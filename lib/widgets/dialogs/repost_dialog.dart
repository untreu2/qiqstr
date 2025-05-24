import 'package:flutter/material.dart';
import 'package:nostr_nip19/nostr_nip19.dart';
import 'package:qiqstr/models/note_model.dart';
import 'package:qiqstr/services/data_service.dart';
import 'package:qiqstr/screens/share_note.dart';

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
    backgroundColor: Colors.black,
    builder: (modalContext) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ListTile(
          leading: const Icon(Icons.repeat, color: Colors.white),
          title: const Text('Repost',
              style: TextStyle(color: Colors.white, fontSize: 16)),
          onTap: () async {
            Navigator.pop(modalContext); 
            try {
              await dataService.sendRepost(note);
            } catch (_) {
              
              
            }
          },
        ),
        ListTile(
          leading: const Icon(Icons.format_quote, color: Colors.white),
          title: const Text('Quote',
              style: TextStyle(color: Colors.white, fontSize: 16)),
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
