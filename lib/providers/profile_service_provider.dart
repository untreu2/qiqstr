import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/qiqstr_service.dart';
import '../models/note_model.dart';

final profileServiceProvider = FutureProvider.autoDispose.family<DataService, String>((ref, npub) async {
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

  ref.onDispose(dataService.closeConnections);

  await dataService.initialize();

  await dataService.loadReactionsFromCache();
  await dataService.loadRepliesFromCache();

  await dataService.loadNotesFromCache((List<NoteModel> cachedNotes) {
    dataService.notes = cachedNotes;
  });

  await dataService.initializeConnections();

  return dataService;
});
