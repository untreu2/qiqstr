import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../src/rust/api/events.dart' as rust_events;
import 'package:carbon_icons/carbon_icons.dart';
import 'dart:convert';
import 'dart:async';
import '../../theme/theme_manager.dart';
import '../../../constants/relays.dart';
import '../../../data/services/auth_service.dart';
import '../../../data/services/nostr_service.dart';
import '../../../data/services/relay_service.dart';
import '../../widgets/common/common_buttons.dart';
import '../../widgets/common/snackbar_widget.dart';
import '../../widgets/common/title_widget.dart';
import '../../widgets/common/top_action_bar_widget.dart';
import '../../widgets/dialogs/reset_relays_dialog.dart';
import '../../widgets/dialogs/add_relay_dialog.dart';
import '../../../l10n/app_localizations.dart';
import '../../widgets/dialogs/broadcast_events_dialog.dart';
import '../../../data/services/event_counts_service.dart';

class RelayPage extends StatefulWidget {
  const RelayPage({super.key});

  @override
  State<RelayPage> createState() => _RelayPageState();
}

class _RelayPageState extends State<RelayPage> {
  final TextEditingController _addRelayController = TextEditingController();
  List<String> _relays = [];
  Map<String, Map<String, bool>> _relayFlags = {};
  List<Map<String, dynamic>> _userRelays = [];
  bool _isLoading = true;
  bool _isAddingRelay = false;
  bool _isFetchingUserRelays = false;
  bool _isPublishingRelays = false;
  bool _disposed = false;
  bool _gossipModelEnabled = false;
  int _connectedRelayCount = 0;
  int _totalRelayCount = 0;
  int _totalBytesSent = 0;
  int _totalBytesReceived = 0;
  final Map<String, Map<String, dynamic>> _relayStats = {};
  late ScrollController _scrollController;
  final ValueNotifier<bool> _showTitleBubble = ValueNotifier(false);

  final AuthService _authService = AuthService.instance;

  @override
  void initState() {
    super.initState();
    _initializeServices();
    _scrollController = ScrollController()..addListener(_scrollListener);
    _loadRelays();
    _loadRelayStats();
    _startStatsRefresh();
  }

