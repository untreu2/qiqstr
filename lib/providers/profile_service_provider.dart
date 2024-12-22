import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/qiqstr_service.dart';
import '../models/note_model.dart';

final profileServiceProvider = FutureProvider.family<DataService, String>((ref, npub) async {
  final dataService = DataService(
    npub: npub,
    dataType: DataType.Profile,
  );

  dataService.onNewNote = (newNote) {
    print('New note in profile: ${newNote.id}');
  };
  dataService.onReactionsUpdated = (noteId, reactions) {
    print('Reactions updated for note $noteId');
  };
  dataService.onRepliesUpdated = (noteId, replies) {
    print('Replies updated for note $noteId');
  };

  ref.onDispose(() {
    print('Disposing connections for npub: $npub');
    dataService.closeConnections();
  });

  print('Initializing data service for npub: $npub');
  await dataService.initialize();

  await dataService.loadReactionsFromCache();
  await dataService.loadRepliesFromCache();
  await dataService.loadNotesFromCache((List<NoteModel> cachedNotes) {
    dataService.notes = cachedNotes;
  });

  await dataService.initializeConnections();

  print('Data service initialized successfully for npub: $npub');
  return dataService;
});

Widget build(BuildContext context, WidgetRef ref) {
  final npub = 'example_npub';
  final profileDataAsync = ref.watch(profileServiceProvider(npub));

  return profileDataAsync.when(
    data: (dataService) {
      return ListView.builder(
        itemCount: dataService.notes.length,
        itemBuilder: (context, index) {
          final note = dataService.notes[index];
          return ListTile(
            title: Text(note.content),
            subtitle: Text('By: ${note.author}'),
          );
        },
      );
    },
    loading: () => const Center(child: CircularProgressIndicator()),
    error: (error, stack) => Center(child: Text('Error: $error')),
  );
}
