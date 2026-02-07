import '../services/isar_database_service.dart';
import '../../domain/mappers/event_mapper.dart';

abstract class BaseRepository {
  final IsarDatabaseService db;
  final EventMapper mapper;

  BaseRepository({
    required this.db,
    required this.mapper,
  });
}
