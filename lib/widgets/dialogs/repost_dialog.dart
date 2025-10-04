import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:nostr_nip19/nostr_nip19.dart';
import '../../models/note_model.dart';
import '../../screens/share_note.dart';
import '../../theme/theme_manager.dart';
import '../../core/di/app_di.dart';
import '../../data/repositories/note_repository.dart';
import '../../data/repositories/auth_repository.dart';
import '../toast_widget.dart';

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
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (modalContext) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ListTile(
          leading: Icon(Icons.repeat, color: context.colors.iconPrimary),
          title: Text('Repost', style: TextStyle(color: context.colors.textPrimary, fontSize: 16)),
          onTap: () async {
            Navigator.pop(modalContext);
            await _performRepost(context, note, onRepostSuccess);
          },
        ),
        ListTile(
          leading: Icon(Icons.format_quote, color: context.colors.iconPrimary),
          title: Text('Quote', style: TextStyle(color: context.colors.textPrimary, fontSize: 16)),
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
        ),
        const SizedBox(height: 45),
      ],
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
        AppToast.error(context, 'Please log in to repost');
      }
      return;
    }

    final result = await noteRepository.repostNote(note.id);
    if (result.isError) {
      if (context.mounted) {
        AppToast.error(context, 'Failed to repost: ${result.error}');
      }
    } else {
      onRepostSuccess?.call();
      // No toast on successful repost
    }
  } catch (e) {
    if (kDebugMode) {
      print('Error reposting note: $e');
    }
    if (context.mounted) {
      AppToast.error(context, 'Failed to repost note');
    }
  }
}
