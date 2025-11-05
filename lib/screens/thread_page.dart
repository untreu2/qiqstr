import 'dart:async';
import 'dart:math' as math;
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
import '../data/repositories/user_repository.dart';
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
  late ValueNotifier<List<NoteModel>> _notesNotifier;
  final Map<String, UserModel> _profiles = {};
  late final AuthRepository _authRepository;
  late final UserRepository _userRepository;
  String _currentUserNpub = '';
  UserModel? _currentUser;
  bool _showThreadBubble = false;

  int _visibleRepliesCount = 5;
  static const int _repliesPerPage = 5;
  static const int _maxInitialReplies = 20;
  static const int _maxNestedReplies = 3;

  Timer? _refreshDebounceTimer;
  bool _isRefreshing = false;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController()..addListener(_scrollListener);
    _notesNotifier = ValueNotifier<List<NoteModel>>([]);
    _authRepository = AppDI.get<AuthRepository>();
    _userRepository = AppDI.get<UserRepository>();
    _loadCurrentUser();

    if (widget.focusedNoteId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scheduleScrollToFocusedNote();
      });
    }
  }

  void _scrollListener() {
    if (_scrollController.hasClients) {
      final shouldShow = _scrollController.offset > 100;
      if (_showThreadBubble != shouldShow) {
        setState(() {
          _showThreadBubble = shouldShow;
        });
      }
    }
  }

  Future<void> _loadCurrentUser() async {
    try {
      final result = await _authRepository.getCurrentUserNpub();
      if (result.isSuccess && result.data != null) {
        setState(() {
          _currentUserNpub = result.data!;
        });

        final userResult = await _userRepository.getCurrentUser();
        if (userResult.isSuccess && userResult.data != null) {
          setState(() {
            _currentUser = userResult.data!;
          });
        }
      }
    } catch (e) {}
  }

  @override
  void dispose() {
    _refreshDebounceTimer?.cancel();
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
                  Positioned(
                    top: MediaQuery.of(context).padding.top + 8,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: AnimatedOpacity(
                        opacity: _showThreadBubble ? 1.0 : 0.0,
                        duration: const Duration(milliseconds: 300),
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
              child: _buildReplyInputSection(context),
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
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 6),
      child: FocusedNoteWidget(
        note: note,
        currentUserNpub: _currentUserNpub,
        notesNotifier: _notesNotifier,
        profiles: _profiles,
        notesListProvider: null,
      ),
    );
  }

  Widget _buildReplyInputSection(BuildContext context) {
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
                  child: _currentUser?.profileImage.isNotEmpty == true
                      ? Image.network(
                          _currentUser!.profileImage,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
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
                return RepaintBoundary(
                  key: ValueKey('reply_list_${reply.id}'),
                  child: AnimatedContainer(
                    key: ValueKey(reply.id),
                    duration: const Duration(milliseconds: 200),
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
            addRepaintBoundaries: false,
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
              _visibleRepliesCount = math.min(
                _visibleRepliesCount + _repliesPerPage,
                totalReplies,
              );
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
            'Load more (${totalReplies - _visibleRepliesCount} remaining)',
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
      key: ValueKey('reply_${reply.id}_$depth'),
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
                      Container(
                        margin: EdgeInsets.only(
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

    return RepaintBoundary(
      key: ValueKey('note_${note.id}_$depth'),
      child: NoteWidget(
        note: note,
        currentUserNpub: _currentUserNpub,
        notesNotifier: _notesNotifier,
        profiles: _profiles,
        containerColor: Colors.transparent,
        isSmallView: depth > 1,
        scrollController: _scrollController,
      ),
    );
  }

  Widget _buildSimpleNoteWidget(
    BuildContext context,
    NoteModel note, {
    bool isSmallView = false,
  }) {
    final viewModel = context.read<ThreadViewModel>();
    _profiles.addAll(viewModel.userProfiles);

    return RepaintBoundary(
      key: ValueKey('simple_note_${note.id}'),
      child: NoteWidget(
        note: note,
        currentUserNpub: _currentUserNpub,
        notesNotifier: _notesNotifier,
        profiles: _profiles,
        containerColor: context.colors.background,
        isSmallView: isSmallView,
        scrollController: _scrollController,
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

  Future<void> _debouncedRefresh(ThreadViewModel viewModel) async {
    if (_isRefreshing) return;

    _refreshDebounceTimer?.cancel();
    _refreshDebounceTimer = Timer(const Duration(milliseconds: 300), () async {
      if (!mounted) return;

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
    });
  }
}
