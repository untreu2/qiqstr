import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:nostr_nip19/nostr_nip19.dart';
import 'package:share_plus/share_plus.dart';
import 'package:qiqstr/ui/widgets/note/note_widget.dart';
import 'package:qiqstr/ui/widgets/note/focused_note_widget.dart';
import '../../widgets/common/common_buttons.dart';
import '../../widgets/common/top_action_bar_widget.dart';
import '../../theme/theme_manager.dart';
import '../../../core/di/app_di.dart';
import '../../../presentation/blocs/thread/thread_bloc.dart';
import '../../../presentation/blocs/thread/thread_event.dart';
import '../../../presentation/blocs/thread/thread_state.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'share_note.dart';

class ThreadPage extends StatefulWidget {
  final String rootNoteId;
  final String? focusedNoteId;

  const ThreadPage({
    super.key,
    required this.rootNoteId,
    this.focusedNoteId,
  });

  @override
  State<ThreadPage> createState() => _ThreadPageState();
}

class _ThreadPageState extends State<ThreadPage> {
  late ScrollController _scrollController;
  final Map<String, GlobalKey> _noteKeys = {};
  String? _currentFocusedNoteId;

  int _visibleRepliesCount = 3;
  static const int _repliesPerPage = 5;
  static const int _maxInitialReplies = 10;
  static const int _maxNestedReplies = 1;

