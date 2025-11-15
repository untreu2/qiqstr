import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:nostr_nip19/nostr_nip19.dart';
import '../../../models/note_model.dart';
import '../../screens/note/share_note.dart';
import '../../theme/theme_manager.dart';
import '../../../core/di/app_di.dart';
import '../../../data/repositories/note_repository.dart';
import '../../../data/repositories/auth_repository.dart';
import '../common/snackbar_widget.dart';

Future<void> showRepostDialog({
  required BuildContext context,
  required NoteModel note,
  VoidCallback? onRepostSuccess,
}) async {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.colors.background,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (modalContext) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: () async {
              Navigator.pop(modalContext);
              await _performRepost(context, note, onRepostSuccess);
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: context.colors.buttonPrimary,
                borderRadius: BorderRadius.circular(40),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.repeat, color: context.colors.buttonText, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Repost',
                    style: TextStyle(
                      color: context.colors.buttonText,
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: () {
              Navigator.pop(modalContext);
              final bech32 = encodeBasicBech32(note.id, 'note');
              final quoteText = 'nostr:$bech32';

              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ShareNotePage(
                    initialText: quoteText,
                  ),
                ),
              );
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: context.colors.overlayLight,
                borderRadius: BorderRadius.circular(40),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.format_quote, color: context.colors.textPrimary, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Quote',
                    style: TextStyle(
                      color: context.colors.textPrimary,
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
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

Future<void> _performRepost(
  BuildContext context,
  NoteModel note,
  VoidCallback? onRepostSuccess,
) async {
  try {
    final authRepository = AppDI.get<AuthRepository>();
    final noteRepository = AppDI.get<NoteRepository>();

    final currentUserResult = await authRepository.getCurrentUserNpub();
    if (currentUserResult.isError || currentUserResult.data == null) {
      if (context.mounted) {
        AppSnackbar.error(context, 'Please log in to repost');
      }
      return;
    }

    final result = await noteRepository.repostNote(note.id);
    if (result.isError) {
      if (context.mounted) {
        AppSnackbar.error(context, 'Failed to repost: ${result.error}');
      }
    } else {
      onRepostSuccess?.call();
    }
  } catch (e) {
    if (kDebugMode) {
      print('Error reposting note: $e');
    }
    if (context.mounted) {
      AppSnackbar.error(context, 'Failed to repost note');
    }
  }
}
