import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/note_model.dart';

class NoteDetailPage extends StatelessWidget {
  final NoteModel note;

  const NoteDetailPage({Key? key, required this.note}) : super(key: key);

  void _copyNoteId(BuildContext context) {
    Clipboard.setData(ClipboardData(text: note.noteId));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Note ID copied to clipboard")),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(note.authorName),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              note.authorName,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 10),
            if (note.authorProfileImage.isNotEmpty)
              CircleAvatar(
                backgroundImage: NetworkImage(note.authorProfileImage),
                radius: 40,
              ),
            const SizedBox(height: 20),
            Text(
              note.content,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 20),
            Text(
              'Published on: ${note.timestamp}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Note ID: ${note.noteId}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.copy),
                  onPressed: () => _copyNoteId(context),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
