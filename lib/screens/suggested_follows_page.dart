import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../models/user_model.dart';
import '../screens/home_navigator.dart';
import '../theme/theme_manager.dart';
import '../core/ui/ui_state_builder.dart';
import '../core/di/app_di.dart';
import '../presentation/viewmodels/suggested_follows_viewmodel.dart';
import '../presentation/providers/viewmodel_provider.dart';

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
                  ElevatedButton(
                    onPressed: () => viewModel.loadSuggestedUsers(),
                    child: const Text('Retry'),
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
                const SizedBox(height: 48),
                ...users.map((user) => _buildUserTile(context, viewModel, user)),
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 100, 24, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Here are some interesting people you might want to follow to get started.',
            style: TextStyle(
              fontSize: 16,
              color: context.colors.textSecondary,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUserTile(BuildContext context, SuggestedFollowsViewModel viewModel, UserModel user) {
    final isSelected = viewModel.selectedUsers.contains(user.npub);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isSelected ? context.colors.primary : context.colors.border,
          width: isSelected ? 2 : 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => viewModel.toggleUserSelection(user.npub),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 30,
                  backgroundImage: user.profileImage.isNotEmpty ? CachedNetworkImageProvider(user.profileImage) : null,
                  backgroundColor: Colors.grey.shade700,
                  child: user.profileImage.isEmpty
                      ? Icon(
                          Icons.person,
                          size: 36,
                          color: context.colors.textSecondary,
                        )
                      : null,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              user.name.isNotEmpty ? user.name : 'Anonymous',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: context.colors.textPrimary,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (user.nip05.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                '• ${user.nip05}',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: context.colors.secondary,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isSelected ? context.colors.primary : Colors.transparent,
                    border: Border.all(
                      color: isSelected ? context.colors.primary : context.colors.border,
                      width: 2,
                    ),
                  ),
                  child: isSelected
                      ? Icon(
                          Icons.check,
                          color: context.colors.buttonText,
                          size: 16,
                        )
                      : null,
                ),
              ],
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
        border: Border(
          top: BorderSide(color: context.colors.border),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: viewModel.isProcessing
                ? null
                : () async {
                    await _skipToHome(context, viewModel);
                  },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 18),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: context.colors.overlayLight,
                borderRadius: BorderRadius.circular(40),
              ),
              child: Text(
                'Skip',
                style: TextStyle(
                  color: context.colors.textPrimary,
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: viewModel.isProcessing
                ? null
                : () async {
                    await _continueToHome(context, viewModel);
                  },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 18),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: context.colors.buttonPrimary,
                borderRadius: BorderRadius.circular(40),
              ),
              child: viewModel.isProcessing
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(context.colors.background),
                      ),
                    )
                  : Text(
                      'Continue',
                      style: TextStyle(
                        color: context.colors.buttonText,
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _skipToHome(BuildContext context, SuggestedFollowsViewModel viewModel) async {
    viewModel.skipToHome();
    _navigateToHome(context);
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
