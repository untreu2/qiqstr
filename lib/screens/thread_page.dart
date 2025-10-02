import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qiqstr/models/note_model.dart';
import 'package:qiqstr/models/user_model.dart';
import 'package:qiqstr/widgets/note_widget.dart';
import 'package:qiqstr/widgets/focused_note_widget.dart';
import '../widgets/back_button_widget.dart';
import '../theme/theme_manager.dart';
import '../core/ui/ui_state_builder.dart';
import '../core/di/app_di.dart';
import '../presentation/providers/viewmodel_provider.dart';
import '../presentation/viewmodels/thread_viewmodel.dart';

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
  String? _highlightedNoteId;
  late ValueNotifier<List<NoteModel>> _notesNotifier;
  final Map<String, UserModel> _profiles = {};

  // Pagination state for replies
  int _visibleRepliesCount = 10;
  static const int _repliesPerPage = 10;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _notesNotifier = ValueNotifier<List<NoteModel>>([]);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _notesNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ViewModelBuilder<ThreadViewModel>(
      create: () => AppDI.get<ThreadViewModel>(),
      onModelReady: (viewModel) {
        // Initialize once when ViewModel is ready
        viewModel.initializeWithThread(
          rootNoteId: widget.rootNoteId,
          focusedNoteId: widget.focusedNoteId,
        );

        // Scroll to focused note if specified
        if (widget.focusedNoteId != null) {
          _scrollToFocusedNote();
        }
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
      loading: () => _buildLoadingState(context),
      error: (message) => _buildErrorState(context, message, viewModel),
      empty: (message) => _buildNotFoundState(context, viewModel),
    );
  }

  Widget _buildThreadContent(BuildContext context, ThreadViewModel viewModel, NoteModel rootNote) {
    final double topPadding = MediaQuery.of(context).padding.top;
    final double headerHeight = topPadding + 60;

    // Determine which note to display as main (focused or root)
    final displayNote =
        widget.focusedNoteId != null ? viewModel.threadStructureState.data?.getNote(widget.focusedNoteId!) ?? rootNote : rootNote;

    final isDisplayNoteHighlighted = displayNote.id == _highlightedNoteId;

    return RefreshIndicator(
      onRefresh: () => viewModel.refreshThreadCommand.execute(),
      child: SingleChildScrollView(
        key: PageStorageKey<String>('thread_${widget.rootNoteId}'),
        controller: _scrollController,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(height: headerHeight),

            // Context note (parent of focused note if applicable)
            _buildContextNote(context, viewModel, displayNote),

            // Main note (root or focused)
            AnimatedContainer(
              duration: const Duration(milliseconds: 500),
              curve: Curves.easeInOut,
              color: isDisplayNoteHighlighted ? Theme.of(context).primaryColor.withValues(alpha: 0.1) : Colors.transparent,
              child: _buildMainNote(context, viewModel, displayNote),
            ),

            // Thread replies
            _buildThreadReplies(context, viewModel, displayNote),

            const SizedBox(height: 24.0),
          ],
        ),
      ),
    );
  }

  Widget _buildContextNote(BuildContext context, ThreadViewModel viewModel, NoteModel displayNote) {
    // Show parent note if this is a reply
    if (displayNote.isReply && displayNote.parentId != null) {
      final parentNote = viewModel.threadStructureState.data?.getNote(displayNote.parentId!);

      if (parentNote != null && !parentNote.isRepost) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(0, 8, 0, 0),
          child: _buildSimpleNoteWidget(context, parentNote, isSmallView: true),
        );
      }
    }

    return const SizedBox.shrink();
  }

  Widget _buildMainNote(BuildContext context, ThreadViewModel viewModel, NoteModel note) {
    // Don't display repost notes
    if (note.isRepost) {
      return const SizedBox.shrink();
    }

    // Update profiles from viewModel
    _profiles.addAll(viewModel.userProfiles);

    return Container(
      key: widget.focusedNoteId != null ? _focusedNoteKey : null,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: FocusedNoteWidget(
        note: note,
        currentUserNpub: viewModel.currentRootNote?.author ?? '',
        notesNotifier: _notesNotifier,
        profiles: _profiles,
        notesListProvider: null, // ThreadPage doesn't use notesListProvider
      ),
    );
  }

  Widget _buildThreadReplies(BuildContext context, ThreadViewModel viewModel, NoteModel displayNote) {
    debugPrint(' [ThreadPage] Building thread replies for display note: ${displayNote.id}');

    return UIStateBuilder<List<NoteModel>>(
      state: viewModel.repliesState,
      builder: (context, replies) {
        debugPrint(' [ThreadPage] Replies state loaded with ${replies.length} replies');

        final threadStructure = viewModel.threadStructureState.data;
        if (threadStructure == null) {
          debugPrint('[ThreadPage] Thread structure is null, showing empty widget');
          return const SizedBox.shrink();
        }

        debugPrint(' [ThreadPage] Thread structure available, getting children for: ${displayNote.id}');
        final allDirectReplies = threadStructure.getChildren(displayNote.id);
        // Filter out repost notes
        final directReplies = allDirectReplies.where((reply) => !reply.isRepost).toList();
        debugPrint(' [ThreadPage] Found ${directReplies.length} direct replies (filtered) for ${displayNote.id}');

        if (directReplies.isEmpty) {
          debugPrint(' [ThreadPage] No direct replies found, showing "No replies yet"');
          return Center(
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
          );
        }

        // Apply pagination to direct replies
        final visibleReplies = directReplies.take(_visibleRepliesCount).toList();
        final hasMoreReplies = directReplies.length > _visibleRepliesCount;

        debugPrint(' [ThreadPage] Building ${visibleReplies.length} reply widgets out of ${directReplies.length} total');
        return Column(
          children: [
            const SizedBox(height: 8.0),
            ...visibleReplies.map((reply) {
              debugPrint(' [ThreadPage] Creating widget for reply: ${reply.id}');
              return _buildThreadReply(
                context,
                viewModel,
                reply,
                threadStructure,
                0, // depth
              );
            }),

            // Load More button
            if (hasMoreReplies) ...[
              const SizedBox(height: 16.0),
              _buildLoadMoreButton(context, directReplies.length),
              const SizedBox(height: 8.0),
            ],
          ],
        );
      },
      loading: () => Container(
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
      empty: (message) => Center(
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

  Widget _buildLoadMoreButton(BuildContext context, int totalReplies) {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16.0),
        child: OutlinedButton(
          onPressed: () {
            setState(() {
              _visibleRepliesCount += _repliesPerPage;
            });
          },
          child: Text(
            'Load More',
            style: TextStyle(
              color: context.colors.primary,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          style: OutlinedButton.styleFrom(
            side: BorderSide(color: context.colors.primary.withValues(alpha: 0.3)),
            backgroundColor: context.colors.primary.withValues(alpha: 0.05),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(40),
            ),
          ),
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
    const int maxDepth = 2; // Maximum 2 levels of nesting for clean UI
    final double currentIndent = depth * baseIndentWidth;

    final isFocused = reply.id == widget.focusedNoteId;
    final isHighlighted = reply.id == _highlightedNoteId;
    final allNestedReplies = threadStructure.getChildren(reply.id);
    // Filter out repost notes from nested replies
    final nestedReplies = allNestedReplies.where((nestedReply) => !nestedReply.isRepost).toList();
    final hasNestedReplies = nestedReplies.isNotEmpty;

    return RepaintBoundary(
      child: Container(
        margin: EdgeInsets.only(
          bottom: depth == 0 ? 12.0 : 6.0,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Simple thread indentation
            if (depth > 0) SizedBox(width: currentIndent),

            // Reply content with enhanced design
            Expanded(
              child: Column(
                key: isFocused ? _focusedNoteKey : null,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 2),

                  // Simple flat note container
                  Container(
                    margin: const EdgeInsets.only(right: 8),
                    color: isHighlighted ? context.colors.primary.withValues(alpha: 0.05) : Colors.transparent,
                    child: _buildEnhancedNoteWidget(
                      context,
                      viewModel,
                      reply,
                      depth,
                    ),
                  ),

                  const SizedBox(height: 4),

                  // Nested replies with improved layout
                  if (depth < maxDepth && hasNestedReplies) ...[
                    const SizedBox(height: 4),
                    ...nestedReplies.take(5).map(
                          (nestedReply) => _buildThreadReply(
                            context,
                            viewModel,
                            nestedReply,
                            threadStructure,
                            depth + 1,
                          ),
                        ),

                    // Simple "more replies" indicator
                    if (nestedReplies.length > 5)
                      Container(
                        margin: EdgeInsets.only(
                          left: (depth + 1) * baseIndentWidth + 12,
                          top: 4,
                          bottom: 8,
                        ),
                        child: Text(
                          '${nestedReplies.length - 5} more replies...',
                          style: TextStyle(
                            color: context.colors.textSecondary,
                            fontSize: 12,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                  ] else if (hasNestedReplies) ...[
                    // Max depth reached - simple summary
                    Container(
                      margin: EdgeInsets.only(
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
      ),
    );
  }

  Widget _buildEnhancedNoteWidget(
    BuildContext context,
    ThreadViewModel viewModel,
    NoteModel note,
    int depth,
  ) {
    // Update profiles from viewModel
    _profiles.addAll(viewModel.userProfiles);

    return NoteWidget(
      note: note,
      currentUserNpub: viewModel.currentRootNote?.author ?? '',
      notesNotifier: _notesNotifier,
      profiles: _profiles,
      containerColor: Colors.transparent,
      isSmallView: depth > 1,
      scrollController: _scrollController,
    );
  }

  Widget _buildSimpleNoteWidget(
    BuildContext context,
    NoteModel note, {
    bool isSmallView = false,
  }) {
    final viewModel = context.read<ThreadViewModel>();
    // Update profiles from viewModel
    _profiles.addAll(viewModel.userProfiles);

    return NoteWidget(
      note: note,
      currentUserNpub: viewModel.currentRootNote?.author ?? '',
      notesNotifier: _notesNotifier,
      profiles: _profiles,
      containerColor: context.colors.background,
      isSmallView: isSmallView,
      scrollController: _scrollController,
    );
  }

  // Removed _buildInteractionBar - NoteWidget has its own InteractionBar

  Widget _buildLoadingState(BuildContext context) {
    final double topPadding = MediaQuery.of(context).padding.top;
    final double headerHeight = topPadding + 60;

    return Column(
      children: [
        SizedBox(height: headerHeight),
        Expanded(
          child: Center(
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
          ),
        ),
      ],
    );
  }

  Widget _buildErrorState(BuildContext context, String message, ThreadViewModel viewModel) {
    final double topPadding = MediaQuery.of(context).padding.top;
    final double headerHeight = topPadding + 60;

    return Column(
      children: [
        SizedBox(height: headerHeight),
        Expanded(
          child: Center(
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
                Text(
                  message,
                  style: TextStyle(color: context.colors.textSecondary),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () => viewModel.loadThreadCommand.execute(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: context.colors.accent,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNotFoundState(BuildContext context, ThreadViewModel viewModel) {
    final double topPadding = MediaQuery.of(context).padding.top;
    final double headerHeight = topPadding + 60;

    return Column(
      children: [
        SizedBox(height: headerHeight),
        Expanded(
          child: Center(
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
                Text(
                  'The note may have been deleted or is not available',
                  style: TextStyle(
                    color: context.colors.textSecondary,
                    fontSize: 14,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () => viewModel.loadThreadCommand.execute(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: context.colors.accent,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _scrollToFocusedNote() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      setState(() {
        _highlightedNoteId = widget.focusedNoteId;
      });

      if (widget.focusedNoteId != null) {
        final context = _focusedNoteKey.currentContext;
        if (context != null) {
          Scrollable.ensureVisible(
            context,
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeInOut,
            alignment: 0.1,
          );
        }
      }

      // Remove highlight after delay
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) {
          setState(() => _highlightedNoteId = null);
        }
      });
    });
  }

  // Removed interaction handlers - NoteWidget handles interactions internally
}
