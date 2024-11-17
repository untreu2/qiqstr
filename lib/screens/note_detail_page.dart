import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/note_model.dart';
import '../models/reaction_model.dart';

class NoteDetailPage extends StatelessWidget {
  final NoteModel note;
  final List<ReactionModel> reactions;

  const NoteDetailPage({Key? key, required this.note, required this.reactions}) : super(key: key);

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
        child: SingleChildScrollView(
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
              const SizedBox(height: 20),
              Text(
                'Reactions:',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                children: reactions.map((reaction) {
                  String displayContent = reaction.content;
                  if (displayContent.isEmpty) {
                    displayContent = '+';
                  }
                  return Text(
                    displayContent,
                    style: const TextStyle(fontSize: 24),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
