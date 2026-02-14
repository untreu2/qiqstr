import 'package:flutter/material.dart';
import 'package:carbon_icons/carbon_icons.dart';
import '../../theme/theme_manager.dart';
import '../../../data/services/auth_service.dart';
import '../../../l10n/app_localizations.dart';

Future<void> showSwitchAccountDialog({
  required BuildContext context,
  required String currentNpub,
  required List<StoredAccount> accounts,
  required Map<String, String> accountProfileImages,
  required bool isSwitching,
  required ValueChanged<String> onSwitchAccount,
  required VoidCallback onAddAccount,
}) async {
  final colors = context.colors;
  final l10n = AppLocalizations.of(context)!;
  final otherAccounts = accounts.where((a) => a.npub != currentNpub).toList();

  return showModalBottomSheet(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: colors.background,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (modalContext) => Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        bottom: MediaQuery.of(modalContext).viewInsets.bottom + 40,
        top: 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.switchAccount,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              GestureDetector(
                onTap: () => Navigator.pop(modalContext),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: colors.overlayLight,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.close,
                    size: 20,
                    color: colors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          ...otherAccounts.map((account) {
            final profileImage = accountProfileImages[account.npub];
            final displayNpub = account.npub.length > 16
                ? '${account.npub.substring(0, 10)}...${account.npub.substring(account.npub.length - 6)}'
                : account.npub;
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: GestureDetector(
                onTap: () {
                  Navigator.pop(modalContext);
                  onSwitchAccount(account.npub);
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: colors.overlayLight,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: colors.avatarPlaceholder,
                          image: profileImage != null && profileImage.isNotEmpty
                              ? DecorationImage(
                                  image: NetworkImage(profileImage),
                                  fit: BoxFit.cover,
                                )
                              : null,
                        ),
                        child: profileImage == null || profileImage.isEmpty
                            ? Center(
                                child: Icon(
                                  Icons.person,
                                  size: 16,
                                  color: colors.textSecondary,
                                ),
                              )
                            : null,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          displayNpub,
                          style: TextStyle(
                            color: colors.textPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
          GestureDetector(
            onTap: () {
              Navigator.pop(modalContext);
              onAddAccount();
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: BoxDecoration(
                color: colors.overlayLight,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Icon(CarbonIcons.add, size: 20, color: colors.textPrimary),
                  const SizedBox(width: 12),
                  Text(
                    l10n.addAccount,
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
