import 'package:flutter/material.dart';
import 'package:nostr_nip19/nostr_nip19.dart';
import 'package:qiqstr/models/note_model.dart';
import 'package:qiqstr/services/data_service.dart';
import 'package:qiqstr/screens/share_note.dart';
import 'package:qiqstr/providers/interactions_provider.dart';
import 'package:qiqstr/providers/user_provider.dart';
import '../../theme/theme_manager.dart';

Future<void> showRepostDialog({
  required BuildContext context,
  required DataService dataService,
  required NoteModel note,
}) async {
  return showModalBottomSheet(
    context: context,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    backgroundColor: context.colors.background,
    builder: (modalContext) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ListTile(
          leading: Icon(Icons.repeat, color: context.colors.iconPrimary),
          title: Text('Repost', style: TextStyle(color: context.colors.textPrimary, fontSize: 16)),
          onTap: () async {
            Navigator.pop(modalContext);
            await _performOptimisticRepost(context, dataService, note);
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
                  dataService: dataService,
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

Future<void> _performOptimisticRepost(
  BuildContext context,
  DataService dataService,
  NoteModel note,
) async {
  final currentUserNpub = UserProvider.instance.currentUser?.npub;
  if (currentUserNpub == null) return;

  InteractionsProvider.instance.addOptimisticRepost(note.id, currentUserNpub);

  try {
    await dataService.sendRepost(note);
  } catch (e) {
    print('Error sending repost: $e');

    InteractionsProvider.instance.removeOptimisticRepost(note.id, currentUserNpub);
  }
}
