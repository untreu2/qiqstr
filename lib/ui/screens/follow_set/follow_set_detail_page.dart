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
import '../../../data/services/follow_set_service.dart';
import '../../../domain/entities/follow_set.dart';
import '../../widgets/common/title_widget.dart';
import '../../widgets/common/top_action_bar_widget.dart';
import '../../widgets/common/common_buttons.dart';
import '../../widgets/user/user_tile_widget.dart';
import '../../../l10n/app_localizations.dart';
import '../../../src/rust/api/relay.dart' as rust_relay;
import '../../widgets/dialogs/delete_list_dialog.dart';

class FollowSetDetailPage extends StatefulWidget {
  final String dTag;
  final String? ownerPubkey;

  const FollowSetDetailPage({
    super.key,
    required this.dTag,
    this.ownerPubkey,
  });

  @override
  State<FollowSetDetailPage> createState() => _FollowSetDetailPageState();
}

class _FollowSetDetailPageState extends State<FollowSetDetailPage> {
  late final FollowSetBloc _bloc;
  late final ScrollController _scrollController;
  final ValueNotifier<bool> _showTitleBubble = ValueNotifier(false);

  bool get _isOwnList => widget.ownerPubkey == null;

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

  FollowSet? _findSet() {
    final service = FollowSetService.instance;
    if (_isOwnList) {
      return service.getByDTag(widget.dTag);
    }
    try {
      return service.followedUsersSets.firstWhere(
        (s) => s.dTag == widget.dTag && s.pubkey == widget.ownerPubkey,
      );
    } catch (_) {
      return null;
    }
  }

  List<Map<String, dynamic>> _resolveUsers(FollowSetState state) {
    if (state is! FollowSetLoaded) return [];
    if (_isOwnList) {
      return state.resolvedProfiles[widget.dTag] ?? [];
    }
    final key = '${widget.ownerPubkey}:${widget.dTag}';
    return state.resolvedProfiles[key] ??
        state.resolvedProfiles[widget.dTag] ??
        [];
  }

  void _showDeleteDialog(BuildContext context, FollowSet set) {
    showDeleteListDialog(
      context: context,
      listTitle: set.title,
      onConfirm: () {
        final service = FollowSetService.instance;
        if (set.id.isNotEmpty) {
          rust_relay.deleteEvents(
            eventIds: [set.id],
            reason: 'User deleted list',
          ).catchError((_) => '');
        }
        service.removeSet(set.dTag);
        context.pop(true);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider<FollowSetBloc>.value(
      value: _bloc,
      child: BlocBuilder<FollowSetBloc, FollowSetState>(
        builder: (context, state) {
          final currentSet = _findSet();
          final title = currentSet?.title ?? widget.dTag;
          final users = _resolveUsers(state);
          final authorInfo = (state is FollowSetLoaded && currentSet != null)
              ? state.resolvedAuthors[currentSet.pubkey]
              : null;

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
                        title: title,
                        fontSize: 32,
                        subtitle: (currentSet?.description ?? '').isNotEmpty
                            ? currentSet!.description
                            : null,
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                      ),
                    ),
                    const SliverToBoxAdapter(
                      child: SizedBox(height: 8),
                    ),
                    if (currentSet != null)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Text(
                            AppLocalizations.of(context)!
                                .memberCount(currentSet.pubkeys.length),
                            style: TextStyle(
                              color: context.colors.textSecondary,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
                    if (authorInfo != null)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                          child: GestureDetector(
                            onTap: () {
                              final pubkey = currentSet?.pubkey ?? '';
                              if (pubkey.isNotEmpty) {
                                context.push(
                                  '/home/feed/profile?pubkeyHex=${Uri.encodeComponent(pubkey)}',
                                );
                              }
                            },
                            child: Row(
                              children: [
                                ClipOval(
                                  child: (authorInfo['picture'] ?? '')
                                          .isNotEmpty
                                      ? CachedNetworkImage(
                                          imageUrl: authorInfo['picture']!,
                                          width: 24,
                                          height: 24,
                                          fit: BoxFit.cover,
                                          placeholder: (context, url) =>
                                              Container(
                                            width: 24,
                                            height: 24,
                                            color: context
                                                .colors.avatarPlaceholder,
                                            child: Icon(
                                              CarbonIcons.user,
                                              size: 12,
                                              color:
                                                  context.colors.textSecondary,
                                            ),
                                          ),
                                          errorWidget: (context, url, error) =>
                                              Container(
                                            width: 24,
                                            height: 24,
                                            color: context
                                                .colors.avatarPlaceholder,
                                            child: Icon(
                                              CarbonIcons.user,
                                              size: 12,
                                              color:
                                                  context.colors.textSecondary,
                                            ),
                                          ),
                                        )
                                      : Container(
                                          width: 24,
                                          height: 24,
                                          color:
                                              context.colors.avatarPlaceholder,
                                          child: Icon(
                                            CarbonIcons.user,
                                            size: 12,
                                            color: context.colors.textSecondary,
                                          ),
                                        ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    authorInfo['name'] ?? '',
                                    style: TextStyle(
                                      color: context.colors.textSecondary,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    const SliverToBoxAdapter(
                      child: SizedBox(height: 16),
                    ),
                    _buildMembersList(context, users),
                    if (_isOwnList && currentSet != null)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 24),
                          child: SecondaryButton(
                            label: AppLocalizations.of(context)!.deleteList,
                            icon: Icons.delete_forever,
                            onPressed: () =>
                                _showDeleteDialog(context, currentSet),
                            size: ButtonSize.large,
                            backgroundColor:
                                context.colors.error.withValues(alpha: 0.1),
                            foregroundColor: context.colors.error,
                          ),
                        ),
                      ),
                    const SliverToBoxAdapter(
                      child: SizedBox(height: 150),
                    ),
                  ],
                ),
                TopActionBarWidget(
                  onBackPressed: () => context.pop(),
                  showShareButton: false,
                  centerBubble: Text(
                    title,
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

  Widget _buildMembersList(
      BuildContext context, List<Map<String, dynamic>> users) {
    final l10n = AppLocalizations.of(context)!;

    if (users.isEmpty) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Center(
            child: Column(
              children: [
                Icon(
                  CarbonIcons.user_multiple,
                  size: 48,
                  color: context.colors.textSecondary,
                ),
                const SizedBox(height: 16),
                Text(
                  l10n.noMembersInList,
                  style: TextStyle(
                    color: context.colors.textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.noMembersInListDescription,
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
      );
    }

    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          final user = users[index];
          final pubkey = user['pubkey'] as String? ?? '';
          final tileUser = {
            'npub': user['npub'] ?? '',
            'pubkeyHex': pubkey,
            'name': user['name'] ?? '',
            'profileImage': user['picture'] ?? '',
            'nip05': '',
            'nip05Verified': false,
          };

          return UserTile(
            user: tileUser,
            showFollowButton: true,
            trailing: _isOwnList
                ? GestureDetector(
                    onTap: () {
                      if (pubkey.isNotEmpty) {
                        _bloc.add(FollowSetUserRemoved(
                          dTag: widget.dTag,
                          pubkeyHex: pubkey,
                        ));
                      }
                    },
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: context.colors.overlayLight,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        CarbonIcons.close,
                        size: 16,
                        color: context.colors.textSecondary,
                      ),
                    ),
                  )
                : null,
          );
        },
        childCount: users.length,
      ),
    );
  }
}
