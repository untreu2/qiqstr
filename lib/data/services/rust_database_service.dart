import 'dart:async';

class RustDatabaseService {
  static final RustDatabaseService _instance = RustDatabaseService._internal();
  static RustDatabaseService get instance => _instance;

  RustDatabaseService._internal();

  final _changeController = StreamController<void>.broadcast();
  Stream<void> get onChange => _changeController.stream;

  void notifyChange() {
    if (!_changeController.isClosed) {
      _changeController.add(null);
    }
  }

  Future<void> close() async {
    await _changeController.close();
  }
}
