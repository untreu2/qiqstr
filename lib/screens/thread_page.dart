import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:qiqstr/models/note_model.dart';
import 'package:qiqstr/widgets/note_widget.dart';
import 'package:qiqstr/widgets/focused_note_widget.dart';
import '../widgets/back_button_widget.dart';
import '../widgets/common_buttons.dart';
import '../theme/theme_manager.dart';
import '../core/ui/ui_state_builder.dart';
import '../core/di/app_di.dart';
import '../presentation/providers/viewmodel_provider.dart';
import '../presentation/viewmodels/thread_viewmodel.dart';
import '../screens/share_note.dart';

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
  final GlobalKey _focusedNoteKey = GlobalKey();
  final ValueNotifier<bool> _showThreadBubbleNotifier = ValueNotifier<bool>(false);

  int _visibleRepliesCount = 3;
  static const int _repliesPerPage = 5;
  static const int _maxInitialReplies = 10;
  static const int _maxNestedReplies = 1;

  bool _isRefreshing = false;
  Timer? _scrollDebounceTimer;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController()..addListener(_scrollListener);
    
    if (widget.focusedNoteId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scheduleScrollToFocusedNote();
      });
    }
  }

  void _scrollListener() {
    if (!_scrollController.hasClients) return;
    
    _scrollDebounceTimer?.cancel();
    _scrollDebounceTimer = Timer(const Duration(milliseconds: 100), () {
      if (!mounted || !_scrollController.hasClients) return;
      
      final shouldShow = _scrollController.offset > 100;
      if (_showThreadBubbleNotifier.value != shouldShow) {
        _showThreadBubbleNotifier.value = shouldShow;
      }
    });
  }

  @override
  void dispose() {
    _scrollDebounceTimer?.cancel();
    _scrollController.removeListener(_scrollListener);
    _scrollController.dispose();
    _showThreadBubbleNotifier.dispose();
    super.dispose();
  }


  @override
  Widget build(BuildContext context) {
    return ViewModelBuilder<ThreadViewModel>(
      create: () => AppDI.get<ThreadViewModel>(),
      onModelReady: (viewModel) {
        viewModel.initializeWithThread(
          rootNoteId: widget.rootNoteId,
          focusedNoteId: widget.focusedNoteId,
        );
      },
      builder: (context, viewModel) {
        return Scaffold(
          backgroundColor: context.colors.background,
          body: Consumer<ThreadViewModel>(
            builder: (context, vm, child) {
              return Stack(
                children: [
                  _buildContent(context, vm),
                  const BackButtonWidget.floating(),
                  Positioned(
                    top: MediaQuery.of(context).padding.top + 8,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: ValueListenableBuilder<bool>(
                        valueListenable: _showThreadBubbleNotifier,
                        builder: (context, showBubble, child) {
                          return AnimatedOpacity(
                            opacity: showBubble ? 1.0 : 0.0,
                            duration: const Duration(milliseconds: 200),
                            child: IgnorePointer(
                              ignoring: !showBubble,
                              child: GestureDetector(
                                onTap: () {
                                  _scrollController.animateTo(
                                    0,
                                    duration: const Duration(milliseconds: 300),
                                    curve: Curves.easeOut,
                                  );
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: context.colors.buttonPrimary,
                                    borderRadius: BorderRadius.circular(40),
                                  ),
                                  child: Text(
                                    'Thread',
                                    style: TextStyle(
                                      color: context.colors.buttonText,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildContent(BuildContext context, ThreadViewModel viewModel) {
    return UIStateBuilder<NoteModel>(
      state: viewModel.rootNoteState,
      builder: (context, rootNote) {
        return _buildThreadContent(context, viewModel, rootNote);
      },
      loading: () => _buildThreadContent(context, viewModel, null),
      error: (message) => _buildErrorState(context, message, viewModel),
      empty: (message) => _buildNotFoundState(context, viewModel),
    );
  }

  Widget _buildThreadContent(BuildContext context, ThreadViewModel viewModel, NoteModel? rootNote) {
    final displayNote = rootNote != null && widget.focusedNoteId != null
        ? viewModel.threadStructureState.data?.getNote(widget.focusedNoteId!) ?? rootNote
        : rootNote;

    return RefreshIndicator(
      onRefresh: () => _debouncedRefresh(viewModel),
      child: CustomScrollView(
        controller: _scrollController,
        slivers: [
          SliverToBoxAdapter(
            child: SizedBox(height: MediaQuery.of(context).padding.top + 60),
          ),
          SliverToBoxAdapter(
            child: _buildHeader(context),
          ),
          if (displayNote != null) ...[
            SliverToBoxAdapter(
              child: _buildContextNote(context, viewModel, displayNote),
            ),
            SliverToBoxAdapter(
              child: _buildMainNote(context, viewModel, displayNote),
            ),
            SliverToBoxAdapter(
              child: _buildReplyInputSection(context, viewModel),
            ),
            _buildThreadRepliesSliver(context, viewModel, displayNote),
          ] else ...[
            SliverToBoxAdapter(
              child: const SizedBox(height: 80),
            ),
            SliverToBoxAdapter(
              child: Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.grey,
                  ),
                ),
              ),
            ),
          ],
          SliverToBoxAdapter(
            child: const SizedBox(height: 24.0),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        'Thread',
        style: TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.w700,
          color: context.colors.textPrimary,
          letterSpacing: -0.5,
        ),
      ),
    );
  }

  Widget _buildContextNote(BuildContext context, ThreadViewModel viewModel, NoteModel displayNote) {
    if (displayNote.isReply && displayNote.parentId != null) {
      final parentNote = viewModel.threadStructureState.data?.getNote(displayNote.parentId!);

      if (parentNote != null && !parentNote.isRepost) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(0, 4, 0, 0),
          child: _buildSimpleNoteWidget(context, parentNote, viewModel, isSmallView: true),
        );
      }
    }

    return const SizedBox.shrink();
  }

  Widget _buildMainNote(BuildContext context, ThreadViewModel viewModel, NoteModel note) {
    if (note.isRepost) {
      return const SizedBox.shrink();
    }

    return Container(
      key: widget.focusedNoteId != null ? _focusedNoteKey : null,
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 6),
      child: FocusedNoteWidget(
        note: note,
        currentUserNpub: viewModel.currentUserNpub,
        notesNotifier: ValueNotifier<List<NoteModel>>([]),
        profiles: viewModel.userProfiles,
        notesListProvider: null,
      ),
    );
  }

  Widget _buildReplyInputSection(BuildContext context, ThreadViewModel viewModel) {
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
                  child: viewModel.currentUser?.profileImage.isNotEmpty == true
                      ? CachedNetworkImage(
                          imageUrl: viewModel.currentUser!.profileImage,
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
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ShareNotePage(
          replyToNoteId: widget.rootNoteId,
        ),
      ),
    );
  }

  Widget _buildThreadRepliesSliver(BuildContext context, ThreadViewModel viewModel, NoteModel displayNote) {
    return UIStateBuilder<List<NoteModel>>(
      state: viewModel.repliesState,
      builder: (context, replies) {
        final threadStructureState = viewModel.threadStructureState;

        if (threadStructureState.isLoading) {
          return SliverToBoxAdapter(
            child: Container(
              padding: const EdgeInsets.all(32),
              child: Center(
                child: Column(
                  children: [
                    CircularProgressIndicator(color: context.colors.primary),
                    const SizedBox(height: 16),
                    Text(
                      'Building thread structure...',
                      style: TextStyle(color: context.colors.textSecondary),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        final threadStructure = threadStructureState.data;
        if (threadStructure == null) {
          return const SliverToBoxAdapter(child: SizedBox.shrink());
        }

        final allDirectReplies = threadStructure.getChildren(displayNote.id);

        final directReplies = allDirectReplies.where((reply) => !reply.isRepost).toList()
          ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

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
                return Padding(
                  key: ValueKey('reply_${reply.id}'),
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: _buildThreadReply(
                    context,
                    viewModel,
                    reply,
                    threadStructure,
                    0,
                  ),
                );
              } else if (index == visibleReplies.length && hasMoreReplies) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16.0),
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
      },
      loading: () => SliverToBoxAdapter(
        child: Container(
          padding: const EdgeInsets.all(32),
          child: Center(
            child: Column(
              children: [
                CircularProgressIndicator(color: context.colors.primary),
                const SizedBox(height: 16),
                Text(
                  'Loading replies...',
                  style: TextStyle(color: context.colors.textSecondary),
                ),
              ],
            ),
          ),
        ),
      ),
      empty: (message) => SliverToBoxAdapter(
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
      ),
    );
  }

  Widget _buildLoadMoreButton(BuildContext context, int totalReplies) {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16.0),
        child: SecondaryButton(
          label: 'Load more (${totalReplies - _visibleRepliesCount} remaining)',
          onPressed: () {
            setState(() {
              _visibleRepliesCount = math.min(
                _visibleRepliesCount + _repliesPerPage,
                totalReplies,
              );
            });
          },
        ),
      ),
    );
  }

  Widget _buildThreadReply(
    BuildContext context,
    ThreadViewModel viewModel,
    NoteModel reply,
    ThreadStructure threadStructure,
    int depth,
  ) {
    const double baseIndentWidth = 24.0;
    const int maxDepth = 1;
    final double currentIndent = depth * baseIndentWidth;

    final isFocused = reply.id == widget.focusedNoteId;
    final allNestedReplies = threadStructure.getChildren(reply.id);
    final nestedReplies = allNestedReplies.where((nestedReply) => !nestedReply.isRepost).toList();
    final hasNestedReplies = nestedReplies.isNotEmpty;

    return Container(
      key: ValueKey('reply_${reply.id}_$depth'),
      margin: EdgeInsets.only(
        bottom: depth == 0 ? 12.0 : 6.0,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (depth > 0) SizedBox(width: currentIndent),
          Expanded(
            child: Column(
              key: isFocused ? _focusedNoteKey : null,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 2),
                Container(
                  margin: const EdgeInsets.only(right: 8),
                  child: _buildEnhancedNoteWidget(
                    context,
                    viewModel,
                    reply,
                    depth,
                  ),
                ),
                const SizedBox(height: 4),
                if (depth < maxDepth && hasNestedReplies) ...[
                  const SizedBox(height: 4),
                  ...nestedReplies.take(_maxNestedReplies).map(
                        (nestedReply) => _buildThreadReply(
                          context,
                          viewModel,
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
                        bottom: 8,
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
                      top: 8,
                      bottom: 4,
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
    ThreadViewModel viewModel,
    NoteModel note,
    int depth,
  ) {
    return RepaintBoundary(
      child: NoteWidget(
        key: ValueKey('note_${note.id}'),
        note: note,
        currentUserNpub: viewModel.currentUserNpub,
        notesNotifier: ValueNotifier<List<NoteModel>>([]),
        profiles: viewModel.userProfiles,
        containerColor: Colors.transparent,
        isSmallView: depth > 0,
        scrollController: _scrollController,
        isVisible: true,
      ),
    );
  }

  Widget _buildSimpleNoteWidget(
    BuildContext context,
    NoteModel note,
    ThreadViewModel viewModel, {
    bool isSmallView = false,
  }) {
    return RepaintBoundary(
      child: NoteWidget(
        key: ValueKey('simple_${note.id}'),
        note: note,
        currentUserNpub: viewModel.currentUserNpub,
        notesNotifier: ValueNotifier<List<NoteModel>>([]),
        profiles: viewModel.userProfiles,
        containerColor: context.colors.background,
        isSmallView: isSmallView,
        scrollController: _scrollController,
        isVisible: true,
      ),
    );
  }

  Widget _buildErrorState(BuildContext context, String message, ThreadViewModel viewModel) {
    return SingleChildScrollView(
      child: Column(
        children: [
          _buildHeader(context),
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
                  onPressed: () => viewModel.loadThreadCommand.execute(),
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

  Widget _buildNotFoundState(BuildContext context, ThreadViewModel viewModel) {
    return SingleChildScrollView(
      child: Column(
        children: [
          _buildHeader(context),
          SizedBox(height: MediaQuery.of(context).size.height * 0.2),
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.search_off,
                  size: 64,
                  color: context.colors.textSecondary,
                ),
                const SizedBox(height: 16),
                Text(
                  'Note not found',
                  style: TextStyle(
                    color: context.colors.textSecondary,
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Text(
                    'The note may have been deleted or is not available',
                    style: TextStyle(
                      color: context.colors.textSecondary,
                      fontSize: 14,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 24),
                PrimaryButton(
                  label: 'Retry',
                  onPressed: () => viewModel.loadThreadCommand.execute(),
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

  void _scheduleScrollToFocusedNote() {
    if (!mounted || widget.focusedNoteId == null) return;

    Future.delayed(const Duration(milliseconds: 500), () {
      if (!mounted) return;

      _attemptScrollToFocusedNote(retries: 5);
    });
  }

  void _attemptScrollToFocusedNote({int retries = 0}) {
    if (!mounted || widget.focusedNoteId == null || retries <= 0) return;

    final context = _focusedNoteKey.currentContext;
    if (context != null) {
      Scrollable.ensureVisible(
        context,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
        alignment: 0.15,
      );
    } else {
      Future.delayed(const Duration(milliseconds: 200), () {
        _attemptScrollToFocusedNote(retries: retries - 1);
      });
    }
  }

  Future<void> _debouncedRefresh(ThreadViewModel viewModel) async {
    if (_isRefreshing) return;

    setState(() {
      _isRefreshing = true;
    });

    try {
      await viewModel.refreshThreadCommand.execute();
    } finally {
      if (mounted) {
        setState(() {
          _isRefreshing = false;
        });
      }
    }
  }
}
