import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../theme/theme_manager.dart';
import '../../../l10n/app_localizations.dart';
import '../../../presentation/blocs/locale/locale_bloc.dart';
import '../../../presentation/blocs/locale/locale_event.dart';

Future<void> showLanguageDialog({
  required BuildContext context,
  required Locale currentLocale,
}) async {
  final colors = context.colors;
  final l10n = AppLocalizations.of(context)!;

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
                  l10n.language,
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
          _buildLanguageOption(
            context: context,
            modalContext: modalContext,
            colors: colors,
            l10n: l10n,
            languageName: l10n.english,
            locale: const Locale('en'),
            isSelected: currentLocale.languageCode == 'en',
          ),
          const SizedBox(height: 12),
          _buildLanguageOption(
            context: context,
            modalContext: modalContext,
            colors: colors,
            l10n: l10n,
            languageName: l10n.turkish,
            locale: const Locale('tr'),
            isSelected: currentLocale.languageCode == 'tr',
          ),
          const SizedBox(height: 12),
          _buildLanguageOption(
            context: context,
            modalContext: modalContext,
            colors: colors,
            l10n: l10n,
            languageName: l10n.german,
            locale: const Locale('de'),
            isSelected: currentLocale.languageCode == 'de',
          ),
        ],
      ),
    ),
  );
}

Widget _buildLanguageOption({
  required BuildContext context,
  required BuildContext modalContext,
  required dynamic colors,
  required AppLocalizations l10n,
  required String languageName,
  required Locale locale,
  required bool isSelected,
}) {
  return GestureDetector(
    onTap: () {
      context.read<LocaleBloc>().add(LocaleChanged(locale));
      Navigator.pop(modalContext);
    },
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: isSelected
            ? colors.primary.withValues(alpha: 0.1)
            : colors.overlayLight,
        borderRadius: BorderRadius.circular(16),
        border: isSelected ? Border.all(color: colors.primary, width: 2) : null,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              languageName,
              style: TextStyle(
                color: isSelected ? colors.primary : colors.textPrimary,
                fontSize: 17,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ),
          if (isSelected)
            Icon(
              Icons.check_circle,
              color: colors.primary,
              size: 22,
            ),
        ],
      ),
    ),
  );
}
