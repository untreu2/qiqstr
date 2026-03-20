import '../services/rust_database_service.dart';

abstract class BaseRepository {
  final RustDatabaseService db;

  BaseRepository({
    required this.db,
  });
}
