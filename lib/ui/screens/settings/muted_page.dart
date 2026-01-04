import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../theme/theme_manager.dart';
import '../../../models/user_model.dart';
import '../../../core/di/app_di.dart';
import '../../../presentation/viewmodels/muted_page_viewmodel.dart';
import '../../widgets/common/back_button_widget.dart';
import '../../widgets/common/title_widget.dart';
import '../../widgets/common/snackbar_widget.dart';
import '../../widgets/common/common_buttons.dart';
import 'package:carbon_icons/carbon_icons.dart';

class MutedPage extends StatelessWidget {
  const MutedPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<MutedPageViewModel>(
      create: (_) => MutedPageViewModel(
        userRepository: AppDI.get(),
        authService: AppDI.get(),
        dataService: AppDI.get(),
      ),
      child: Consumer<MutedPageViewModel>(
        builder: (context, viewModel, child) {
          return Consumer<ThemeManager>(
            builder: (context, themeManager, child) {
              return Scaffold(
                backgroundColor: context.colors.background,
                body: Stack(
                  children: [
                    SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildHeader(context),
                          const SizedBox(height: 16),
                          _buildMutedSection(context, viewModel),
                          const SizedBox(height: 150),
                        ],
                      ),
                    ),
                    const BackButtonWidget.floating(),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  static Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top + 60),
      child: const TitleWidget(
        title: 'Muted',
        fontSize: 32,
        subtitle: "Manage your muted users.",
        padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
      ),
    );
  }

  static Widget _buildMutedSection(BuildContext context, MutedPageViewModel viewModel) {
    if (viewModel.isLoading) {
      return Padding(
        padding: const EdgeInsets.all(32),
        child: Center(
          child: CircularProgressIndicator(
            color: context.colors.textPrimary,
          ),
        ),
      );
    }

    if (viewModel.error != null) {
      return Padding(
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
                'Error loading muted users',
                style: TextStyle(
                  color: context.colors.textPrimary,
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                viewModel.error!,
                style: TextStyle(
                  color: context.colors.textSecondary,
                  fontSize: 15,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              PrimaryButton(
                label: 'Retry',
                onPressed: () => viewModel.refresh(),
                backgroundColor: context.colors.accent,
                foregroundColor: context.colors.background,
              ),
            ],
          ),
        ),
      );
    }

    if (viewModel.mutedUsers.isEmpty) {
      return Padding(
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
                'No muted users',
                style: TextStyle(
                  color: context.colors.textPrimary,
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'You haven\'t muted any users yet.',
                style: TextStyle(
                  color: context.colors.textSecondary,
                  fontSize: 15,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${viewModel.mutedUsers.length} muted ${viewModel.mutedUsers.length == 1 ? 'user' : 'users'}',
            style: TextStyle(
              color: context.colors.textSecondary,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 12),
          ...viewModel.mutedUsers.map((user) => _buildUserTile(context, viewModel, user)),
        ],
      ),
    );
  }

  static Widget _buildUserTile(BuildContext context, MutedPageViewModel viewModel, UserModel user) {
    final isUnmuting = viewModel.isUnmuting(user.npub);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: context.colors.overlayLight,
        borderRadius: BorderRadius.circular(40),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: user.profileImage.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: user.profileImage,
                    width: 40,
                    height: 40,
                    fit: BoxFit.cover,
                    placeholder: (context, url) => Container(
                      width: 40,
                      height: 40,
                      color: context.colors.avatarPlaceholder,
                      child: Icon(
                        CarbonIcons.user,
                        size: 20,
                        color: context.colors.textSecondary,
                      ),
                    ),
                    errorWidget: (context, url, error) => Container(
                      width: 40,
                      height: 40,
                      color: context.colors.avatarPlaceholder,
                      child: Icon(
                        CarbonIcons.user,
                        size: 20,
                        color: context.colors.textSecondary,
                      ),
                    ),
                  )
                : Container(
                    width: 40,
                    height: 40,
                    color: context.colors.avatarPlaceholder,
                    child: Icon(
                      CarbonIcons.user,
                      size: 20,
                      color: context.colors.textSecondary,
                    ),
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user.name,
                  style: TextStyle(
                    color: context.colors.textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (user.nip05.isNotEmpty)
                  Text(
                    user.nip05,
                    style: TextStyle(
                      color: context.colors.textSecondary,
                      fontSize: 14,
                    ),
                  ),
              ],
            ),
          ),
          GestureDetector(
            onTap: isUnmuting ? null : () {
              viewModel.unmuteUser(user.npub).then((_) {
                AppSnackbar.success(context, 'User unmuted successfully');
              }).catchError((error) {
                AppSnackbar.error(context, 'Failed to unmute user: $error');
              });
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: context.colors.overlayLight,
                borderRadius: BorderRadius.circular(40),
              ),
              child: isUnmuting
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(context.colors.textPrimary),
                      ),
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          CarbonIcons.notification_off,
                          size: 16,
                          color: context.colors.textPrimary,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Unmute',
                          style: TextStyle(
                            color: context.colors.textPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