  bool _isRefreshing = false;
  Timer? _cacheCheckTimer;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _currentFocusedNoteId = widget.focusedNoteId;
  }

  @override
  void dispose() {
    _cacheCheckTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider<ThreadBloc>(
      create: (context) {
        final bloc = AppDI.get<ThreadBloc>();
        Future.microtask(() {
          if (mounted) {
            bloc.add(ThreadLoadRequested(
              rootNoteId: widget.rootNoteId,
              focusedNoteId: widget.focusedNoteId,
            ));

            if (widget.focusedNoteId != null) {
              Future.delayed(const Duration(milliseconds: 300), () {
                if (mounted) {
                  _scheduleScrollToFocusedNote(widget.focusedNoteId!);
                }
              });
            }
          }
        });
        return bloc;
      },
      child: BlocBuilder<ThreadBloc, ThreadState>(
        buildWhen: (previous, current) {
          if (previous is ThreadLoaded && current is ThreadLoaded) {
            final prevRootNoteId = previous.rootNote['id'] as String? ?? '';
            final currRootNoteId = current.rootNote['id'] as String? ?? '';
            return previous.replies.length != current.replies.length ||
                prevRootNoteId != currRootNoteId ||
                previous.focusedNoteId != current.focusedNoteId;
          }
          return previous.runtimeType != current.runtimeType;
        },
        builder: (context, state) {
          return Scaffold(
            backgroundColor: context.colors.background,
            body: Stack(
              children: [
                _buildContent(context, state),
                TopActionBarWidget(
                  onBackPressed: () => context.pop(),
                  centerBubble: Text(
                    'Thread',
                    style: TextStyle(
                      color: context.colors.background,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  onCenterBubbleTap: () {
                    _scrollController.animateTo(
                      0,
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOut,
                    );
                  },
                  onSharePressed: () => _handleShare(context, state),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildContent(BuildContext context, ThreadState state) {
    if (state is ThreadLoaded) {
      return _buildThreadContent(context, state);
    }

    if (state is ThreadLoading) {
      return _buildLoadingState(context);
    }

    if (state is ThreadError) {
      return _buildErrorState(context, state.message);
    }

    return _buildLoadingState(context);
  }

  Widget _buildLoadingState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(color: context.colors.primary),
          const SizedBox(height: 16),
          Text(
            'Loading thread...',
            style: TextStyle(color: context.colors.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildThreadContent(BuildContext context, ThreadLoaded state) {
    Map<String, dynamic>? displayNote = state.rootNote;
    final focusedNoteId = _currentFocusedNoteId ?? state.focusedNoteId;
    if (focusedNoteId != null) {
      if (state.focusedNote != null) {
        displayNote = state.focusedNote;
      } else {
        displayNote =
            state.threadStructure.getNote(focusedNoteId) ?? state.rootNote;
      }
    }

    return RefreshIndicator(
      onRefresh: () => _debouncedRefresh(context),
      child: CustomScrollView(
        controller: _scrollController,
        slivers: [
          SliverToBoxAdapter(
            child: SizedBox(height: MediaQuery.of(context).padding.top + 68),
          ),
          if (displayNote != null) ...[
            SliverToBoxAdapter(
              child: _buildContextNote(context, state, displayNote),
            ),
            SliverToBoxAdapter(
              child: _buildMainNote(context, state, displayNote),
            ),
            SliverToBoxAdapter(
              child: _buildReplyInputSection(context, state),
            ),
            _buildThreadRepliesSliver(context, state, displayNote),
          ] else ...[
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 32,
                      height: 32,
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        color: context.colors.primary,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Loading thread...',
                      style: TextStyle(
                        color: context.colors.textSecondary,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          SliverToBoxAdapter(
            child:
                SizedBox(height: MediaQuery.of(context).padding.bottom + 120),
          ),
        ],
      ),
    );
  }

  Widget _buildContextNote(BuildContext context, ThreadLoaded state,
      Map<String, dynamic> displayNote) {
    final threadStructure = state.threadStructure;
    final displayNoteId = displayNote['id'] as String? ?? '';
    final rootNoteId = threadStructure.rootNote['id'] as String? ?? '';

    if (displayNoteId == rootNoteId) {
      return const SizedBox.shrink();
    }

    final parentChain = _getParentChain(threadStructure, displayNoteId);
    if (parentChain.isEmpty) return const SizedBox.shrink();

    return Column(
      children: parentChain.map((parentNote) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: _buildSimpleNoteWidget(context, parentNote, state,
              isSmallView: true),
        );
      }).toList(),
    );
  }

  List<Map<String, dynamic>> _getParentChain(
      ThreadStructure structure, String noteId) {
    final List<Map<String, dynamic>> chain = [];
    Map<String, dynamic>? currentNote = structure.getNote(noteId);
    final rootNoteId = structure.rootNote['id'] as String? ?? '';

    while (currentNote != null) {
      final currentNoteId = currentNote['id'] as String? ?? '';
      if (currentNoteId == rootNoteId) {
        break;
      }
      final parentId = currentNote['parentId'] as String? ?? rootNoteId;
      if (parentId == rootNoteId) {
        break;
      }
      final parent = structure.getNote(parentId);
      if (parent == null) break;
      chain.insert(0, parent);
      currentNote = parent;
    }

    return chain;
  }

  Widget _buildMainNote(
      BuildContext context, ThreadLoaded state, Map<String, dynamic> note) {
    final isRepost = note['isRepost'] as bool? ?? false;
    if (isRepost) {
      return const SizedBox.shrink();
    }

    final focusedNoteId = _currentFocusedNoteId ?? state.focusedNoteId;
    final noteId = note['id'] as String? ?? '';
    final noteKey = _getNoteKey(noteId);
    final isFocused = focusedNoteId == noteId;

    return Container(
      key: isFocused ? noteKey : null,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 6),
      child: FocusedNoteWidget(
        note: note,
        currentUserNpub: state.currentUserNpub,
        notesNotifier: ValueNotifier<List<Map<String, dynamic>>>([]),
        profiles: state.userProfiles,
        notesListProvider: null,
        isSelectable: true,
      ),
    );
  }

  Widget _buildReplyInputSection(BuildContext context, ThreadLoaded state) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: GestureDetector(
        onTap: _handleReplyInputTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: context.colors.background,
            borderRadius: BorderRadius.circular(40),
            border: Border.all(
              color: context.colors.textPrimary,
              width: 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: context.colors.primary.withValues(alpha: 0.1),
                ),
                child: ClipOval(
                  child: Builder(
                    builder: (context) {
                      final currentUser = state.currentUser;
                      final profileImage =
                          currentUser?['profileImage'] as String? ?? '';
                      return profileImage.isNotEmpty
                          ? CachedNetworkImage(
                              imageUrl: profileImage,
                              fit: BoxFit.cover,
                              fadeInDuration: Duration.zero,
                              fadeOutDuration: Duration.zero,
                              maxHeightDiskCache: 80,
                              maxWidthDiskCache: 80,
                              memCacheWidth: 80,
                              memCacheHeight: 80,
                              errorWidget: (context, url, error) {
                                return Icon(
                                  Icons.person,
                                  size: 24,
                                  color: context.colors.primary,
                                );
                              },
                            )
                          : Icon(
                              Icons.person,
                              size: 24,
                              color: context.colors.primary,
                            );
                    },
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Add a reply...',
                  style: TextStyle(
                    color: context.colors.textSecondary,
                    fontSize: 16,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _handleReplyInputTap() {
    ShareNotePage.show(
      context,
      replyToNoteId: widget.rootNoteId,
    );
  }

  Widget _buildThreadRepliesSliver(BuildContext context, ThreadLoaded state,
      Map<String, dynamic> displayNote) {
    final threadStructure = state.threadStructure;
    final displayNoteId = displayNote['id'] as String? ?? '';

    final allDirectReplies = threadStructure.getChildren(displayNoteId);
    final directReplies = <Map<String, dynamic>>[];
    for (final reply in allDirectReplies) {
      final isRepost = reply['isRepost'] as bool? ?? false;
      if (!isRepost) {
        directReplies.add(reply);
      }
    }

    final currentUserNpub = state.currentUserNpub;
    directReplies.sort((a, b) {
      final aAuthor = a['author'] as String? ?? '';
      final bAuthor = b['author'] as String? ?? '';
      final aIsUserReply = aAuthor == currentUserNpub;
      final bIsUserReply = bAuthor == currentUserNpub;

      if (aIsUserReply && !bIsUserReply) return -1;
      if (!aIsUserReply && bIsUserReply) return 1;

      final aTimestamp = a['timestamp'] as DateTime? ?? DateTime(0);
      final bTimestamp = b['timestamp'] as DateTime? ?? DateTime(0);
      return aTimestamp.compareTo(bTimestamp);
    });

    if (directReplies.isEmpty) {
      return SliverToBoxAdapter(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32.0),
            child: Text(
              'No replies yet',
              style: TextStyle(
                color: context.colors.textSecondary,
                fontSize: 16,
              ),
            ),
          ),
        ),
      );
    }

    final maxVisible = math.min(_visibleRepliesCount, _maxInitialReplies);
    final visibleReplies = directReplies.take(maxVisible).toList();
    final hasMoreReplies = directReplies.length > maxVisible;

    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          if (index < visibleReplies.length) {
            final reply = visibleReplies[index];
            final showSeparator = index < visibleReplies.length - 1;
            return Column(
              key: ValueKey('reply_${reply['id'] as String? ?? ''}'),
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildThreadReply(
                  context,
                  state,
                  reply,
                  threadStructure,
                  0,
                ),
                if (showSeparator) _buildNoteSeparator(context),
              ],
            );
          } else if (index == visibleReplies.length && hasMoreReplies) {
            return Padding(
              padding: const EdgeInsets.only(top: 8.0, bottom: 4.0),
              child: _buildLoadMoreButton(context, directReplies.length),
            );
          }
          return const SizedBox.shrink();
        },
        childCount: visibleReplies.length + (hasMoreReplies ? 1 : 0),
        addAutomaticKeepAlives: false,
        addRepaintBoundaries: true,
      ),
    );
  }

  Widget _buildLoadMoreButton(BuildContext context, int totalReplies) {
    return Center(
      child: GestureDetector(
        onTap: () {
          setState(() {
            _visibleRepliesCount = math.min(
              _visibleRepliesCount + _repliesPerPage,
              totalReplies,
            );
          });
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Text(
            'Load more',
            style: TextStyle(
              color: context.colors.accent,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildThreadReply(
    BuildContext context,
    ThreadLoaded state,
    Map<String, dynamic> reply,
    ThreadStructure threadStructure,
    int depth,
  ) {
    const double baseIndentWidth = 24.0;
    const int maxDepth = 1;
    final double currentIndent = depth * baseIndentWidth;

    final focusedNoteId = _currentFocusedNoteId ?? state.focusedNoteId;
    final replyId = reply['id'] as String? ?? '';
    final isFocused = replyId == focusedNoteId;
    final noteKey = _getNoteKey(replyId);
    final allNestedReplies = threadStructure.getChildren(replyId);
    final nestedReplies = <Map<String, dynamic>>[];
    for (final nestedReply in allNestedReplies) {
      final isRepost = nestedReply['isRepost'] as bool? ?? false;
      if (!isRepost) {
        nestedReplies.add(nestedReply);
      }
    }

    final currentUserNpub = state.currentUserNpub;
    nestedReplies.sort((a, b) {
      final aAuthor = a['author'] as String? ?? '';
      final bAuthor = b['author'] as String? ?? '';
      final aIsUserReply = aAuthor == currentUserNpub;
      final bIsUserReply = bAuthor == currentUserNpub;

      if (aIsUserReply && !bIsUserReply) return -1;
      if (!aIsUserReply && bIsUserReply) return 1;

      final aTimestamp = a['timestamp'] as DateTime? ?? DateTime(0);
      final bTimestamp = b['timestamp'] as DateTime? ?? DateTime(0);
      return aTimestamp.compareTo(bTimestamp);
    });

    final hasNestedReplies = nestedReplies.isNotEmpty;

    return Container(
      key: ValueKey('reply_${replyId}_$depth'),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (depth > 0) SizedBox(width: currentIndent),
          Expanded(
            child: Column(
              key: isFocused ? noteKey : null,
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildEnhancedNoteWidget(
                  context,
                  state,
                  reply,
                  depth,
                ),
                if (depth < maxDepth && hasNestedReplies) ...[
                  ...nestedReplies.take(_maxNestedReplies).map(
                        (nestedReply) => _buildThreadReply(
                          context,
                          state,
                          nestedReply,
                          threadStructure,
                          depth + 1,
                        ),
                      ),
                  if (nestedReplies.length > _maxNestedReplies)
                    Padding(
                      padding: EdgeInsets.only(
                        left: (depth + 1) * baseIndentWidth + 12,
                        top: 4,
                      ),
                      child: Text(
                        '${nestedReplies.length - _maxNestedReplies} more replies...',
                        style: TextStyle(
                          color: context.colors.textSecondary,
                          fontSize: 12,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                ] else if (hasNestedReplies) ...[
                  Padding(
                    padding: EdgeInsets.only(
                      left: currentIndent + 12,
                      top: 4,
                    ),
                    child: Text(
                      'More replies... (${nestedReplies.length} nested)',
                      style: TextStyle(
                        color: context.colors.textSecondary,
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEnhancedNoteWidget(
    BuildContext context,
    ThreadLoaded state,
    Map<String, dynamic> note,
    int depth,
  ) {
    final noteId = note['id'] as String? ?? '';
    return RepaintBoundary(
      child: NoteWidget(
        key: ValueKey('note_$noteId'),
        note: note,
        currentUserNpub: state.currentUserNpub,
        notesNotifier: ValueNotifier<List<Map<String, dynamic>>>([]),
        profiles: state.userProfiles,
        containerColor: Colors.transparent,
        isSmallView: depth > 0,
        scrollController: _scrollController,
        isVisible: true,
        onNoteTap: (noteId, rootId) =>
            _handleNoteTap(noteId, rootId, state.threadStructure),
      ),
    );
  }

  Widget _buildSimpleNoteWidget(
    BuildContext context,
    Map<String, dynamic> note,
    ThreadLoaded state, {
    bool isSmallView = false,
  }) {
    final noteId = note['id'] as String? ?? '';
    return RepaintBoundary(
      child: NoteWidget(
        key: ValueKey('simple_$noteId'),
        note: note,
        currentUserNpub: state.currentUserNpub,
        notesNotifier: ValueNotifier<List<Map<String, dynamic>>>([]),
        profiles: state.userProfiles,
        containerColor: context.colors.background,
        isSmallView: isSmallView,
        scrollController: _scrollController,
        isVisible: true,
        onNoteTap: (noteId, rootId) =>
            _handleNoteTap(noteId, rootId, state.threadStructure),
      ),
    );
  }

  Widget _buildErrorState(BuildContext context, String message) {
    return SingleChildScrollView(
      child: Column(
        children: [
          SizedBox(height: MediaQuery.of(context).size.height * 0.2),
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.error_outline,
                  size: 64,
                  color: context.colors.error,
                ),
                const SizedBox(height: 16),
                Text(
                  'Failed to load thread',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: context.colors.textPrimary,
                      ),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Text(
                    message,
                    style: TextStyle(color: context.colors.textSecondary),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 24),
                PrimaryButton(
                  label: 'Retry',
                  onPressed: () {
                    context.read<ThreadBloc>().add(const ThreadRefreshed());
                  },
                  backgroundColor: context.colors.accent,
                  foregroundColor: Colors.white,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _handleNoteTap(String noteId, String? rootId,
      [ThreadStructure? threadStructure]) {
    String targetRootId = rootId ?? widget.rootNoteId;
    String? targetFocusedId;

    if (threadStructure != null) {
      final note = threadStructure.getNote(noteId);
      if (note != null) {
        final isReply = note['isReply'] as bool? ?? false;
        final noteRootId = note['rootId'] as String?;
        final isRepost = note['isRepost'] as bool? ?? false;

        if (isReply && noteRootId != null && noteRootId.isNotEmpty) {
          targetRootId = noteRootId;
          targetFocusedId = noteId;
        } else if (isRepost && noteRootId != null && noteRootId.isNotEmpty) {
          targetRootId = noteRootId;
          targetFocusedId = null;
        } else {
          targetRootId = noteId;
          targetFocusedId = null;
        }
      } else {
        if (rootId != null && rootId != widget.rootNoteId) {
          targetRootId = rootId;
          targetFocusedId = noteId;
        } else {
          targetRootId = noteId;
          targetFocusedId = null;
        }
      }
    } else {
      if (rootId != null && rootId != widget.rootNoteId) {
        targetRootId = rootId;
        targetFocusedId = noteId;
      } else {
        targetRootId = noteId;
        targetFocusedId = null;
      }
    }

    final currentLocation = GoRouterState.of(context).matchedLocation;
    if (currentLocation.startsWith('/home/feed')) {
      context.push(
          '/home/feed/thread?rootNoteId=${Uri.encodeComponent(targetRootId)}${targetFocusedId != null ? '&focusedNoteId=${Uri.encodeComponent(targetFocusedId)}' : ''}');
    } else if (currentLocation.startsWith('/home/notifications')) {
      context.push(
          '/home/notifications/thread?rootNoteId=${Uri.encodeComponent(targetRootId)}${targetFocusedId != null ? '&focusedNoteId=${Uri.encodeComponent(targetFocusedId)}' : ''}');
    } else {
      context.push(
          '/thread?rootNoteId=${Uri.encodeComponent(targetRootId)}${targetFocusedId != null ? '&focusedNoteId=${Uri.encodeComponent(targetFocusedId)}' : ''}');
    }
  }

  GlobalKey _getNoteKey(String noteId) {
    if (!_noteKeys.containsKey(noteId)) {
      _noteKeys[noteId] = GlobalKey();
    }
    return _noteKeys[noteId]!;
  }

  void _scheduleScrollToFocusedNote(String noteId) {
    if (!mounted) return;

    Future.delayed(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      _attemptScrollToFocusedNote(noteId, retries: 3);
    });
  }

  void _attemptScrollToFocusedNote(String noteId, {int retries = 0}) {
    if (!mounted || retries <= 0) return;

    final noteKey = _noteKeys[noteId];
    if (noteKey == null) {
      Future.delayed(const Duration(milliseconds: 200), () {
        _attemptScrollToFocusedNote(noteId, retries: retries - 1);
      });
      return;
    }

    final context = noteKey.currentContext;
    if (context != null) {
      Scrollable.ensureVisible(
        context,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
        alignment: 0.15,
      );
    } else {
      Future.delayed(const Duration(milliseconds: 200), () {
        _attemptScrollToFocusedNote(noteId, retries: retries - 1);
      });
    }
  }

  Future<void> _debouncedRefresh(BuildContext context) async {
    if (_isRefreshing) return;

    setState(() {
      _isRefreshing = true;
    });

    try {
      context.read<ThreadBloc>().add(const ThreadRefreshed());
    } finally {
      if (mounted) {
        setState(() {
          _isRefreshing = false;
        });
      }
    }
  }

  Widget _buildNoteSeparator(BuildContext context) {
    return SizedBox(
      height: 16,
      child: Center(
        child: Container(
          height: 0.5,
          decoration: BoxDecoration(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.3),
          ),
        ),
      ),
    );
  }

  Future<void> _handleShare(BuildContext context, ThreadState state) async {
    final rootNote = state is ThreadLoaded ? state.rootNote : null;
    if (rootNote == null) return;

    try {
      final rootNoteId = rootNote['id'] as String? ?? '';
      String noteId;
      if (rootNoteId.startsWith('note1')) {
        noteId = rootNoteId;
      } else {
        noteId = encodeBasicBech32(rootNoteId, 'note');
      }

      final nostrLink = 'nostr:$noteId';

      final box = context.findRenderObject() as RenderBox?;
      await SharePlus.instance.share(
        ShareParams(
          text: nostrLink,
          sharePositionOrigin:
              box != null ? box.localToGlobal(Offset.zero) & box.size : null,
        ),
      );
    } catch (e) {
      debugPrint('[ThreadPage] Share error: $e');
    }
  }
}
