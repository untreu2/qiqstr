import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/qiqstr_service.dart';

final noteDetailServiceProvider = FutureProvider.autoDispose.family<DataService, String>((ref, noteId) async {
  final dataService = DataService(
    npub: noteId,
    dataType: DataType.Feed,
  );

  ref.onDispose(() {
    dataService.closeConnections();
  });

  await dataService.initialize();

  await dataService.loadNotesFromCache((cachedNotes) {
    dataService.notes = cachedNotes;
  });
  await dataService.loadReactionsFromCache();
  await dataService.loadRepliesFromCache();

  await dataService.initializeConnections();

  await dataService.fetchReactionsForNotes([noteId]);
  await dataService.fetchRepliesForNotes([noteId]);

  return dataService;
});