  void _scrollListener() {
    if (_scrollController.hasClients) {
      final shouldShow = _scrollController.offset > 100;
      if (_showTitleBubble.value != shouldShow) {
        _showTitleBubble.value = shouldShow;
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _scrollController.dispose();
    _showTitleBubble.dispose();
    _addRelayController.dispose();
    super.dispose();
  }

  void _initializeServices() {}

  void _startStatsRefresh() {
    Timer.periodic(const Duration(seconds: 2), (timer) {
      if (_disposed) {
        timer.cancel();
        return;
      }
      _loadRelayStats();
    });
  }

  void _loadRelayStats() async {
    if (_disposed) return;
    try {
      final status = await RustRelayService.instance.getRelayStatus();
      if (_disposed || !mounted) return;

      final summary = status['summary'] as Map<String, dynamic>?;
      final relays = status['relays'] as List<dynamic>? ?? [];
      final newStats = <String, Map<String, dynamic>>{};
      int bytesSent = 0;
      int bytesReceived = 0;

      for (final relay in relays) {
        final r = relay as Map<String, dynamic>;
        final url = r['url'] as String? ?? '';
        if (url.isNotEmpty) {
          newStats[url] = r;
          bytesSent += (r['bytesSent'] as int? ?? 0);
          bytesReceived += (r['bytesReceived'] as int? ?? 0);
        }
      }

      setState(() {
        _relayStats.clear();
        _relayStats.addAll(newStats);
        _connectedRelayCount = summary?['connectedRelays'] as int? ?? 0;
        _totalRelayCount = summary?['totalRelays'] as int? ?? 0;
        _totalBytesSent = bytesSent;
        _totalBytesReceived = bytesReceived;
      });
    } catch (_) {}
  }

  Future<void> _loadRelays() async {
    setState(() => _isLoading = true);

    try {
      final prefs = await SharedPreferences.getInstance();

      final customMainRelays = prefs.getStringList('custom_main_relays');
      final userRelaysJson = prefs.getString('user_relays');
      final flagsJson = prefs.getString('relay_flags');
      _gossipModelEnabled = prefs.getBool('gossip_model_enabled') ?? false;

      if (userRelaysJson != null) {
        final List<dynamic> decoded = jsonDecode(userRelaysJson);
        _userRelays = decoded.cast<Map<String, dynamic>>();
      }

      Map<String, Map<String, bool>> loadedFlags = {};
      if (flagsJson != null) {
        final decoded = jsonDecode(flagsJson) as Map<String, dynamic>;
        for (final entry in decoded.entries) {
          final flags = entry.value as Map<String, dynamic>;
          loadedFlags[entry.key] = {
            'read': flags['read'] as bool? ?? true,
            'write': flags['write'] as bool? ?? true,
          };
        }
      }

      final relays = customMainRelays ?? List.from(relaySetMainSockets);

      for (final relay in relays) {
        loadedFlags.putIfAbsent(relay, () => {'read': true, 'write': true});
      }

      setState(() {
        _relays = relays;
        _relayFlags = loadedFlags;
        _isLoading = false;
      });

    } catch (e) {
      setState(() {
        _relays = List.from(relaySetMainSockets);
        _relayFlags = {};
        for (final relay in _relays) {
          _relayFlags[relay] = {'read': true, 'write': true};
        }
        _isLoading = false;
      });
      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
        AppSnackbar.error(context, '${l10n.errorLoadingRelays}: ${e.toString()}');
      }
    }
  }

  Future<void> _publishRelays() async {
    if (!mounted) return;

    setState(() {
      _isPublishingRelays = true;
    });

    try {
      final privateKeyResult = await _authService.getCurrentUserPrivateKey();
      if (privateKeyResult.isError || privateKeyResult.data == null) {
        if (mounted) {
          final l10n = AppLocalizations.of(context)!;
          AppSnackbar.error(
              context, l10n.privateKeyNotFound);
        }
        return;
      }

      final npubResult = await _authService.getCurrentUserNpub();
      if (npubResult.isError || npubResult.data == null) {
        if (mounted) {
          final l10n = AppLocalizations.of(context)!;
          AppSnackbar.error(context, l10n.pleaseSetUpYourProfileFirst);
        }
        return;
      }

      final privateKey = privateKeyResult.data!;

      List<String> relayConfigs = [];
      for (String relay in _relays) {
        final flags = _relayFlags[relay] ?? {'read': true, 'write': true};
        final isRead = flags['read'] ?? true;
        final isWrite = flags['write'] ?? true;

        if (isRead && isWrite) {
          relayConfigs.add(relay);
        } else if (isRead) {
          relayConfigs.add('$relay|read');
        } else if (isWrite) {
          relayConfigs.add('$relay|write');
        }
      }

      final eventJsonStr = rust_events.createRelayListEventWithMarkers(
        relayConfigs: relayConfigs,
        privateKeyHex: privateKey,
      );
      final event = jsonDecode(eventJsonStr) as Map<String, dynamic>;

      final serializedEvent = NostrService.serializeEvent(event);

      await _broadcastRelayListEvent(serializedEvent);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('published_relay_list', jsonEncode(event));

      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
        AppSnackbar.success(context,
            '${l10n.relayListPublishedSuccessfully} (${relayConfigs.length} relays in list)');
      }

      if (kDebugMode) {
        print('Relay list event published: ${event['id']}');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error publishing relays: $e');
      }
      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
        AppSnackbar.error(
            context, '${l10n.errorPublishingRelayList}: ${e.toString()}');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isPublishingRelays = false;
        });
      }
    }
  }

  Future<void> _broadcastRelayListEvent(String serializedEvent) async {
    try {
      final decoded = jsonDecode(serializedEvent) as List<dynamic>;
      if (decoded.isNotEmpty && decoded[0] == 'EVENT' && decoded.length >= 2) {
        final eventData = decoded[1] as Map<String, dynamic>;
        final eventJson = jsonEncode(eventData);
        await RustRelayService.instance.sendEvent(eventJson);
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error during relay list broadcast: $e');
      }
    }
  }

  Future<void> _fetchUserRelays() async {
    setState(() {
      _isFetchingUserRelays = true;
    });

    try {
      final npubResult = await _authService.getCurrentUserNpub();
      if (npubResult.isError || npubResult.data == null) {
        throw Exception('User not logged in');
      }

      final npub = npubResult.data!;
      final userRelayList = await _fetchRelayListMetadata(npub);

      if (userRelayList.isNotEmpty) {
        setState(() {
          _userRelays = userRelayList;
        });

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('user_relays', jsonEncode(_userRelays));

        await _useUserRelays();

        if (mounted) {
          final l10n = AppLocalizations.of(context)!;
          AppSnackbar.success(context,
              '${l10n.relayListFetchedSuccessfully} (${_userRelays.length} relays)');
        }
      } else {
        if (mounted) {
          final l10n = AppLocalizations.of(context)!;
          AppSnackbar.info(context, l10n.noRelayListFoundInYourProfile);
        }
      }
    } catch (e) {
      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
        AppSnackbar.error(
            context, '${l10n.errorFetchingRelayList}: ${e.toString()}');
      }
    } finally {
      setState(() {
        _isFetchingUserRelays = false;
      });
    }
  }

  Future<List<Map<String, dynamic>>> _fetchRelayListMetadata(
      String npub) async {
    final List<Map<String, dynamic>> relayList = [];

    try {
      final pubkeyHex = _authService.npubToHex(npub) ?? npub;

      final filter = {
        'authors': [pubkeyHex],
        'kinds': [10002],
        'limit': 1,
      };

      final events = await RustRelayService.instance.fetchEvents(filter, timeoutSecs: 10);

      if (events.isNotEmpty) {
        final eventData = events.first;
        final tags = eventData['tags'] as List<dynamic>? ?? [];

        for (final tag in tags) {
          if (tag is List &&
              tag.isNotEmpty &&
              tag[0] == 'r' &&
              tag.length >= 2) {
            final relayUrl = tag[1] as String;
            String marker = '';

            if (tag.length >= 3 && tag[2] is String) {
              marker = tag[2] as String;
            }

            if (marker.isEmpty) {
              marker = 'read,write';
            }

            relayList.add({
              'url': relayUrl,
              'marker': marker,
            });
          }
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error in _fetchRelayListMetadata: $e');
      }
    }

    return relayList;
  }

  Future<void> _useUserRelays() async {
    if (_userRelays.isEmpty) {
      final l10n = AppLocalizations.of(context)!;
      AppSnackbar.info(
          context, l10n.noRelayListFoundInYourProfile);
      return;
    }

    try {
      final previousRelays = Set<String>.from(_relays.map(_normalizeRelayUrl));

      final newRelays = _userRelays
          .map((relay) => relay['url'] as String)
          .toList();

      final newFlags = <String, Map<String, bool>>{};
      for (final relay in _userRelays) {
        final url = relay['url'] as String;
        final marker = relay['marker'] as String? ?? '';

        if (marker == 'read') {
          newFlags[url] = {'read': true, 'write': false};
        } else if (marker == 'write') {
          newFlags[url] = {'read': false, 'write': true};
        } else {
          newFlags[url] = {'read': true, 'write': true};
        }
      }

      setState(() {
        _relays = newRelays;
        _relayFlags = newFlags;
      });

      await _saveRelays();

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('using_user_relays', true);

      if (mounted) {
        AppSnackbar.success(context,
            'Now using your personal relays (${newRelays.length} main relays)');

        final newRelayUrls = newRelays
            .where(
                (relay) => !previousRelays.contains(_normalizeRelayUrl(relay)))
            .toList();

        if (newRelayUrls.isNotEmpty && mounted) {
          final shouldBroadcast = await showBroadcastEventsDialog(
            context: context,
            relayUrls: newRelayUrls,
            relayCount: newRelayUrls.length,
          );

          if (shouldBroadcast && mounted) {
            await _broadcastEventsToRelays(newRelayUrls);
          }
        }
      }
    } catch (e) {
      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
        AppSnackbar.error(
            context, '${l10n.errorSavingRelays}: ${e.toString()}');
      }
    }
  }

  Future<void> _saveRelays() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('custom_main_relays', _relays);
      await prefs.setString('relay_flags', jsonEncode(_relayFlags));

      await RustRelayService.instance.reloadCustomRelays();

      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
        AppSnackbar.success(context, l10n.relaysSavedSuccessfully);
      }
    } catch (e) {
      if (kDebugMode) {
        print('[RelayPage] Error saving relays: $e');
      }
      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
        AppSnackbar.error(context, '${l10n.errorSavingRelays}: ${e.toString()}');
      }
    }
  }

  bool _isValidRelayUrl(String url) {
    final trimmed = url.trim();
    return trimmed.startsWith('wss://') || trimmed.startsWith('ws://');
  }

  String _normalizeRelayUrl(String url) {
    final trimmed = url.trim();
    if (trimmed.endsWith('/') && !trimmed.endsWith('://')) {
      return trimmed.substring(0, trimmed.length - 1);
    }
    return trimmed;
  }

  bool _isRelayUrlEqual(String url1, String url2) {
    return _normalizeRelayUrl(url1) == _normalizeRelayUrl(url2);
  }

  Future<void> _addRelay(bool isMainRelay) async {
    final url = _addRelayController.text.trim();

    if (url.isEmpty) {
      final l10n = AppLocalizations.of(context)!;
      AppSnackbar.error(context, l10n.pleaseEnterRelayUrl);
      return;
    }

    if (!_isValidRelayUrl(url)) {
      final l10n = AppLocalizations.of(context)!;
      AppSnackbar.error(
          context, l10n.invalidRelayUrl);
      return;
    }

    final targetList = _relays;
    final normalizedUrl = _normalizeRelayUrl(url);

    if (targetList
        .any((existingUrl) => _isRelayUrlEqual(existingUrl, normalizedUrl))) {
      final l10n = AppLocalizations.of(context)!;
      AppSnackbar.error(context, l10n.relayAlreadyExistsInCategory);
      return;
    }

    setState(() => _isAddingRelay = true);

    try {
      setState(() {
        targetList.add(url);
        _relayFlags[url] = {'read': true, 'write': true};
      });

      await _saveRelays();
      _addRelayController.clear();

      if (mounted) {
        context.pop();
        final l10n = AppLocalizations.of(context)!;
        AppSnackbar.success(context, l10n.relayAddedToMainList);

        final shouldBroadcast = await showBroadcastEventsDialog(
          context: context,
          relayUrl: normalizedUrl,
        );

        if (shouldBroadcast && mounted) {
          await _broadcastEventsToRelay(normalizedUrl);
        }
      }
    } catch (e) {
      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
        AppSnackbar.error(context, '${l10n.errorAddingRelay}: ${e.toString()}');
      }
    } finally {
      setState(() => _isAddingRelay = false);
    }
  }

  Future<void> _broadcastEventsToRelay(String relayUrl) async {
    await _broadcastEventsToRelays([relayUrl]);
  }

  Future<void> _broadcastEventsToRelays(List<String> relayUrls) async {
    if (!mounted || relayUrls.isEmpty) return;

    final l10n = AppLocalizations.of(context)!;
    AppSnackbar.info(context, l10n.fetchingYourEvents);

    try {
      final result =
          await EventCountsService.instance.fetchAllEventsForUser(null);

      if (!mounted) return;

      if (result == null || result.allEvents.isEmpty) {
        AppSnackbar.info(context, l10n.noEventsFoundToBroadcast);
        return;
      }

      AppSnackbar.info(
          context, l10n.broadcastingEvents(result.allEvents.length, relayUrls.length));

      final success = await EventCountsService.instance.rebroadcastEvents(
        result.allEvents,
        relayUrls: relayUrls,
      );

      if (!mounted) return;

      if (success) {
        AppSnackbar.success(
          context,
          l10n.eventsSuccessfullyBroadcast(result.allEvents.length, relayUrls.length),
        );
      } else {
        AppSnackbar.error(context, l10n.errorBroadcastingEvents);
      }
    } catch (e) {
      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
        AppSnackbar.error(
            context, '${l10n.errorBroadcastingEvents}: ${e.toString()}');
      }
    }
  }

  Future<void> _removeRelay(String url, bool isMainRelay) async {
    setState(() {
      _relays.remove(url);
      _relayFlags.remove(url);
    });

    await _saveRelays();

    if (mounted) {
      final l10n = AppLocalizations.of(context)!;
      AppSnackbar.success(context, l10n.relayRemovedSuccessfully);
    }
  }

  Future<void> _resetToDefaults() async {
    await showResetRelaysDialog(
      context: context,
      onConfirm: () async {
        final previousRelays =
            Set<String>.from(_relays.map(_normalizeRelayUrl));

        final defaultFlags = <String, Map<String, bool>>{};
        for (final relay in relaySetMainSockets) {
          defaultFlags[relay] = {'read': true, 'write': true};
        }

        setState(() {
          _relays = List.from(relaySetMainSockets);
          _relayFlags = defaultFlags;
        });
        await _saveRelays();

        if (mounted && context.mounted) {
          final l10n = AppLocalizations.of(context)!;
          AppSnackbar.success(context, l10n.relaysResetToDefaults);

          final newRelayUrls = _relays
              .where((relay) =>
                  !previousRelays.contains(_normalizeRelayUrl(relay)))
              .toList();

          if (newRelayUrls.isNotEmpty && mounted) {
            final shouldBroadcast = await showBroadcastEventsDialog(
              context: context,
              relayUrls: newRelayUrls,
              relayCount: newRelayUrls.length,
            );

            if (shouldBroadcast && mounted) {
              await _broadcastEventsToRelays(newRelayUrls);
            }
          }
        }
      },
    );
  }

  void _showAddRelayDialog() {
    showAddRelayDialog(
      context: context,
      controller: _addRelayController,
      isLoading: _isAddingRelay,
      onAdd: () => _addRelay(true),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    } else if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    } else if (bytes >= 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '$bytes B';
  }

  Widget _buildHeader(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return TitleWidget(
      title: l10n.relays,
      fontSize: 32,
      subtitle: l10n.manageYourRelayConnections,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
    );
  }

  Widget _buildRelayStatsSection(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(
        children: [
          Icon(
            CarbonIcons.network_3,
            color: context.colors.textSecondary,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '$_connectedRelayCount/$_totalRelayCount ${l10n.connected.toLowerCase()} • ${_formatBytes(_totalBytesSent + _totalBytesReceived)}',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: context.colors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGossipModelToggle(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: context.colors.overlayLight,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.gossipMode,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: context.colors.textPrimary,
                    ),
                  ),
                ),
                Switch(
                  value: _gossipModelEnabled,
                  onChanged: (value) async {
                    setState(() {
                      _gossipModelEnabled = value;
                    });
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setBool('gossip_model_enabled', value);
                    if (context.mounted) {
                      final l10n = AppLocalizations.of(context)!;
                      AppSnackbar.success(
                        context,
                        value
                            ? l10n.gossipModelEnabledRestartApp
                            : l10n.gossipModelDisabledRestartApp,
                      );
                    }
                  },
                  activeThumbColor: context.colors.switchActive,
                  inactiveThumbColor: context.colors.textSecondary,
                  inactiveTrackColor: context.colors.border,
                  activeTrackColor: context.colors.switchActive.withValues(alpha: 0.3),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              l10n.gossipModeDescription,
              style: TextStyle(
                fontSize: 13,
                color: context.colors.textSecondary,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context, AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: SecondaryButton(
                  label: _isFetchingUserRelays ? l10n.fetching : l10n.fetch,
                  icon: Icons.download,
                  onPressed: _isFetchingUserRelays ? null : _fetchUserRelays,
                  isLoading: _isFetchingUserRelays,
                  backgroundColor: context.colors.overlayLight,
                  foregroundColor: context.colors.textPrimary,
                  size: ButtonSize.large,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SecondaryButton(
                  label: _isPublishingRelays ? l10n.publishing : l10n.publish,
                  icon: Icons.upload,
                  onPressed: _isPublishingRelays ? null : _publishRelays,
                  isLoading: _isPublishingRelays,
                  backgroundColor: context.colors.overlayLight,
                  foregroundColor: context.colors.textPrimary,
                  size: ButtonSize.large,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: SecondaryButton(
                  label: l10n.addRelay,
                  icon: Icons.add,
                  onPressed: _showAddRelayDialog,
                  backgroundColor: context.colors.overlayLight,
                  foregroundColor: context.colors.textPrimary,
                  size: ButtonSize.large,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SecondaryButton(
                  label: l10n.reset,
                  icon: Icons.refresh,
                  onPressed: _resetToDefaults,
                  backgroundColor: context.colors.overlayLight,
                  foregroundColor: context.colors.textPrimary,
                  size: ButtonSize.large,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRelayTile(String relay, bool isMainRelay, AppLocalizations l10n) {
    final stats = _relayStats[relay];
    final relayStatus = stats?['status'] as String? ?? 'disconnected';
    final isConnected = relayStatus == 'connected';
    final isConnecting = relayStatus == 'connecting' || relayStatus == 'pending';

    return RepaintBoundary(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: context.colors.overlayLight,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isConnected
                    ? Colors.green
                    : isConnecting
                        ? Colors.orange
                        : Colors.red.withValues(alpha: 0.5),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                relay,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: context.colors.textPrimary,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => _removeRelay(relay, isMainRelay),
              child: Icon(
                CarbonIcons.trash_can,
                size: 18,
                color: context.colors.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    if (_isLoading) {
      return Scaffold(
        backgroundColor: context.colors.background,
        body: Center(
          child: CircularProgressIndicator(color: context.colors.textPrimary),
        ),
      );
    }

    final relayWidgets = <Widget>[];
    for (int i = 0; i < _relays.length; i++) {
      relayWidgets.add(Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: _buildRelayTile(_relays[i], true, l10n),
      ));
    }

    return Scaffold(
      backgroundColor: context.colors.background,
      body: Stack(
        children: [
          CustomScrollView(
            controller: _scrollController,
            slivers: [
              SliverToBoxAdapter(
                child:
                    SizedBox(height: MediaQuery.of(context).padding.top + 60),
              ),
              SliverToBoxAdapter(
                child: _buildHeader(context),
              ),
              SliverToBoxAdapter(
                child: _buildRelayStatsSection(context),
              ),
              SliverToBoxAdapter(
                child: _buildActionButtons(context, l10n),
              ),
              SliverToBoxAdapter(
                child: _buildGossipModelToggle(context),
              ),
              if (_relays.isEmpty)
                SliverToBoxAdapter(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 32),
                      child: Text(
                        'No relays in this category',
                        style: TextStyle(color: context.colors.textTertiary),
                      ),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) => relayWidgets[index],
                      childCount: relayWidgets.length,
                      addAutomaticKeepAlives: true,
                      addRepaintBoundaries: false,
                    ),
                  ),
                ),
            ],
          ),
          TopActionBarWidget(
            onBackPressed: () => context.pop(),
            centerBubble: Text(
              'Relays',
              style: TextStyle(
                color: context.colors.background,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            centerBubbleVisibility: _showTitleBubble,
            onCenterBubbleTap: () {
              _scrollController.animateTo(
                0,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut,
              );
            },
            showShareButton: false,
          ),
        ],
      ),
    );
  }
}
