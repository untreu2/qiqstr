import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../theme/theme_manager.dart';
import '../../../core/di/app_di.dart';
import '../../../data/repositories/interaction_repository.dart';
import '../../../data/repositories/profile_repository.dart';
import '../../../data/services/auth_service.dart';
import '../../../presentation/blocs/note_statistics/note_statistics_bloc.dart';
import '../../../presentation/blocs/note_statistics/note_statistics_event.dart';
import '../../../presentation/blocs/note_statistics/note_statistics_state.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../widgets/common/title_widget.dart';
import '../../widgets/common/top_action_bar_widget.dart';
import '../../../l10n/app_localizations.dart';

class NoteStatisticsPage extends StatefulWidget {
  final String noteId;

  const NoteStatisticsPage({
    super.key,
    required this.noteId,
  });

  @override
  State<NoteStatisticsPage> createState() => _NoteStatisticsPageState();
}

class _NoteStatisticsPageState extends State<NoteStatisticsPage> {
  late ScrollController _scrollController;
  final ValueNotifier<bool> _showInteractionsBubble = ValueNotifier(false);

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController()..addListener(_scrollListener);
  }

  void _scrollListener() {
    if (_scrollController.hasClients) {
      final shouldShow = _scrollController.offset > 100;
      if (_showInteractionsBubble.value != shouldShow) {
        _showInteractionsBubble.value = shouldShow;
      }
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _showInteractionsBubble.dispose();
    super.dispose();
  }

  void _navigateToProfile(String npub, Map<String, dynamic>? user) {
    try {
      if (!mounted) return;

      final userNpubValue = user?['npub'];
      final userNpub = userNpubValue is String
          ? userNpubValue
          : (userNpubValue?.toString() ?? npub);

      final userPubkeyHexValue = user?['pubkeyHex'];
      final userPubkeyHex = userPubkeyHexValue is String
          ? userPubkeyHexValue
          : (userPubkeyHexValue?.toString() ?? '');

      if (!mounted) return;

      final currentLocation = GoRouterState.of(context).matchedLocation;
      if (currentLocation.startsWith('/home/feed')) {
        context.push(
            '/home/feed/profile?npub=${Uri.encodeComponent(userNpub)}&pubkeyHex=${Uri.encodeComponent(userPubkeyHex)}');
      } else if (currentLocation.startsWith('/home/notifications')) {
        context.push(
            '/home/notifications/profile?npub=${Uri.encodeComponent(userNpub)}&pubkeyHex=${Uri.encodeComponent(userPubkeyHex)}');
      } else {
        context.push(
            '/profile?npub=${Uri.encodeComponent(userNpub)}&pubkeyHex=${Uri.encodeComponent(userPubkeyHex)}');
      }
    } catch (e) {
      debugPrint('[NoteStatisticsPage] Navigate to profile error: $e');
    }
  }

  Widget _buildEntry({
    required String npub,
    required String content,
    int? zapAmount,
    Map<String, dynamic>? user,
  }) {
    if (user == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            _buildAvatar(context, ''),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                npub.length > 8 ? '${npub.substring(0, 8)}...' : npub,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: context.colors.textPrimary,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final userProfileImageValue = user['profileImage'];
    final userProfileImage = userProfileImageValue is String
        ? userProfileImageValue
        : (userProfileImageValue?.toString() ?? '');

    final userNameValue = user['name'];
    final userName = userNameValue is String
        ? userNameValue
        : (userNameValue?.toString() ?? '');

    final userNip05Value = user['nip05'];
    final userNip05 = userNip05Value is String
        ? userNip05Value
        : (userNip05Value?.toString() ?? '');

    final userNip05VerifiedValue = user['nip05Verified'];
    final userNip05Verified = userNip05VerifiedValue is bool
        ? userNip05VerifiedValue
        : (userNip05VerifiedValue == true || userNip05VerifiedValue == 'true');

    Widget? trailing;
    if (zapAmount != null || content.isNotEmpty) {
      trailing = Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (zapAmount != null)
            Text(
              ' $zapAmount sats',
              style: TextStyle(
                color: context.colors.accent,
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
          if (content.isNotEmpty) ...[
            if (zapAmount != null) const SizedBox(width: 12),
            Flexible(
              child: Text(
                content,
                style: TextStyle(
                  color: context.colors.textPrimary,
                  fontSize: content.length <= 5 ? 20 : 15,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ],
      );
    }

    return GestureDetector(
      onTap: () => _navigateToProfile(npub, user),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            _buildAvatar(context, userProfileImage),
            const SizedBox(width: 12),
            Expanded(
              child: Row(
                mainAxisAlignment: trailing != null
                    ? MainAxisAlignment.spaceBetween
                    : MainAxisAlignment.start,
                children: [
                  Flexible(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            userName.length > 25
                                ? '${userName.substring(0, 25)}...'
                                : userName,
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                              color: context.colors.textPrimary,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (userNip05.isNotEmpty && userNip05Verified) ...[
                          const SizedBox(width: 4),
                          Icon(
                            Icons.verified,
                            size: 16,
                            color: context.colors.accent,
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (trailing != null) ...[
                    Flexible(
                      child: trailing,
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

  Widget _buildAvatar(BuildContext context, String imageUrl) {
    if (imageUrl.isEmpty) {
      return CircleAvatar(
        radius: 24,
        backgroundColor: Colors.grey.shade800,
        child: Icon(
          Icons.person,
          size: 26,
          color: context.colors.textSecondary,
        ),
      );
    }

    return ClipOval(
      child: Container(
        width: 48,
        height: 48,
        color: Colors.transparent,
        child: CachedNetworkImage(
          imageUrl: imageUrl,
          width: 48,
          height: 48,
          fit: BoxFit.cover,
          fadeInDuration: Duration.zero,
          fadeOutDuration: Duration.zero,
          memCacheWidth: 192,
          placeholder: (context, url) => Container(
            color: Colors.grey.shade800,
            child: Icon(
              Icons.person,
              size: 26,
              color: context.colors.textSecondary,
            ),
          ),
          errorWidget: (context, url, error) => Container(
            color: Colors.grey.shade800,
            child: Icon(
              Icons.person,
              size: 26,
              color: context.colors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return TitleWidget(
      title: l10n.interactions,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider<NoteStatisticsBloc>(
      create: (context) {
        final bloc = NoteStatisticsBloc(
          interactionRepository: AppDI.get<InteractionRepository>(),
          profileRepository: AppDI.get<ProfileRepository>(),
          authService: AppDI.get<AuthService>(),
          noteId: widget.noteId,
        );
        bloc.add(NoteStatisticsInitialized(noteId: widget.noteId));
        return bloc;
      },
      child: BlocBuilder<NoteStatisticsBloc, NoteStatisticsState>(
        builder: (context, state) {
          final l10n = AppLocalizations.of(context)!;
          
          if (state is NoteStatisticsLoading ||
              state is NoteStatisticsInitial) {
            return Scaffold(
              backgroundColor: context.colors.background,
              body: const Center(child: CircularProgressIndicator()),
            );
          }

          if (state is! NoteStatisticsLoaded) {
            return Scaffold(
              backgroundColor: context.colors.background,
              body: const Center(child: CircularProgressIndicator()),
            );
          }

          final interactions = state.interactions;
          final users = state.users;

          final interactionWidgets = <Widget>[];
          for (int i = 0; i < interactions.length; i++) {
            final interaction = interactions[i];

            final npubValue = interaction['npub'];
            final npub =
                npubValue is String ? npubValue : (npubValue?.toString() ?? '');

            final pubkeyValue = interaction['pubkey'];
            final pubkey = pubkeyValue is String
                ? pubkeyValue
                : (pubkeyValue?.toString() ?? '');

            if (npub.isEmpty && pubkey.isEmpty) {
              continue;
            }

            final contentValue = interaction['content'];
            final content = contentValue is String
                ? contentValue
                : (contentValue?.toString() ?? '');

            final zapAmountValue = interaction['zapAmount'];
            final zapAmount = zapAmountValue is int
                ? zapAmountValue
                : (zapAmountValue is num ? zapAmountValue.toInt() : null);

            final user = users[pubkey] ?? users[npub];

            interactionWidgets.add(
              _buildEntry(
                npub: npub,
                content: content,
                zapAmount: zapAmount,
                user: user,
              ),
            );
            if (i < interactions.length - 1) {
              interactionWidgets.add(const _UserSeparator());
            }
          }

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
                      child: _buildHeader(context),
                    ),
                    SliverToBoxAdapter(
                      child: interactionWidgets.isEmpty
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.only(top: 32),
                                child: Text(
                                  l10n.noInteractionsYet,
                                  style: TextStyle(
                                      color: context.colors.textTertiary),
                                ),
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                    SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) => interactionWidgets[index],
                        childCount: interactionWidgets.length,
                        addAutomaticKeepAlives: true,
                        addRepaintBoundaries: false,
                      ),
                    ),
                    const SliverToBoxAdapter(
                      child: SizedBox(height: 150),
                    ),
                  ],
                ),
                TopActionBarWidget(
                  onBackPressed: () => context.pop(),
                  centerBubble: Text(
                    l10n.interactions,
                    style: TextStyle(
                      color: context.colors.background,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  centerBubbleVisibility: _showInteractionsBubble,
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
        },
      ),
    );
  }
}

class _UserSeparator extends StatelessWidget {
  const _UserSeparator();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 8,
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
}
