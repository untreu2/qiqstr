import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../theme/theme_manager.dart';
import '../../widgets/common/common_buttons.dart';
import '../../widgets/common/title_widget.dart';
import '../../../core/di/app_di.dart';
import '../../../presentation/blocs/suggested_follows/suggested_follows_bloc.dart';
import '../../../presentation/blocs/suggested_follows/suggested_follows_event.dart';
import '../../../presentation/blocs/suggested_follows/suggested_follows_state.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class SuggestedFollowsPage extends StatelessWidget {
  final String npub;

  const SuggestedFollowsPage({
    super.key,
    required this.npub,
  });

  @override
  Widget build(BuildContext context) {
    return BlocProvider<SuggestedFollowsBloc>(
      create: (context) {
        final bloc = AppDI.get<SuggestedFollowsBloc>();
        bloc.add(const SuggestedFollowsLoadRequested());
        return bloc;
      },
      child: BlocBuilder<SuggestedFollowsBloc, SuggestedFollowsState>(
        builder: (context, state) {
          return Scaffold(
            backgroundColor: context.colors.background,
            body: switch (state) {
              SuggestedFollowsLoading() => Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(color: context.colors.primary),
                      const SizedBox(height: 20),
                      Text(
                        'Loading suggested users...',
                        style: TextStyle(
                          color: context.colors.textSecondary,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ),
              SuggestedFollowsError(:final message) => Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error_outline,
                          size: 64, color: context.colors.error),
                      const SizedBox(height: 16),
                      Text(
                        'Failed to load suggested users',
                        style: TextStyle(
                            color: context.colors.error, fontSize: 18),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        message,
                        style: TextStyle(color: context.colors.textSecondary),
                      ),
                      const SizedBox(height: 16),
                      PrimaryButton(
                        label: 'Retry',
                        onPressed: () {
                          context
                              .read<SuggestedFollowsBloc>()
                              .add(const SuggestedFollowsLoadRequested());
                        },
                        size: ButtonSize.large,
                      ),
                    ],
                  ),
                ),
              SuggestedFollowsLoaded(:final suggestedUsers) =>
                suggestedUsers.isEmpty
                    ? Center(
                        child: Text(
                          'No suggested users available at the moment.',
                          style: TextStyle(
                            color: context.colors.textSecondary,
                            fontSize: 16,
                          ),
                        ),
                      )
                    : _buildContent(context, state),
              _ => const SizedBox(),
            },
          );
        },
      ),
    );
  }

  Widget _buildContent(BuildContext context, SuggestedFollowsLoaded state) {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(context),
                const SizedBox(height: 16),
                ...state.suggestedUsers.asMap().entries.map((entry) {
                  final index = entry.key;
                  final user = entry.value;
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildUserItem(context, user, state),
                      if (index < state.suggestedUsers.length - 1)
                        const _UserSeparator(),
                    ],
                  );
                }),
                const SizedBox(height: 120),
              ],
            ),
          ),
        ),
        _buildBottomSection(context, state),
      ],
    );
  }

  Widget _buildHeader(BuildContext context) {
    final double topPadding = MediaQuery.of(context).padding.top;

    return TitleWidget(
      title: 'Suggested Follows',
      fontSize: 32,
      subtitle: "Select at least 3 people to follow to get started.",
      useTopPadding: false,
      padding: EdgeInsets.fromLTRB(16, topPadding + 20, 16, 8),
    );
  }

  Widget _buildUserItem(BuildContext context, Map<String, dynamic> user,
      SuggestedFollowsLoaded state) {
    final userNpub = user['npub'] as String? ?? '';
    final isSelected = state.selectedUsers.contains(userNpub);
    final profileImage = user['profileImage'] as String? ?? '';
    final userName = user['name'] as String? ?? '';
    final nip05 = user['nip05'] as String? ?? '';
    final nip05Verified = user['nip05Verified'] as bool? ?? false;

    return GestureDetector(
      onTap: () {
        context
            .read<SuggestedFollowsBloc>()
            .add(SuggestedFollowsUserToggled(userNpub));
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            _buildAvatar(context, profileImage),
            const SizedBox(width: 12),
            Expanded(
              child: Row(
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
                  if (nip05.isNotEmpty && nip05Verified) ...[
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
            const SizedBox(width: 12),
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected ? context.colors.accent : Colors.transparent,
                border: Border.all(
                  color: isSelected
                      ? context.colors.accent
                      : context.colors.border,
                  width: 2,
                ),
              ),
              child: isSelected
                  ? Icon(
                      Icons.check,
                      color: context.colors.background,
                      size: 16,
                    )
                  : null,
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

  Widget _buildBottomSection(
      BuildContext context, SuggestedFollowsLoaded state) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
      decoration: BoxDecoration(
        color: context.colors.background,
      ),
      child: SizedBox(
        width: double.infinity,
        child: _buildContinueButton(context, state),
      ),
    );
  }

  Widget _buildContinueButton(
      BuildContext context, SuggestedFollowsLoaded state) {
    final hasMinimumSelection = state.selectedUsers.length >= 3;
    final isDisabled = state.isProcessing || !hasMinimumSelection;

    return GestureDetector(
      onTap: isDisabled
          ? null
          : () async {
              context
                  .read<SuggestedFollowsBloc>()
                  .add(const SuggestedFollowsFollowSelectedRequested());
              _navigateToHome(context);
            },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          color: isDisabled
              ? context.colors.textPrimary.withValues(alpha: 0.3)
              : context.colors.textPrimary,
          borderRadius: BorderRadius.circular(24),
        ),
        child: state.isProcessing
            ? Center(
                child: SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: context.colors.background,
                  ),
                ),
              )
            : Text(
                'Continue',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: isDisabled
                      ? context.colors.background.withValues(alpha: 0.5)
                      : context.colors.background,
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  decoration: hasMinimumSelection
                      ? TextDecoration.none
                      : TextDecoration.lineThrough,
                ),
              ),
      ),
    );
  }

  void _navigateToHome(BuildContext context) {
    context.go('/home/feed?npub=${Uri.encodeComponent(npub)}');
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
