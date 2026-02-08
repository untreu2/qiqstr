import '../services/rust_database_service.dart';
import '../../domain/mappers/event_mapper.dart';

abstract class BaseRepository {
  final RustDatabaseService db;
  final EventMapper mapper;

  BaseRepository({
    required this.db,
    required this.mapper,
  });
}
