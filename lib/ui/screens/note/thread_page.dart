import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../data/services/rust_nostr_bridge.dart';
import 'package:share_plus/share_plus.dart';
import 'package:qiqstr/ui/widgets/note/note_widget.dart';
import 'package:qiqstr/ui/widgets/note/focused_note_widget.dart';
import '../../widgets/common/common_buttons.dart';
import '../../widgets/common/list_separator_widget.dart';
import '../../widgets/common/top_action_bar_widget.dart';
import '../../theme/theme_manager.dart';
import '../../../core/di/app_di.dart';
import '../../../presentation/blocs/thread/thread_bloc.dart';
import '../../../presentation/blocs/thread/thread_event.dart';
import '../../../presentation/blocs/thread/thread_state.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'share_note.dart';
import '../../../l10n/app_localizations.dart';
import '../../../utils/thread_chain.dart';

class ThreadPage extends StatefulWidget {
  final String chain;
  final Map<String, dynamic>? initialNoteData;

  const ThreadPage({
    super.key,
    required this.chain,
    this.initialNoteData,
  });

  @override
  State<ThreadPage> createState() => _ThreadPageState();
}

class _ThreadPageState extends State<ThreadPage> {
  late ScrollController _scrollController;
  final Map<String, GlobalKey> _noteKeys = {};

  int _visibleRepliesCount = 20;
  static const int _repliesPerPage = 20;
  static const int _maxInitialReplies = 100;
  static const int _maxNestedReplies = 2;
  static const int _maxReplyDepth = 1;

  final List<String> _stableReplyOrder = [];

  bool _isRefreshing = false;
  final ValueNotifier<List<Map<String, dynamic>>> _emptyNotesNotifier =
      ValueNotifier([]);

