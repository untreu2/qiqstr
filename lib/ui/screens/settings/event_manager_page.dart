import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../theme/theme_manager.dart';
import '../../widgets/common/title_widget.dart';
import '../../widgets/common/top_action_bar_widget.dart';
import '../../widgets/common/common_buttons.dart';
import '../../../data/services/event_counts_service.dart';
import '../../widgets/common/snackbar_widget.dart';

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
  int _totalEventCount = 0;
  Map<int, int> _eventCountsByKind = {};
  final List<Map<String, dynamic>> _allEvents = [];

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
    _scrollController.dispose();
    _showTitleBubble.dispose();
    super.dispose();
  }

  Future<void> _fetchAllEvents() async {
    setState(() {
      _isLoading = true;
      _totalEventCount = 0;
      _eventCountsByKind.clear();
      _allEvents.clear();
    });

    try {
      final result =
          await EventCountsService.instance.fetchAllEventsForUser(null);

      if (!mounted) return;

      if (result != null) {
        setState(() {
          _totalEventCount = result.totalCount;
          _eventCountsByKind = result.countsByKind;
          _allEvents.addAll(result.allEvents);
          _isLoading = false;
        });
      } else {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _rebroadcastAllEvents() async {
    if (_allEvents.isEmpty) {
      AppSnackbar.info(context, 'No events to rebroadcast');
      return;
    }

    setState(() {
      _isRebroadcasting = true;
    });

    try {
      final success =
          await EventCountsService.instance.rebroadcastEvents(_allEvents);

      if (!mounted) return;

      if (success) {
        AppSnackbar.success(
          context,
          'Rebroadcasted ${_allEvents.length} events to relays',
        );
      } else {
        AppSnackbar.error(context, 'Error rebroadcasting events');
      }
    } catch (e) {
      if (mounted) {
        AppSnackbar.error(context, 'Error rebroadcasting events: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isRebroadcasting = false;
        });
      }
    }
  }

  String _getKindName(int kind) {
    switch (kind) {
      case 0:
        return 'Profile Metadata';
      case 1:
        return 'Text Note';
      case 3:
        return 'Follows';
      case 4:
        return 'Encrypted Direct Message';
      case 5:
        return 'Event Deletion';
      case 6:
        return 'Repost';
      case 7:
        return 'Reaction';
      case 9735:
        return 'Zap';
      case 10000:
        return 'Mute List';
      case 10002:
        return 'Relay List';
      default:
        if (kind >= 10000 && kind <= 10010) {
          return 'List (kind $kind)';
        }
        return 'Kind $kind';
    }
  }

  @override
  Widget build(BuildContext context) {
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
                child: const TitleWidget(
                  title: 'Your Data on Relays',
                  subtitle:
                      'Everything you share on Nostr is an event. View your event counts by kind and rebroadcast them to relays.',
                  padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: PrimaryButton(
                    label:
                        _isRebroadcasting ? 'Rebroadcasting...' : 'Rebroadcast',
                    icon: Icons.send,
                    onPressed: (_isLoading || _isRebroadcasting)
                        ? null
                        : _rebroadcastAllEvents,
                    isLoading: _isRebroadcasting,
                    size: ButtonSize.large,
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      if (index == 0) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: Text(
                            _isLoading
                                ? 'Loading events...'
                                : 'You have $_totalEventCount event${_totalEventCount != 1 ? 's' : ''}',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: context.colors.textSecondary,
                            ),
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

                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: context.colors.overlayLight,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                _getKindName(kind),
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: context.colors.textPrimary,
                                ),
                              ),
                            ),
                            Text(
                              '$count',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: context.colors.textPrimary,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                    childCount: _eventCountsByKind.length + 1,
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
              'Your Data on Relays',
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
