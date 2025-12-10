import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../../models/user_model.dart';
import '../home_navigator.dart';
import '../../theme/theme_manager.dart';
import '../../widgets/common/common_buttons.dart';
import '../../widgets/common/title_widget.dart';
import '../../../core/ui/ui_state_builder.dart';
import '../../../core/di/app_di.dart';
import '../../../presentation/viewmodels/suggested_follows_viewmodel.dart';
import '../../../presentation/providers/viewmodel_provider.dart';

class SuggestedFollowsPage extends StatelessWidget {
  final String npub;

  const SuggestedFollowsPage({
    super.key,
    required this.npub,
  });

  @override
  Widget build(BuildContext context) {
    return ViewModelBuilder<SuggestedFollowsViewModel>(
      create: () => SuggestedFollowsViewModel(
        userRepository: AppDI.get(),
        authRepository: AppDI.get(),
        nostrDataService: AppDI.get(),
      ),
      builder: (context, viewModel) {
        return Scaffold(
          backgroundColor: context.colors.background,
          body: UIStateBuilder<List<UserModel>>(
            state: viewModel.suggestedUsersState,
            builder: (context, users) => _buildContent(context, viewModel, users),
            loading: () => Center(
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
            error: (error) => Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline, size: 64, color: context.colors.error),
                  const SizedBox(height: 16),
                  Text(
                    'Failed to load suggested users',
                    style: TextStyle(color: context.colors.error, fontSize: 18),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    error,
                    style: TextStyle(color: context.colors.textSecondary),
                  ),
                  const SizedBox(height: 16),
                  PrimaryButton(
                    label: 'Retry',
                    onPressed: () => viewModel.loadSuggestedUsers(),
                    size: ButtonSize.large,
                  ),
                ],
              ),
            ),
            empty: (message) => Center(
              child: Text(
                message ?? 'No suggested users available at the moment.',
                style: TextStyle(
                  color: context.colors.textSecondary,
                  fontSize: 16,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildContent(BuildContext context, SuggestedFollowsViewModel viewModel, List<UserModel> users) {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(context),
                const SizedBox(height: 16),
                ...users.asMap().entries.map((entry) {
                  final index = entry.key;
                  final user = entry.value;
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildUserItem(context, user, viewModel),
                      if (index < users.length - 1) const _UserSeparator(),
                    ],
                  );
                }),
                const SizedBox(height: 120),
              ],
            ),
          ),
        ),
        _buildBottomSection(context, viewModel),
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

  Widget _buildUserItem(BuildContext context, UserModel user, SuggestedFollowsViewModel viewModel) {
    final isSelected = viewModel.selectedUsers.contains(user.npub);
    
    return GestureDetector(
      onTap: () => viewModel.toggleUserSelection(user.npub),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            _buildAvatar(context, user.profileImage),
            const SizedBox(width: 12),
            Expanded(
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      user.name.length > 25 ? '${user.name.substring(0, 25)}...' : user.name,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: context.colors.textPrimary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (user.nip05.isNotEmpty && user.nip05Verified) ...[
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
                  color: isSelected ? context.colors.accent : context.colors.border,
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


  Widget _buildBottomSection(BuildContext context, SuggestedFollowsViewModel viewModel) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
      decoration: BoxDecoration(
        color: context.colors.background,
      ),
      child: SizedBox(
        width: double.infinity,
        child: _buildContinueButton(context, viewModel),
      ),
    );
  }

  Widget _buildContinueButton(BuildContext context, SuggestedFollowsViewModel viewModel) {
    final hasMinimumSelection = viewModel.selectedUsers.length >= 3;
    final isDisabled = viewModel.isProcessing || !hasMinimumSelection;

    return GestureDetector(
      onTap: isDisabled
          ? null
          : () async {
              await _continueToHome(context, viewModel);
            },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          color: isDisabled ? context.colors.textPrimary.withValues(alpha: 0.3) : context.colors.textPrimary,
          borderRadius: BorderRadius.circular(40),
        ),
        child: viewModel.isProcessing
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
                  color: isDisabled ? context.colors.background.withValues(alpha: 0.5) : context.colors.background,
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  decoration: hasMinimumSelection ? TextDecoration.none : TextDecoration.lineThrough,
                ),
              ),
      ),
    );
  }

  Future<void> _continueToHome(BuildContext context, SuggestedFollowsViewModel viewModel) async {
    viewModel.followSelectedUsers();
    _navigateToHome(context);
  }

  void _navigateToHome(BuildContext context) {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => HomeNavigator(npub: npub),
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