  late final List<String> _parsedChain;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _parsedChain = ThreadChain.parse(widget.chain);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _emptyNotesNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider<ThreadBloc>(
      create: (context) {
        final bloc = AppDI.get<ThreadBloc>();
        bloc.add(ThreadLoadRequested(
          chain: _parsedChain,
          initialNoteData: widget.initialNoteData,
        ));
        return bloc;
      },
      child: BlocConsumer<ThreadBloc, ThreadState>(
        listenWhen: (previous, current) {
          return previous is! ThreadLoaded && current is ThreadLoaded;
        },
        listener: (context, state) {
          if (state is ThreadLoaded && state.chainNotes.length > 1) {
            _scrollToFocusedNote(state.focusedNoteId);
          }
        },
        buildWhen: (previous, current) {
          if (previous is ThreadLoaded && current is ThreadLoaded) {
            return previous.replies.length != current.replies.length ||
                previous.rootNoteId != current.rootNoteId ||
                previous.chainNotes.length != current.chainNotes.length ||
                previous.userProfiles.length != current.userProfiles.length ||
                previous.repliesSynced != current.repliesSynced;
          }
          return previous.runtimeType != current.runtimeType;
        },
        builder: (context, state) {
          final l10n = AppLocalizations.of(context)!;
          return Scaffold(
            backgroundColor: context.colors.background,
            body: Stack(
              children: [
                _buildContent(context, state, l10n),
                TopActionBarWidget(
                  onBackPressed: () => context.pop(),
                  centerBubble: Builder(
                    builder: (context) {
                      final l10n = AppLocalizations.of(context)!;
                      return Text(
                        l10n.thread,
                        style: TextStyle(
                          color: context.colors.background,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      );
                    },
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

  Widget _buildContent(
      BuildContext context, ThreadState state, AppLocalizations l10n) {
    if (state is ThreadLoaded) {
      return _buildThreadContent(context, state);
    }

    if (state is ThreadError) {
      return _buildErrorState(context, state.message, l10n);
    }

    if (state is ThreadInitial &&
        widget.initialNoteData != null &&
        _parsedChain.isNotEmpty) {
      final rootNote = _stripRepostDataForPlaceholder(
          widget.initialNoteData!, _parsedChain.first);
      final structure = ThreadStructure(
        rootNote: rootNote,
        childrenMap: const {},
        notesMap: {_parsedChain.first: rootNote},
        totalReplies: 0,
      );
      final placeholderState = ThreadLoaded(
        rootNote: rootNote,
        replies: const [],
        threadStructure: structure,
        chainNotes: [rootNote],
        chain: _parsedChain,
        userProfiles: const {},
        currentUserHex: '',
        currentUser: null,
      );
      return _buildThreadContent(context, placeholderState);
    }

    if (state is ThreadLoading) {
      return Center(
        child: CircularProgressIndicator(
          color: context.colors.primary,
          strokeWidth: 2,
        ),
      );
    }

    return const SizedBox.shrink();
  }

  Map<String, dynamic> _stripRepostDataForPlaceholder(
      Map<String, dynamic> noteData, String rootNoteId) {
    final stripped = Map<String, dynamic>.from(noteData);
    stripped['isRepost'] = false;
    stripped.remove('repostedBy');
    stripped.remove('repostCreatedAt');
    if ((stripped['id'] as String? ?? '') != rootNoteId) {
      stripped['id'] = rootNoteId;
    }
    return stripped;
  }

  Widget _buildThreadContent(BuildContext context, ThreadLoaded state) {
    final focusedNote = state.focusedNote;
    final contextNotes = state.contextNotes;

    return RefreshIndicator(
      onRefresh: () => _debouncedRefresh(context),
      child: CustomScrollView(
        controller: _scrollController,
        slivers: [
          SliverToBoxAdapter(
            child: SizedBox(height: MediaQuery.of(context).padding.top + 68),
          ),
          if (contextNotes.isNotEmpty)
            SliverToBoxAdapter(
              child: _buildContextChain(context, state, contextNotes),
            ),
          SliverToBoxAdapter(
            child: _buildMainNote(context, state, focusedNote),
          ),
          SliverToBoxAdapter(
            child: _buildReplyInputSection(context, state),
          ),
          _buildThreadRepliesSliver(context, state, focusedNote),
          SliverToBoxAdapter(
            child: SizedBox(
                height: MediaQuery.of(context).padding.bottom + 120),
          ),
        ],
      ),
    );
  }

  Widget _buildContextChain(BuildContext context, ThreadLoaded state,
      List<Map<String, dynamic>> contextNotes) {
    return Column(
      children: contextNotes.map((note) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: _buildSimpleNoteWidget(context, note, state,
              isSmallView: true),
        );
      }).toList(),
    );
  }

  Widget _buildMainNote(
      BuildContext context, ThreadLoaded state, Map<String, dynamic> note) {
    final isRepost = note['isRepost'] as bool? ?? false;
    if (isRepost) {
      return const SizedBox.shrink();
    }

    final noteId = note['id'] as String? ?? '';
    final noteKey = _getNoteKey(noteId);

    return Container(
      key: noteKey,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 6),
      child: FocusedNoteWidget(
        note: note,
        currentUserHex: state.currentUserHex,
        notesNotifier: _emptyNotesNotifier,
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
        onTap: () => _handleReplyInputTap(state),
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

  void _handleReplyInputTap(ThreadLoaded state) {
    final focusedNote = state.focusedNote;
    final focusedNoteId = focusedNote['id'] as String? ?? '';
    final parentAuthor = focusedNote['pubkey'] as String? ??
        focusedNote['author'] as String?;

    ShareNotePage.show(
      context,
      replyToNoteId: focusedNoteId,
      parentAuthor: parentAuthor,
    );
  }

  Widget _buildThreadRepliesSliver(BuildContext context, ThreadLoaded state,
      Map<String, dynamic> displayNote) {
    final threadStructure = state.threadStructure;
    final displayNoteId = displayNote['id'] as String? ?? '';

    final allDirectReplies = threadStructure.getChildren(displayNoteId);
    final repliesById = <String, Map<String, dynamic>>{};
    for (final reply in allDirectReplies) {
      final isRepost = reply['isRepost'] as bool? ?? false;
      if (isRepost) continue;
      final id = reply['id'] as String? ?? '';
      if (id.isNotEmpty) repliesById[id] = reply;
    }

    _stableReplyOrder.removeWhere((id) => !repliesById.containsKey(id));

    final newIds = repliesById.keys
        .where((id) => !_stableReplyOrder.contains(id))
        .toList();

    if (_stableReplyOrder.isEmpty && newIds.isNotEmpty) {
      final currentUserHex = state.currentUserHex;
      newIds.sort((a, b) {
        final aReply = repliesById[a]!;
        final bReply = repliesById[b]!;
        final aAuthor = aReply['author'] as String? ?? '';
        final bAuthor = bReply['author'] as String? ?? '';
        final aIsUser = aAuthor == currentUserHex;
        final bIsUser = bAuthor == currentUserHex;
        if (aIsUser && !bIsUser) return -1;
        if (!aIsUser && bIsUser) return 1;
        final aTime = aReply['timestamp'] as DateTime? ?? DateTime(0);
        final bTime = bReply['timestamp'] as DateTime? ?? DateTime(0);
        return aTime.compareTo(bTime);
      });
    } else if (newIds.isNotEmpty) {
      newIds.sort((a, b) {
        final aTime =
            repliesById[a]!['timestamp'] as DateTime? ?? DateTime(0);
        final bTime =
            repliesById[b]!['timestamp'] as DateTime? ?? DateTime(0);
        return aTime.compareTo(bTime);
      });
    }

    _stableReplyOrder.addAll(newIds);

    final directReplies = _stableReplyOrder
        .where((id) => repliesById.containsKey(id))
        .map((id) => repliesById[id]!)
        .toList();

    if (directReplies.isEmpty) {
      if (!state.repliesSynced) {
        return SliverToBoxAdapter(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32.0),
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: context.colors.textSecondary,
                ),
              ),
            ),
          ),
        );
      }
      return SliverToBoxAdapter(
        child: Builder(
          builder: (context) {
            final l10n = AppLocalizations.of(context)!;
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32.0),
                child: Text(
                  l10n.noRepliesFound,
                  style: TextStyle(
                    color: context.colors.textSecondary,
                    fontSize: 16,
                  ),
                ),
              ),
            );
          },
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
                if (showSeparator) const ListSeparatorWidget(),
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
    final l10n = AppLocalizations.of(context)!;
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
            l10n.loadMore,
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
    const double baseIndentWidth = 16.0;
    final double currentIndent = depth * baseIndentWidth;

    final replyId = reply['id'] as String? ?? '';
    final noteKey = _getNoteKey(replyId);
    final allNestedReplies = threadStructure.getChildren(replyId);
    final nestedReplies = <Map<String, dynamic>>[];
    for (final nestedReply in allNestedReplies) {
      final isRepost = nestedReply['isRepost'] as bool? ?? false;
      if (!isRepost) {
        nestedReplies.add(nestedReply);
      }
    }

    final currentUserHex = state.currentUserHex;
    nestedReplies.sort((a, b) {
      final aAuthor = a['author'] as String? ?? '';
      final bAuthor = b['author'] as String? ?? '';
      final aIsUserReply = aAuthor == currentUserHex;
      final bIsUserReply = bAuthor == currentUserHex;

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
              key: noteKey,
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildEnhancedNoteWidget(
                  context,
                  state,
                  reply,
                  depth,
                ),
                if (depth < _maxReplyDepth && hasNestedReplies) ...[
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
        currentUserHex: state.currentUserHex,
        notesNotifier: _emptyNotesNotifier,
        profiles: state.userProfiles,
        containerColor: Colors.transparent,
        isSmallView: depth > 0,
        scrollController: _scrollController,
        isVisible: true,
        onNoteTap: (noteId, rootId) =>
            _handleNoteTap(noteId, rootId, state),
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
        currentUserHex: state.currentUserHex,
        notesNotifier: _emptyNotesNotifier,
        profiles: state.userProfiles,
        containerColor: context.colors.background,
        isSmallView: isSmallView,
        scrollController: _scrollController,
        isVisible: true,
        onNoteTap: (noteId, rootId) =>
            _handleNoteTap(noteId, rootId, state),
      ),
    );
  }

  Widget _buildErrorState(
      BuildContext context, String message, AppLocalizations l10n) {
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
                  l10n.failedToLoadThread,
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
                  label: l10n.retryText,
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

  void _handleNoteTap(String noteId, String? rootId, ThreadLoaded state) {
    if (noteId == state.focusedNoteId) return;

    final threadStructure = state.threadStructure;
    final rootNoteId = state.rootNoteId;

    final note = threadStructure.getNote(noteId);
    if (note != null) {
      final isRepost = note['isRepost'] as bool? ?? false;
      if (isRepost) {
        final originalRootId = note['rootId'] as String?;
        final originalParentId = note['parentId'] as String?;
        final originalNoteId = note['id'] as String? ?? noteId;

        final chain = <String>[];
        if (originalRootId != null && originalRootId.isNotEmpty) {
          chain.add(originalRootId);
          if (originalParentId != null &&
              originalParentId.isNotEmpty &&
              originalParentId != originalRootId &&
              originalParentId != originalNoteId) {
            chain.add(originalParentId);
          }
          if (originalNoteId != originalRootId) {
            chain.add(originalNoteId);
          }
        } else {
          chain.add(originalNoteId);
        }

        _navigateToThread(ThreadChain.build(chain));
        return;
      }
    }

    final newChain = ThreadChain.buildChainToNote(
      noteId,
      rootNoteId,
      threadStructure.getNote,
    );

    _navigateToThread(ThreadChain.build(newChain));
  }

  void _navigateToThread(String chainStr) {
    final currentLocation = GoRouterState.of(context).matchedLocation;
    if (currentLocation.startsWith('/home/feed')) {
      context.push('/home/feed/thread/$chainStr');
    } else if (currentLocation.startsWith('/home/notifications')) {
      context.push('/home/notifications/thread/$chainStr');
    } else {
      context.push('/thread/$chainStr');
    }
  }

  GlobalKey _getNoteKey(String noteId) {
    if (!_noteKeys.containsKey(noteId)) {
      _noteKeys[noteId] = GlobalKey();
    }
    return _noteKeys[noteId]!;
  }

  void _scrollToFocusedNote(String noteId) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _attemptScrollToFocusedNote(noteId, retries: 5);
    });
  }

  void _attemptScrollToFocusedNote(String noteId, {int retries = 0}) {
    if (!mounted || retries <= 0) return;

    final noteKey = _noteKeys[noteId];
    if (noteKey != null && noteKey.currentContext != null) {
      final topBar = MediaQuery.of(context).padding.top + 175;

      Scrollable.ensureVisible(
        noteKey.currentContext!,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
        alignment: topBar / MediaQuery.of(context).size.height,
      );
      return;
    }

    Future.delayed(const Duration(milliseconds: 50), () {
      if (mounted) {
        _attemptScrollToFocusedNote(noteId, retries: retries - 1);
      }
    });
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
