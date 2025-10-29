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
import '../data/repositories/auth_repository.dart';

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
  late ValueNotifier<List<NoteModel>> _notesNotifier;
  final Map<String, UserModel> _profiles = {};
  late final AuthRepository _authRepository;
  String _currentUserNpub = '';

  int _visibleRepliesCount = 10;
  static const int _repliesPerPage = 10;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _notesNotifier = ValueNotifier<List<NoteModel>>([]);
    _authRepository = AppDI.get<AuthRepository>();
    _loadCurrentUser();

    if (widget.focusedNoteId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scheduleScrollToFocusedNote();
      });
    }
  }

  Future<void> _loadCurrentUser() async {
    try {
      final result = await _authRepository.getCurrentUserNpub();
      if (result.isSuccess && result.data != null) {
        setState(() {
          _currentUserNpub = result.data!;
        });
      }
    } catch (e) {
      debugPrint('[ThreadPage] Error loading current user: $e');
    }
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
      onRefresh: () => viewModel.refreshThreadCommand.execute(),
      child: CustomScrollView(
        controller: _scrollController,
        slivers: [
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
    final double topPadding = MediaQuery.of(context).padding.top;

    return Padding(
      padding: EdgeInsets.fromLTRB(16, topPadding + 70, 16, 0),
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
          child: _buildSimpleNoteWidget(context, parentNote, isSmallView: true),
        );
      }
    }

    return const SizedBox.shrink();
  }

  Widget _buildMainNote(BuildContext context, ThreadViewModel viewModel, NoteModel note) {
    if (note.isRepost) {
      return const SizedBox.shrink();
    }

    _profiles.addAll(viewModel.userProfiles);

    return Container(
      key: widget.focusedNoteId != null ? _focusedNoteKey : null,
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: FocusedNoteWidget(
        note: note,
        currentUserNpub: _currentUserNpub,
        notesNotifier: _notesNotifier,
        profiles: _profiles,
        notesListProvider: null,
      ),
    );
  }

  Widget _buildThreadRepliesSliver(BuildContext context, ThreadViewModel viewModel, NoteModel displayNote) {
    debugPrint(' [ThreadPage] Building thread replies sliver for display note: ${displayNote.id}');

    return UIStateBuilder<List<NoteModel>>(
      state: viewModel.repliesState,
      builder: (context, replies) {
        debugPrint(' [ThreadPage] Replies state loaded with ${replies.length} replies');

        final threadStructureState = viewModel.threadStructureState;

        if (threadStructureState.isLoading) {
          debugPrint('[ThreadPage] Thread structure still loading, showing loader');
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
          debugPrint('[ThreadPage] Thread structure is null, showing empty widget');
          return const SliverToBoxAdapter(child: SizedBox.shrink());
        }

        debugPrint(' [ThreadPage] Thread structure ready, getting children for: ${displayNote.id}');
        final allDirectReplies = threadStructure.getChildren(displayNote.id);

        final directReplies = allDirectReplies.where((reply) => !reply.isRepost).toList()
          ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

        debugPrint(' [ThreadPage] Found ${directReplies.length} direct replies (filtered and sorted) for ${displayNote.id}');

        if (directReplies.isEmpty) {
          debugPrint(' [ThreadPage] No direct replies found, showing "No replies yet"');
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

        final visibleReplies = directReplies.take(_visibleRepliesCount).toList();
        final hasMoreReplies = directReplies.length > _visibleRepliesCount;

        debugPrint(' [ThreadPage] Building ${visibleReplies.length} reply widgets out of ${directReplies.length} total');
        return SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              if (index < visibleReplies.length) {
                final reply = visibleReplies[index];
                debugPrint(' [ThreadPage] Creating widget for reply [$index]: ${reply.id}');
                return AnimatedContainer(
                  key: ValueKey(reply.id),
                  duration: const Duration(milliseconds: 300),
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 8.0),
                    child: _buildThreadReply(
                      context,
                      viewModel,
                      reply,
                      threadStructure,
                      0,
                    ),
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
        child: OutlinedButton(
          onPressed: () {
            setState(() {
              _visibleRepliesCount += _repliesPerPage;
            });
          },
          style: OutlinedButton.styleFrom(
            side: BorderSide(color: context.colors.primary.withValues(alpha: 0.3)),
            backgroundColor: context.colors.primary.withValues(alpha: 0.05),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(40),
            ),
          ),
          child: Text(
            'Load More',
            style: TextStyle(
              color: context.colors.primary,
              fontSize: 14,
              fontWeight: FontWeight.w500,
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
    const int maxDepth = 2;
    final double currentIndent = depth * baseIndentWidth;

    final isFocused = reply.id == widget.focusedNoteId;
    final allNestedReplies = threadStructure.getChildren(reply.id);
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
                    ...nestedReplies.take(5).map(
                          (nestedReply) => _buildThreadReply(
                            context,
                            viewModel,
                            nestedReply,
                            threadStructure,
                            depth + 1,
                          ),
                        ),
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
    _profiles.addAll(viewModel.userProfiles);

    return NoteWidget(
      note: note,
      currentUserNpub: _currentUserNpub,
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
    _profiles.addAll(viewModel.userProfiles);

    return NoteWidget(
      note: note,
      currentUserNpub: _currentUserNpub,
      notesNotifier: _notesNotifier,
      profiles: _profiles,
      containerColor: context.colors.background,
      isSmallView: isSmallView,
      scrollController: _scrollController,
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
        ],
      ),
    );
  }

  void _scheduleScrollToFocusedNote() {
    if (!mounted || widget.focusedNoteId == null) return;

    Future.delayed(const Duration(milliseconds: 300), () {
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
}