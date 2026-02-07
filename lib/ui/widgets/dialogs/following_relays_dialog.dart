import 'package:flutter/material.dart';
import '../../theme/theme_manager.dart';
import '../common/common_buttons.dart';
import '../../../core/di/app_di.dart';
import '../../../data/repositories/following_repository.dart';
import '../../../data/repositories/profile_repository.dart';
import '../../../data/services/auth_service.dart';
import '../../../data/services/relay_service.dart';
import '../../../constants/relays.dart';
import 'dart:convert';

class RelayUsageStats {
  final String relayUrl;
  final int userCount;
  final List<String> userPubkeys;

  RelayUsageStats({
    required this.relayUrl,
    required this.userCount,
    required this.userPubkeys,
  });
}

String _normalizeRelayUrl(String url) {
  final trimmed = url.trim();
  if (trimmed.endsWith('/') && !trimmed.endsWith('://')) {
    return trimmed.substring(0, trimmed.length - 1);
  }
  return trimmed;
}

Future<void> showFollowingRelaysDialog({
  required BuildContext context,
  required Future<void> Function(String relayUrl) onAddRelay,
  required List<String> currentRelays,
}) async {
  final colors = context.colors;

  return showModalBottomSheet(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: colors.background,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (modalContext) => _FollowingRelaysDialogContent(
      onAddRelay: onAddRelay,
      currentRelays: currentRelays,
    ),
  );
}

class _FollowingRelaysDialogContent extends StatefulWidget {
  final Future<void> Function(String relayUrl) onAddRelay;
  final List<String> currentRelays;

  const _FollowingRelaysDialogContent({
    required this.onAddRelay,
    required this.currentRelays,
  });

  @override
  State<_FollowingRelaysDialogContent> createState() =>
      _FollowingRelaysDialogContentState();
}

