import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:carbon_icons/carbon_icons.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../theme/theme_manager.dart';
import '../../widgets/common/title_widget.dart';
import '../../widgets/common/top_action_bar_widget.dart';
import '../../widgets/common/common_buttons.dart';
import '../../../data/services/auth_service.dart';
import '../../../data/services/relay_service.dart';
import '../../widgets/common/snackbar_widget.dart';
import '../../../src/rust/api/relay.dart' as rust_relay;
import '../../../utils/logout.dart';
import '../../../l10n/app_localizations.dart';

class EventManagerPage extends StatefulWidget {
  const EventManagerPage({super.key});

  @override
  State<EventManagerPage> createState() => _EventManagerPageState();
}

class _EventManagerPageState extends State<EventManagerPage> {
  late ScrollController _scrollController;
  final ValueNotifier<bool> _showTitleBubble = ValueNotifier(false);

  bool _isLoading = false;
  bool _isRebroadcasting = false;
  bool _isExporting = false;
  int _broadcastSent = 0;
  int _broadcastTotal = 0;
  StreamSubscription<Map<String, dynamic>>? _broadcastSubscription;
  int _totalEventCount = 0;
  final Map<int, int> _eventCountsByKind = {};
  final List<Map<String, dynamic>> _allEvents = [];
  final Set<String> _seenEventIds = {};
  StreamSubscription<Map<String, dynamic>>? _scanSubscription;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController()..addListener(_scrollListener);
    _fetchAllEvents();
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
    _scanSubscription?.cancel();
    _broadcastSubscription?.cancel();
    _scrollController.dispose();
    _showTitleBubble.dispose();
    super.dispose();
  }

  Future<void> _fetchAllEvents() async {
    _scanSubscription?.cancel();

    setState(() {
      _isLoading = true;
      _totalEventCount = 0;
      _eventCountsByKind.clear();
      _allEvents.clear();
      _seenEventIds.clear();
    });

    final pubkeyHex = AuthService.instance.currentUserPubkeyHex;
    if (pubkeyHex == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    _scanSubscription =
        RustRelayService.instance.fetchAllEventsForAuthor(pubkeyHex).listen(
      (event) {
        if (!mounted) return;
        final id = event['id'] as String?;
        if (id == null || _seenEventIds.contains(id)) return;
        _seenEventIds.add(id);
        final kind = event['kind'] as int?;
        setState(() {
          _allEvents.add(event);
          _totalEventCount++;
          if (kind != null) {
            _eventCountsByKind[kind] = (_eventCountsByKind[kind] ?? 0) + 1;
          }
        });
      },
      onDone: () {
        if (mounted) setState(() => _isLoading = false);
      },
      onError: (_) {
        if (mounted) setState(() => _isLoading = false);
      },
    );
  }

  Future<void> _rebroadcastAllEvents() async {
    final l10n = AppLocalizations.of(context)!;
    if (_allEvents.isEmpty) {
      AppSnackbar.info(context, l10n.noEventsToRebroadcast);
      return;
    }

    _broadcastSubscription?.cancel();

    setState(() {
      _isRebroadcasting = true;
      _broadcastSent = 0;
      _broadcastTotal = _allEvents.length;
    });

    final completer = Completer<void>();

    _broadcastSubscription =
        RustRelayService.instance.streamBroadcastEvents(_allEvents).listen(
      (progress) {
        if (!mounted) return;
        final sent = progress['sent'] as int? ?? 0;
        final done = progress['done'] as bool? ?? false;
        setState(() => _broadcastSent = sent);
        if (done) {
          final failed = progress['failed'] as int? ?? 0;
          setState(() => _isRebroadcasting = false);
          AppSnackbar.success(
            context,
            failed > 0
                ? l10n.broadcastedEventsWithFailed(sent, failed)
                : l10n.broadcastedEvents(sent),
          );
          if (!completer.isCompleted) completer.complete();
        }
      },
      onDone: () {
        if (mounted) setState(() => _isRebroadcasting = false);
        if (!completer.isCompleted) completer.complete();
      },
      onError: (e) {
        if (mounted) {
          setState(() => _isRebroadcasting = false);
          AppSnackbar.error(
            context,
            AppLocalizations.of(context)!
                .errorRebroadcastingEventsDetail(e.toString()),
          );
        }
        if (!completer.isCompleted) completer.complete();
      },
    );

    await completer.future;
  }

  Future<void> _exportAllEvents() async {
    final l10n = AppLocalizations.of(context)!;
    if (_allEvents.isEmpty) {
      AppSnackbar.info(context, l10n.noEventsToExport);
      return;
    }

    setState(() => _isExporting = true);

    try {
      final pubkeyHex = AuthService.instance.currentUserPubkeyHex ?? 'unknown';
      final timestamp = DateTime.now()
          .toUtc()
          .toIso8601String()
          .replaceAll(':', '-')
          .split('.')
          .first;
      final fileName =
          'nostr-export-${pubkeyHex.substring(0, 8)}-$timestamp.json';

      final json = const JsonEncoder.withIndent('  ').convert(_allEvents);

      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/$fileName');
      await file.writeAsString(json, encoding: utf8);

      if (!mounted) return;

      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'application/json')],
          subject: fileName,
        ),
      );
    } catch (e) {
      if (mounted) {
        AppSnackbar.error(
          context,
          AppLocalizations.of(context)!.exportFailed(e.toString()),
        );
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  void _showDeleteAccountDialog() {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.colors;
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: colors.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (modalContext) => Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          bottom: MediaQuery.of(modalContext).viewInsets.bottom + 40,
          top: 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l10n.deleteAccountTitle,
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              l10n.deleteAccountConfirmation,
              style: TextStyle(color: colors.textSecondary, fontSize: 14),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: SecondaryButton(
                    label: l10n.cancel,
                    onPressed: () => Navigator.pop(modalContext),
                    size: ButtonSize.large,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SecondaryButton(
                    label: l10n.delete,
                    onPressed: () {
                      Navigator.pop(modalContext);
                      _deleteAccount();
                    },
                    backgroundColor: colors.error.withValues(alpha: 0.1),
                    foregroundColor: colors.error,
                    size: ButtonSize.large,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteAccount() async {
    final l10n = AppLocalizations.of(context)!;
    setState(() => _isRebroadcasting = true);

    try {
      if (_allEvents.isEmpty) {
        if (mounted) {
          AppSnackbar.error(context, l10n.noEventsFoundToDelete);
          setState(() => _isRebroadcasting = false);
        }
        return;
      }

      final eventIds = _allEvents
          .map((e) => e['id'] as String? ?? '')
          .where((id) => id.isNotEmpty)
          .toList();

      if (eventIds.isEmpty) {
        if (mounted) {
          AppSnackbar.error(context, l10n.noValidEventIds);
          setState(() => _isRebroadcasting = false);
        }
        return;
      }

      final deleteResultJson = await rust_relay.deleteEvents(
        eventIds: eventIds,
        reason: 'User requested account deletion',
      );

      if (!mounted) return;

      final deleteResult = jsonDecode(deleteResultJson) as Map<String, dynamic>;
      final deleteSuccess = deleteResult['totalSuccess'] as int? ?? 0;

      if (deleteSuccess > 0) {
        AppSnackbar.success(
          context,
          deleteSuccess == 1
              ? l10n.deletionRequestSent(eventIds.length, deleteSuccess)
              : l10n.deletionRequestSentPlural(eventIds.length, deleteSuccess),
        );
      }

      await Future.delayed(const Duration(milliseconds: 500));

      final vanishResultJson = await rust_relay.requestToVanish(
        relayUrls: ['ALL_RELAYS'],
        reason: 'User requested account deletion',
      );

      if (!mounted) return;

      final vanishResult = jsonDecode(vanishResultJson) as Map<String, dynamic>;
      final vanishSuccess = vanishResult['totalSuccess'] as int? ?? 0;

      if (vanishSuccess > 0) {
        AppSnackbar.success(
          context,
          vanishSuccess == 1
              ? l10n.accountDeletionRequestSent(vanishSuccess)
              : l10n.accountDeletionRequestSentPlural(vanishSuccess),
        );

        await Future.delayed(const Duration(seconds: 2));

        if (mounted) {
          await Logout.performLogout(context);
        }
      } else {
        final vanishFailed = vanishResult['totalFailed'] as int? ?? 0;
        AppSnackbar.error(
          context,
          vanishFailed == 1
              ? l10n.vanishRequestFailed(vanishFailed)
              : l10n.vanishRequestFailedPlural(vanishFailed),
        );
      }
    } catch (e) {
      if (mounted) {
        AppSnackbar.error(
          context,
          AppLocalizations.of(context)!.errorDeletingAccount(e.toString()),
        );
      }
    } finally {
      if (mounted) setState(() => _isRebroadcasting = false);
    }
  }

  String _getKindName(AppLocalizations l10n, int kind) {
    switch (kind) {
      case 0:
        return l10n.kindProfileMetadata;
      case 1:
        return l10n.kindTextNote;
      case 3:
        return l10n.kindFollows;
      case 4:
        return l10n.kindEncryptedDM;
      case 5:
        return l10n.kindEventDeletion;
      case 6:
        return l10n.kindRepost;
      case 7:
        return l10n.kindReaction;
      case 9735:
        return l10n.kindZap;
      case 10000:
        return l10n.kindMuteList;
      case 10002:
        return l10n.kindRelayList;
      default:
        if (kind >= 10000 && kind <= 10010) {
          return l10n.kindList(kind);
        }
        return l10n.kindUnknown(kind);
    }
  }

  IconData _getKindIcon(int kind) {
    switch (kind) {
      case 0:
        return CarbonIcons.user;
      case 1:
        return CarbonIcons.document;
      case 3:
        return CarbonIcons.user_multiple;
      case 4:
        return CarbonIcons.locked;
      case 5:
        return CarbonIcons.trash_can;
      case 6:
        return CarbonIcons.repeat;
      case 7:
        return CarbonIcons.favorite;
      case 9735:
        return CarbonIcons.flash;
      case 10000:
        return CarbonIcons.notification_off;
      case 10002:
        return CarbonIcons.network_3;
      default:
        return CarbonIcons.document_blank;
    }
  }

  String _formatNumber(int number) {
    if (number >= 1000000) {
      return '${(number / 1000000).toStringAsFixed(1)}M';
    } else if (number >= 1000) {
      return '${(number / 1000).toStringAsFixed(1)}K';
    }
    return number.toString();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: context.colors.background,
      body: Stack(
        children: [
          CustomScrollView(
            controller: _scrollController,
            slivers: [
              SliverToBoxAdapter(
                child: SizedBox(
                  height: MediaQuery.of(context).padding.top + 60,
                ),
              ),
              SliverToBoxAdapter(
                child: TitleWidget(
                  title: l10n.yourDataOnRelays,
                  subtitle: l10n.yourDataOnRelaysDescription,
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: PrimaryButton(
                    label: _isRebroadcasting
                        ? l10n.broadcastProgress(
                            _broadcastSent, _broadcastTotal)
                        : l10n.rebroadcast,
                    icon: _isRebroadcasting ? null : Icons.send,
                    onPressed: (_isLoading || _isRebroadcasting || _isExporting)
                        ? null
                        : _rebroadcastAllEvents,
                    size: ButtonSize.large,
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: SecondaryButton(
                    label: _isExporting ? l10n.exporting : l10n.exportData,
                    icon: CarbonIcons.export,
                    onPressed: (_isLoading || _isRebroadcasting || _isExporting)
                        ? null
                        : _exportAllEvents,
                    isLoading: _isExporting,
                    size: ButtonSize.large,
                    backgroundColor: context.colors.overlayLight,
                    foregroundColor: context.colors.textPrimary,
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate((context, index) {
                    if (index == 0) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Row(
                          children: [
                            if (_isLoading)
                              SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: context.colors.textSecondary,
                                ),
                              )
                            else
                              Icon(
                                CarbonIcons.data_connected,
                                color: context.colors.textSecondary,
                                size: 20,
                              ),
                            const SizedBox(width: 8),
                            Text(
                              _isLoading
                                  ? l10n.scanningEventsFound(
                                      _formatNumber(_totalEventCount))
                                  : l10n.eventsOnRelays(
                                      _formatNumber(_totalEventCount)),
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                                color: context.colors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      );
                    }

                    final sortedKinds = _eventCountsByKind.keys.toList()
                      ..sort();
                    if (index - 1 >= sortedKinds.length) {
                      return const SizedBox.shrink();
                    }

                    final kind = sortedKinds[index - 1];
                    final count = _eventCountsByKind[kind] ?? 0;

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: context.colors.overlayLight,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              _getKindIcon(kind),
                              color: context.colors.textPrimary,
                              size: 20,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                _getKindName(l10n, kind),
                                style: TextStyle(
                                  fontSize: 16,
                                  color: context.colors.textPrimary,
                                ),
                              ),
                            ),
                            Text(
                              _formatNumber(count),
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: context.colors.textPrimary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }, childCount: _eventCountsByKind.length + 1),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                  child: SecondaryButton(
                    label: l10n.deleteAccount,
                    icon: Icons.delete_forever,
                    onPressed: (_isLoading || _isRebroadcasting || _isExporting)
                        ? null
                        : _showDeleteAccountDialog,
                    size: ButtonSize.large,
                    backgroundColor: context.colors.error.withValues(
                      alpha: 0.1,
                    ),
                    foregroundColor: context.colors.error,
                  ),
                ),
              ),
            ],
          ),
          TopActionBarWidget(
            onBackPressed: () => context.pop(),
            centerBubble: Text(
              l10n.yourDataOnRelays,
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
