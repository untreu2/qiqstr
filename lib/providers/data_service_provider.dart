import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/qiqstr_service.dart';

final dataServiceProvider = Provider.family<DataService, String>((ref, npub) {
  return DataService(
    npub: npub,
    dataType: DataType.Feed,
    onNewNote: null,
  );
});