class _FollowingRelaysDialogContentState
    extends State<_FollowingRelaysDialogContent> {
  bool _isLoading = true;
  List<RelayUsageStats> _relayStats = [];
  final Map<String, bool> _addingRelays = {};

  @override
  void initState() {
    super.initState();
    _fetchFollowingRelays();
  }

  Future<void> _fetchFollowingRelays() async {
    setState(() => _isLoading = true);

    try {
      final authService = AppDI.get<AuthService>();
      final followingRepo = AppDI.get<FollowingRepository>();
      final profileRepo = AppDI.get<ProfileRepository>();

      final currentUserHex = authService.currentUserPubkeyHex;
      if (currentUserHex == null) {
        if (mounted) {
          setState(() => _isLoading = false);
        }
        return;
      }

      final followingPubkeys =
          await followingRepo.getFollowingList(currentUserHex);
      if (followingPubkeys == null || followingPubkeys.isEmpty) {
        if (mounted) {
          setState(() => _isLoading = false);
        }
        return;
      }

      final profiles = await profileRepo.getProfiles(followingPubkeys);
      final followingUsers = profiles.values.toList();
      if (followingUsers.isEmpty) {
        if (mounted) {
          setState(() => _isLoading = false);
        }
        return;
      }

      final relayUsageMap = <String, List<String>>{};

      final manager = WebSocketManager.instance;
      final pubkeyHexList = followingUsers
          .map((user) {
            try {
              final userPubkeyHex = user.pubkey;
              final hex = authService.npubToHex(userPubkeyHex);
              return hex ?? userPubkeyHex;
            } catch (_) {
              return user.pubkey;
            }
          })
          .where((hex) => hex.isNotEmpty)
          .toList();

      final processedUsers = <String>{};
      final subscriptionId = DateTime.now().millisecondsSinceEpoch.toString();

      for (final relayUrl in relaySetMainSockets.take(5)) {
        if (!mounted) return;

        try {
          final filter = {
            'authors': pubkeyHexList,
            'kinds': [10002],
            'limit': pubkeyHexList.length,
          };

          final request = jsonEncode(['REQ', subscriptionId, filter]);

          final completer = await manager.sendQuery(
            relayUrl,
            request,
            subscriptionId,
            timeout: const Duration(seconds: 5),
            onEvent: (data, url) {
              if (!mounted) return;

              try {
                final eventAuthor = data['pubkey'] as String?;
                if (eventAuthor == null ||
                    processedUsers.contains(eventAuthor)) {
                  return;
                }

                processedUsers.add(eventAuthor);
                final tags = data['tags'] as List<dynamic>? ?? [];

                for (final tag in tags) {
                  if (tag is List &&
                      tag.isNotEmpty &&
                      tag[0] == 'r' &&
                      tag.length >= 2) {
                    final relayUrl = tag[1] as String;
                    if (!relayUsageMap.containsKey(relayUrl)) {
                      relayUsageMap[relayUrl] = [];
                    }
                    if (!relayUsageMap[relayUrl]!.contains(eventAuthor)) {
                      relayUsageMap[relayUrl]!.add(eventAuthor);
                    }
                  }
                }
              } catch (_) {}
            },
          );

          await completer.future
              .timeout(const Duration(seconds: 5), onTimeout: () {});
        } catch (_) {}
      }

      final normalizedCurrentRelays =
          widget.currentRelays.map(_normalizeRelayUrl).toSet();

      final stats = relayUsageMap.entries.where((entry) {
        final normalizedUrl = _normalizeRelayUrl(entry.key);
        return !normalizedCurrentRelays.contains(normalizedUrl);
      }).map((entry) {
        return RelayUsageStats(
          relayUrl: entry.key,
          userCount: entry.value.length,
          userPubkeys: entry.value,
        );
      }).toList();

      stats.sort((a, b) => b.userCount.compareTo(a.userCount));

      if (mounted) {
        setState(() {
          _relayStats = stats;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Widget _buildCancelButton(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      label: 'Close dialog',
      button: true,
      child: GestureDetector(
        onTap: () => Navigator.of(context).pop(),
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: colors.overlayLight,
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.close,
            size: 20,
            color: colors.textPrimary,
          ),
        ),
      ),
    );
  }

  Future<void> _handleAddRelay(String relayUrl) async {
    if (_addingRelays[relayUrl] == true) return;

    setState(() {
      _addingRelays[relayUrl] = true;
    });

    try {
      await widget.onAddRelay(relayUrl);
      if (mounted) {
        Navigator.of(context).pop();
      }
    } finally {
      if (mounted) {
        setState(() {
          _addingRelays[relayUrl] = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.8,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Relays from your follows',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: colors.textPrimary,
                    ),
                  ),
                ),
                _buildCancelButton(context),
              ],
            ),
          ),
          if (_isLoading)
            Padding(
              padding: const EdgeInsets.all(40),
              child: Center(
                child: CircularProgressIndicator(color: colors.textPrimary),
              ),
            )
          else if (_relayStats.isEmpty)
            Padding(
              padding: const EdgeInsets.all(40),
              child: Center(
                child: Text(
                  'No relays found from following users',
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: 15,
                  ),
                ),
              ),
            )
          else
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                itemCount: _relayStats.length,
                itemBuilder: (context, index) {
                  final stat = _relayStats[index];
                  final isAdding = _addingRelays[stat.relayUrl] == true;

                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: colors.overlayLight,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  stat.relayUrl,
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: colors.textPrimary,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Used by ${stat.userCount} user${stat.userCount != 1 ? 's' : ''}',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: colors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          SizedBox(
                            width: 80,
                            child: SecondaryButton(
                              label: isAdding ? 'Adding...' : 'Add',
                              onPressed: isAdding
                                  ? null
                                  : () => _handleAddRelay(stat.relayUrl),
                              isLoading: isAdding,
                              size: ButtonSize.small,
                              backgroundColor: colors.background,
                              foregroundColor: colors.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
