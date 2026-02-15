import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../theme/theme_manager.dart';
import '../../../core/di/app_di.dart';
import '../../../data/services/auth_service.dart';
import '../../../presentation/blocs/bookmark/bookmark_bloc.dart';
import '../../../presentation/blocs/bookmark/bookmark_event.dart';
import '../../../presentation/blocs/bookmark/bookmark_state.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../widgets/common/title_widget.dart';
import '../../widgets/common/common_buttons.dart';
import '../../widgets/common/top_action_bar_widget.dart';
import '../../widgets/common/list_separator_widget.dart';
import '../../widgets/note/note_widget.dart';
import 'package:carbon_icons/carbon_icons.dart';
import '../../../l10n/app_localizations.dart';

class BookmarkPage extends StatefulWidget {
  const BookmarkPage({super.key});

  @override
  State<BookmarkPage> createState() => _BookmarkPageState();
}

class _BookmarkPageState extends State<BookmarkPage> {
  late final BookmarkBloc _bloc;
  late final ScrollController _scrollController;
  late final ValueNotifier<List<Map<String, dynamic>>> _notesNotifier;
  final ValueNotifier<bool> _showTitleBubble = ValueNotifier(false);
  String _currentUserHex = '';

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController()..addListener(_scrollListener);
    _notesNotifier = ValueNotifier([]);
    _bloc = AppDI.get<BookmarkBloc>();
    _bloc.add(const BookmarkLoadRequested());
    _loadCurrentUser();
  }

  void _scrollListener() {
    if (_scrollController.hasClients) {
      final shouldShow = _scrollController.offset > 100;
      if (_showTitleBubble.value != shouldShow) {
        _showTitleBubble.value = shouldShow;
      }
    }
  }

  Future<void> _loadCurrentUser() async {
    final result =
        await AppDI.get<AuthService>().getCurrentUserPublicKeyHex();
    if (result.isSuccess && result.data != null && mounted) {
      setState(() => _currentUserHex = result.data!);
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _showTitleBubble.dispose();
    _notesNotifier.dispose();
    _bloc.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return BlocProvider<BookmarkBloc>.value(
      value: _bloc,
      child: BlocConsumer<BookmarkBloc, BookmarkState>(
        listener: (context, state) {
          if (state is BookmarkLoaded) {
            _notesNotifier.value = state.bookmarkedNotes;
          }
        },
        builder: (context, state) {
          return Scaffold(
            backgroundColor: context.colors.background,
            body: Stack(
              children: [
                CustomScrollView(
                  controller: _scrollController,
                  slivers: [
                    SliverToBoxAdapter(
                      child: SizedBox(
                          height:
                              MediaQuery.of(context).padding.top + 60),
                    ),
                    SliverToBoxAdapter(
                      child: TitleWidget(
                        title: l10n.bookmarksTitle,
                        fontSize: 32,
                        subtitle: l10n.bookmarksSubtitle,
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                      ),
                    ),
                    const SliverToBoxAdapter(
                      child: SizedBox(height: 16),
                    ),
                    _buildContent(context, state, l10n),
                    SliverToBoxAdapter(
                      child: const SizedBox(height: 150),
                    ),
                  ],
                ),
                TopActionBarWidget(
                  onBackPressed: () => context.pop(),
                  showShareButton: false,
                  centerBubble: Text(
                    l10n.bookmarksTitle,
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
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildContent(
      BuildContext context, BookmarkState state, AppLocalizations l10n) {
    return switch (state) {
      BookmarkLoading() => SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Center(
              child: CircularProgressIndicator(
                color: context.colors.textPrimary,
              ),
            ),
          ),
        ),
      BookmarkError(:final message) => SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Center(
              child: Column(
                children: [
                  Icon(
                    CarbonIcons.warning,
                    size: 48,
                    color: context.colors.error,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    l10n.errorLoadingBookmarks,
                    style: TextStyle(
                      color: context.colors.textPrimary,
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    message,
                    style: TextStyle(
                      color: context.colors.textSecondary,
                      fontSize: 15,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  PrimaryButton(
                    label: l10n.retryText,
                    onPressed: () {
                      context
                          .read<BookmarkBloc>()
                          .add(const BookmarkLoadRequested());
                    },
                    backgroundColor: context.colors.accent,
                    foregroundColor: context.colors.background,
                  ),
                ],
              ),
            ),
          ),
        ),
      BookmarkLoaded(:final bookmarkedNotes, :final isSyncing) =>
        bookmarkedNotes.isEmpty && isSyncing
            ? SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Center(
                    child: CircularProgressIndicator(
                      color: context.colors.textPrimary,
                    ),
                  ),
                ),
              )
            : bookmarkedNotes.isEmpty
                ? SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Center(
                        child: Column(
                          children: [
                            Icon(
                              CarbonIcons.bookmark,
                              size: 48,
                              color: context.colors.textSecondary,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              l10n.noBookmarks,
                              style: TextStyle(
                                color: context.colors.textPrimary,
                                fontSize: 17,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              l10n.youHaventBookmarkedAnyNotesYet,
                              style: TextStyle(
                                color: context.colors.textSecondary,
                                fontSize: 15,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                : SliverMainAxisGroup(
                    slivers: [
                      SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final note = bookmarkedNotes[index];
                            final noteId = note['id'] as String? ?? '';

                            return RepaintBoundary(
                              key: ValueKey('bookmark_note_$noteId'),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  NoteWidget(
                                    note: note,
                                    currentUserHex: _currentUserHex,
                                    notesNotifier: _notesNotifier,
                                    profiles: const {},
                                  ),
                                  if (index < bookmarkedNotes.length - 1)
                                    const ListSeparatorWidget(),
                                ],
                              ),
                            );
                          },
                          childCount: bookmarkedNotes.length,
                        ),
                      ),
                      if (isSyncing)
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Center(
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: context.colors.textSecondary,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
      _ => const SliverToBoxAdapter(child: SizedBox()),
    };
  }
}
