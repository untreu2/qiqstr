import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../theme/theme_manager.dart';
import '../../../core/di/app_di.dart';
import '../../../presentation/blocs/muted/muted_bloc.dart';
import '../../../presentation/blocs/muted/muted_event.dart';
import '../../../presentation/blocs/muted/muted_state.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../widgets/common/back_button_widget.dart';
import '../../widgets/common/title_widget.dart';
import '../../widgets/common/common_buttons.dart';
import 'package:carbon_icons/carbon_icons.dart';
import '../../../l10n/app_localizations.dart';

class MutedPage extends StatelessWidget {
  const MutedPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return BlocProvider<MutedBloc>(
      create: (context) {
        final bloc = AppDI.get<MutedBloc>();
        bloc.add(const MutedLoadRequested());
        return bloc;
      },
      child: BlocBuilder<MutedBloc, MutedState>(
        builder: (context, state) {
          return Scaffold(
            backgroundColor: context.colors.background,
            body: Stack(
              children: [
                SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildHeader(context, l10n),
                      const SizedBox(height: 16),
                      _buildMutedSection(context, state, l10n),
                      const SizedBox(height: 150),
                    ],
                  ),
                ),
                const BackButtonWidget.floating(),
              ],
            ),
          );
        },
      ),
    );
  }

  static Widget _buildHeader(BuildContext context, AppLocalizations l10n) {
    return Padding(
      padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top + 60),
      child: TitleWidget(
        title: l10n.mutedTitle,
        fontSize: 32,
        subtitle: l10n.mutedSubtitle,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      ),
    );
  }

  static Widget _buildMutedSection(BuildContext context, MutedState state, AppLocalizations l10n) {
    return switch (state) {
      MutedLoading() => Padding(
          padding: const EdgeInsets.all(32),
          child: Center(
            child: CircularProgressIndicator(
              color: context.colors.textPrimary,
            ),
          ),
        ),
      MutedError(:final message) => Padding(
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
                  l10n.errorLoadingMutedUsers,
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
                    context.read<MutedBloc>().add(const MutedLoadRequested());
                  },
                  backgroundColor: context.colors.accent,
                  foregroundColor: context.colors.background,
                ),
              ],
            ),
          ),
        ),
      MutedLoaded(:final mutedUsers) => mutedUsers.isEmpty
          ? Padding(
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
                      l10n.noMutedUsers,
                      style: TextStyle(
                        color: context.colors.textPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      l10n.youHaventMutedAnyUsersYet,
                      style: TextStyle(
                        color: context.colors.textSecondary,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
              ),
            )
          : Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.mutedUsersCount(mutedUsers.length),
                    style: TextStyle(
                      color: context.colors.textSecondary,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ...mutedUsers
                      .map((user) => _buildUserTile(context, state, user, l10n)),
                ],
              ),
            ),
      _ => const SizedBox(),
    };
  }

  static Widget _buildUserTile(
      BuildContext context, MutedLoaded state, Map<String, dynamic> user, AppLocalizations l10n) {
    final userNpub = user['npub'] as String? ?? '';
    final isUnmuting = state.unmutingStates[userNpub] ?? false;
    final profileImage = user['profileImage'] as String? ?? '';
    final userName = user['name'] as String? ?? '';
    final nip05 = user['nip05'] as String? ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: context.colors.overlayLight,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: profileImage.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: profileImage,
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
                  userName,
                  style: TextStyle(
                    color: context.colors.textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (nip05.isNotEmpty)
                  Text(
                    nip05,
                    style: TextStyle(
                      color: context.colors.textSecondary,
                      fontSize: 14,
                    ),
                  ),
              ],
            ),
          ),
          GestureDetector(
            onTap: isUnmuting
                ? null
                : () {
                    context.read<MutedBloc>().add(MutedUserUnmuted(userNpub));
                  },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: context.colors.overlayLight,
                borderRadius: BorderRadius.circular(24),
              ),
              child: isUnmuting
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(
                            context.colors.textPrimary),
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
                          l10n.unmute,
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
