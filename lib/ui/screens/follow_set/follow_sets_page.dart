import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:carbon_icons/carbon_icons.dart';
import '../../theme/theme_manager.dart';
import '../../../core/di/app_di.dart';
import '../../../presentation/blocs/follow_set/follow_set_bloc.dart';
import '../../../presentation/blocs/follow_set/follow_set_event.dart';
import '../../../presentation/blocs/follow_set/follow_set_state.dart';
import '../../../domain/entities/follow_set.dart';
import '../../widgets/common/title_widget.dart';
import '../../widgets/common/common_buttons.dart';
import '../../widgets/common/top_action_bar_widget.dart';
import '../../../l10n/app_localizations.dart';
import '../../widgets/dialogs/create_list_dialog.dart';
import '../../../data/services/favorite_lists_service.dart';

class FollowSetsPage extends StatefulWidget {
  const FollowSetsPage({super.key});

  @override
  State<FollowSetsPage> createState() => _FollowSetsPageState();
}

class _FollowSetsPageState extends State<FollowSetsPage> {
  late final FollowSetBloc _bloc;
  late final ScrollController _scrollController;
  final ValueNotifier<bool> _showTitleBubble = ValueNotifier(false);

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController()..addListener(_scrollListener);
    _bloc = AppDI.get<FollowSetBloc>();
    _bloc.add(const FollowSetLoadRequested());
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
    _bloc.close();
    super.dispose();
  }

  Future<void> _showCreateDialog() async {
    final result = await showCreateListDialog(context: context);
    if (result != null && mounted) {
      final title = result['title'] as String? ?? '';
      final description = result['description'] as String? ?? '';
      final pubkeys = (result['pubkeys'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [];
      if (title.isNotEmpty) {
        _bloc.add(FollowSetCreated(
          title: title,
          description: description,
          pubkeys: pubkeys,
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return BlocProvider<FollowSetBloc>.value(
      value: _bloc,
      child: BlocBuilder<FollowSetBloc, FollowSetState>(
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
                          height: MediaQuery.of(context).padding.top + 60),
                    ),
                    SliverToBoxAdapter(
                      child: TitleWidget(
                        title: l10n.listsTitle,
                        fontSize: 32,
                        subtitle: l10n.listsSubtitle,
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                      ),
                    ),
                    const SliverToBoxAdapter(
                      child: SizedBox(height: 16),
                    ),
                    ..._buildContent(context, state, l10n),
                    const SliverToBoxAdapter(
                      child: SizedBox(height: 150),
                    ),
                  ],
                ),
                TopActionBarWidget(
                  onBackPressed: () => context.pop(),
                  showShareButton: false,
                  centerBubble: Text(
                    l10n.listsTitle,
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
                  customRightWidget: GestureDetector(
                    onTap: _showCreateDialog,
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: context.colors.textPrimary,
                        borderRadius: BorderRadius.circular(22),
                      ),
                      child: Icon(
                        Icons.add,
                        color: context.colors.background,
                        size: 24,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  List<Widget> _buildContent(
      BuildContext context, FollowSetState state, AppLocalizations l10n) {
    if (state is FollowSetLoading) {
      return [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Center(
              child: CircularProgressIndicator(
                color: context.colors.textPrimary,
              ),
            ),
          ),
        ),
      ];
    }

    if (state is FollowSetError) {
      return [
        SliverToBoxAdapter(
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
                    l10n.errorLoadingLists,
                    style: TextStyle(
                      color: context.colors.textPrimary,
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    state.message,
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
                      _bloc.add(const FollowSetLoadRequested());
                    },
                    backgroundColor: context.colors.accent,
                    foregroundColor: context.colors.background,
                  ),
                ],
              ),
            ),
          ),
        ),
      ];
    }

    if (state is! FollowSetLoaded) {
      return [const SliverToBoxAdapter(child: SizedBox())];
    }

    final ownSets = state.followSets;
    final followedSets = state.followedUsersSets;
    final resolvedProfiles = state.resolvedProfiles;
    final resolvedAuthors = state.resolvedAuthors;
    final slivers = <Widget>[];

    if (ownSets.isEmpty && followedSets.isEmpty) {
      slivers.add(
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Center(
              child: Column(
                children: [
                  Icon(
                    CarbonIcons.list_boxes,
                    size: 48,
                    color: context.colors.textSecondary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    l10n.noLists,
                    style: TextStyle(
                      color: context.colors.textPrimary,
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l10n.noListsDescription,
                    style: TextStyle(
                      color: context.colors.textSecondary,
                      fontSize: 15,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      return slivers;
    }

    if (ownSets.isNotEmpty) {
      slivers.add(
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final set = ownSets[index];
                final users = resolvedProfiles[set.dTag] ?? [];
                final listId = '${set.pubkey}:${set.dTag}';
                final favService = FavoriteListsService.instance;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _FollowSetCard(
                    followSet: set,
                    users: users,
                    isAddedToFeed: favService.isFavorite(listId),
                    onFeedToggle: () {
                      favService.toggle(listId);
                      setState(() {});
                    },
                    onTap: () async {
                      final deleted = await context.push<bool>(
                        '/follow-set-detail?dTag=${Uri.encodeComponent(set.dTag)}',
                      );
                      if (deleted == true && mounted) {
                        _bloc.add(const FollowSetLoadRequested());
                      }
                    },
                  ),
                );
              },
              childCount: ownSets.length,
            ),
          ),
        ),
      );
    } else {
      slivers.add(
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
            child: Center(
              child: Column(
                children: [
                  Icon(
                    CarbonIcons.list_boxes,
                    size: 40,
                    color: context.colors.textSecondary,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    l10n.noLists,
                    style: TextStyle(
                      color: context.colors.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    l10n.noListsDescription,
                    style: TextStyle(
                      color: context.colors.textSecondary,
                      fontSize: 14,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    if (followedSets.isNotEmpty) {
      final sortedFollowedSets = List<FollowSet>.from(followedSets)
        ..sort((a, b) => b.pubkeys.length.compareTo(a.pubkeys.length));

      slivers.add(
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
            child: Text(
              l10n.listsFromFollows,
              style: TextStyle(
                color: context.colors.textSecondary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      );

      slivers.add(
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final set = sortedFollowedSets[index];
                final key = '${set.pubkey}:${set.dTag}';
                final users =
                    resolvedProfiles[key] ?? resolvedProfiles[set.dTag] ?? [];
                final listId = key;
                final favService = FavoriteListsService.instance;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _FollowSetCard(
                    followSet: set,
                    users: users,
                    authorName: resolvedAuthors[set.pubkey]?['name'],
                    authorPicture: resolvedAuthors[set.pubkey]?['picture'],
                    isAddedToFeed: favService.isFavorite(listId),
                    onFeedToggle: () {
                      favService.toggle(listId);
                      setState(() {});
                    },
                    onTap: () async {
                      final deleted = await context.push<bool>(
                        '/follow-set-detail?dTag=${Uri.encodeComponent(set.dTag)}&pubkey=${Uri.encodeComponent(set.pubkey)}',
                      );
                      if (deleted == true && mounted) {
                        _bloc.add(const FollowSetLoadRequested());
                      }
                    },
                  ),
                );
              },
              childCount: sortedFollowedSets.length,
            ),
          ),
        ),
      );
    }

    return slivers;
  }
}

class _FollowSetCard extends StatelessWidget {
  final FollowSet followSet;
  final List<Map<String, dynamic>> users;
  final VoidCallback onTap;
  final String? authorName;
  final String? authorPicture;
  final bool isAddedToFeed;
  final VoidCallback? onFeedToggle;

  const _FollowSetCard({
    required this.followSet,
    required this.users,
    required this.onTap,
    this.authorName,
    this.authorPicture,
    this.isAddedToFeed = false,
    this.onFeedToggle,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final title = followSet.title.isNotEmpty ? followSet.title : followSet.dTag;
    final memberCount = followSet.pubkeys.length;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: context.colors.overlayLight,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  CarbonIcons.list_boxes,
                  size: 22,
                  color: context.colors.textPrimary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      color: context.colors.textPrimary,
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  l10n.memberCount(memberCount),
                  style: TextStyle(
                    color: context.colors.textSecondary,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  CarbonIcons.chevron_right,
                  size: 16,
                  color: context.colors.textSecondary,
                ),
              ],
            ),
            if (followSet.description.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                followSet.description,
                style: TextStyle(
                  color: context.colors.textSecondary,
                  fontSize: 14,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            if (users.isNotEmpty) ...[
              const SizedBox(height: 14),
              _buildAvatarRow(context, users),
            ],
            if (authorName != null || onFeedToggle != null) ...[
              const SizedBox(height: 14),
              Row(
                children: [
                  if (authorName != null) ...[
                    ClipOval(
                      child: (authorPicture ?? '').isNotEmpty
                          ? CachedNetworkImage(
                              imageUrl: authorPicture!,
                              width: 20,
                              height: 20,
                              fit: BoxFit.cover,
                              placeholder: (context, url) => Container(
                                width: 20,
                                height: 20,
                                color: context.colors.avatarPlaceholder,
                                child: Icon(
                                  CarbonIcons.user,
                                  size: 10,
                                  color: context.colors.textSecondary,
                                ),
                              ),
                              errorWidget: (context, url, error) => Container(
                                width: 20,
                                height: 20,
                                color: context.colors.avatarPlaceholder,
                                child: Icon(
                                  CarbonIcons.user,
                                  size: 10,
                                  color: context.colors.textSecondary,
                                ),
                              ),
                            )
                          : Container(
                              width: 20,
                              height: 20,
                              color: context.colors.avatarPlaceholder,
                              child: Icon(
                                CarbonIcons.user,
                                size: 10,
                                color: context.colors.textSecondary,
                              ),
                            ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        authorName!,
                        style: TextStyle(
                          color: context.colors.textSecondary,
                          fontSize: 13,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ] else
                    const Spacer(),
                  if (onFeedToggle != null)
                    GestureDetector(
                      onTap: onFeedToggle,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: isAddedToFeed
                              ? context.colors.textPrimary
                              : context.colors.overlayLight,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              isAddedToFeed
                                  ? Icons.check_rounded
                                  : Icons.add_rounded,
                              size: 14,
                              color: isAddedToFeed
                                  ? context.colors.background
                                  : context.colors.textPrimary,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              isAddedToFeed
                                  ? l10n.removeFromFeed
                                  : l10n.addToFeed,
                              style: TextStyle(
                                color: isAddedToFeed
                                    ? context.colors.background
                                    : context.colors.textPrimary,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAvatarRow(
      BuildContext context, List<Map<String, dynamic>> users) {
    final displayCount = users.length > 5 ? 5 : users.length;
    final remaining = users.length - displayCount;
    const double avatarSize = 28;
    const double overlap = 6.0;
    final double stackWidth =
        avatarSize + (displayCount - 1) * (avatarSize - overlap);

    return Row(
      children: [
        SizedBox(
          width: stackWidth,
          height: avatarSize,
          child: Stack(
            children: List.generate(displayCount, (index) {
              final user = users[index];
              final picture = user['picture'] as String? ?? '';
              return Positioned(
                left: index * (avatarSize - overlap),
                child: ClipOval(
                  child: picture.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: picture,
                          width: avatarSize,
                          height: avatarSize,
                          fit: BoxFit.cover,
                          placeholder: (context, url) => Container(
                            color: context.colors.avatarPlaceholder,
                            child: Icon(
                              CarbonIcons.user,
                              size: 14,
                              color: context.colors.textSecondary,
                            ),
                          ),
                          errorWidget: (context, url, error) => Container(
                            color: context.colors.avatarPlaceholder,
                            child: Icon(
                              CarbonIcons.user,
                              size: 14,
                              color: context.colors.textSecondary,
                            ),
                          ),
                        )
                      : Container(
                          color: context.colors.avatarPlaceholder,
                          child: Icon(
                            CarbonIcons.user,
                            size: 14,
                            color: context.colors.textSecondary,
                          ),
                        ),
                ),
              );
            }),
          ),
        ),
        if (remaining > 0) ...[
          const SizedBox(width: 10),
          Text(
            '+$remaining',
            style: TextStyle(
              color: context.colors.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ],
    );
  }
}
