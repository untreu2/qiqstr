// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'note_count_model_isar.dart';

// **************************************************************************
// IsarCollectionGenerator
// **************************************************************************

// coverage:ignore-file
// ignore_for_file: duplicate_ignore, non_constant_identifier_names, constant_identifier_names, invalid_use_of_protected_member, unnecessary_cast, prefer_const_constructors, lines_longer_than_80_chars, require_trailing_commas, inference_failure_on_function_invocation, unnecessary_parenthesis, unnecessary_raw_strings, unnecessary_null_checks, join_return_with_assignment, prefer_final_locals, avoid_js_rounded_ints, avoid_positional_boolean_parameters, always_specify_types

extension GetNoteCountModelIsarCollection on Isar {
  IsarCollection<NoteCountModelIsar> get noteCountModelIsars =>
      this.collection();
}

const NoteCountModelIsarSchema = CollectionSchema(
  name: r'NoteCountModelIsar',
  id: 469096896815884342,
  properties: {
    r'cachedAt': PropertySchema(
      id: 0,
      name: r'cachedAt',
      type: IsarType.dateTime,
    ),
    r'noteId': PropertySchema(
      id: 1,
      name: r'noteId',
      type: IsarType.string,
    ),
    r'reactionCount': PropertySchema(
      id: 2,
      name: r'reactionCount',
      type: IsarType.long,
    ),
    r'replyCount': PropertySchema(
      id: 3,
      name: r'replyCount',
      type: IsarType.long,
    ),
    r'repostCount': PropertySchema(
      id: 4,
      name: r'repostCount',
      type: IsarType.long,
    ),
    r'updatedAt': PropertySchema(
      id: 5,
      name: r'updatedAt',
      type: IsarType.dateTime,
    ),
    r'zapAmount': PropertySchema(
      id: 6,
      name: r'zapAmount',
      type: IsarType.long,
    )
  },
  estimateSize: _noteCountModelIsarEstimateSize,
  serialize: _noteCountModelIsarSerialize,
  deserialize: _noteCountModelIsarDeserialize,
  deserializeProp: _noteCountModelIsarDeserializeProp,
  idName: r'id',
  indexes: {
    r'noteId': IndexSchema(
      id: -9014133502494436840,
      name: r'noteId',
      unique: true,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'noteId',
          type: IndexType.hash,
          caseSensitive: true,
        )
      ],
    )
  },
  links: {},
  embeddedSchemas: {},
  getId: _noteCountModelIsarGetId,
  getLinks: _noteCountModelIsarGetLinks,
  attach: _noteCountModelIsarAttach,
  version: '3.1.0+1',
);

int _noteCountModelIsarEstimateSize(
  NoteCountModelIsar object,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  var bytesCount = offsets.last;
  bytesCount += 3 + object.noteId.length * 3;
  return bytesCount;
}

void _noteCountModelIsarSerialize(
  NoteCountModelIsar object,
  IsarWriter writer,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  writer.writeDateTime(offsets[0], object.cachedAt);
  writer.writeString(offsets[1], object.noteId);
  writer.writeLong(offsets[2], object.reactionCount);
  writer.writeLong(offsets[3], object.replyCount);
  writer.writeLong(offsets[4], object.repostCount);
  writer.writeDateTime(offsets[5], object.updatedAt);
  writer.writeLong(offsets[6], object.zapAmount);
}

NoteCountModelIsar _noteCountModelIsarDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = NoteCountModelIsar();
  object.cachedAt = reader.readDateTime(offsets[0]);
  object.id = id;
  object.noteId = reader.readString(offsets[1]);
  object.reactionCount = reader.readLong(offsets[2]);
  object.replyCount = reader.readLong(offsets[3]);
  object.repostCount = reader.readLong(offsets[4]);
  object.updatedAt = reader.readDateTime(offsets[5]);
  object.zapAmount = reader.readLong(offsets[6]);
  return object;
}

P _noteCountModelIsarDeserializeProp<P>(
  IsarReader reader,
  int propertyId,
  int offset,
  Map<Type, List<int>> allOffsets,
) {
  switch (propertyId) {
    case 0:
      return (reader.readDateTime(offset)) as P;
    case 1:
      return (reader.readString(offset)) as P;
    case 2:
      return (reader.readLong(offset)) as P;
    case 3:
      return (reader.readLong(offset)) as P;
    case 4:
      return (reader.readLong(offset)) as P;
    case 5:
      return (reader.readDateTime(offset)) as P;
    case 6:
      return (reader.readLong(offset)) as P;
    default:
      throw IsarError('Unknown property with id $propertyId');
  }
}

Id _noteCountModelIsarGetId(NoteCountModelIsar object) {
  return object.id;
}

List<IsarLinkBase<dynamic>> _noteCountModelIsarGetLinks(
    NoteCountModelIsar object) {
  return [];
}

void _noteCountModelIsarAttach(
    IsarCollection<dynamic> col, Id id, NoteCountModelIsar object) {
  object.id = id;
}

extension NoteCountModelIsarByIndex on IsarCollection<NoteCountModelIsar> {
  Future<NoteCountModelIsar?> getByNoteId(String noteId) {
    return getByIndex(r'noteId', [noteId]);
  }

  NoteCountModelIsar? getByNoteIdSync(String noteId) {
    return getByIndexSync(r'noteId', [noteId]);
  }

  Future<bool> deleteByNoteId(String noteId) {
    return deleteByIndex(r'noteId', [noteId]);
  }

  bool deleteByNoteIdSync(String noteId) {
    return deleteByIndexSync(r'noteId', [noteId]);
  }

  Future<List<NoteCountModelIsar?>> getAllByNoteId(List<String> noteIdValues) {
    final values = noteIdValues.map((e) => [e]).toList();
    return getAllByIndex(r'noteId', values);
  }

  List<NoteCountModelIsar?> getAllByNoteIdSync(List<String> noteIdValues) {
    final values = noteIdValues.map((e) => [e]).toList();
    return getAllByIndexSync(r'noteId', values);
  }

  Future<int> deleteAllByNoteId(List<String> noteIdValues) {
    final values = noteIdValues.map((e) => [e]).toList();
    return deleteAllByIndex(r'noteId', values);
  }

  int deleteAllByNoteIdSync(List<String> noteIdValues) {
    final values = noteIdValues.map((e) => [e]).toList();
    return deleteAllByIndexSync(r'noteId', values);
  }

  Future<Id> putByNoteId(NoteCountModelIsar object) {
    return putByIndex(r'noteId', object);
  }

  Id putByNoteIdSync(NoteCountModelIsar object, {bool saveLinks = true}) {
    return putByIndexSync(r'noteId', object, saveLinks: saveLinks);
  }

  Future<List<Id>> putAllByNoteId(List<NoteCountModelIsar> objects) {
    return putAllByIndex(r'noteId', objects);
  }

  List<Id> putAllByNoteIdSync(List<NoteCountModelIsar> objects,
      {bool saveLinks = true}) {
    return putAllByIndexSync(r'noteId', objects, saveLinks: saveLinks);
  }
}

extension NoteCountModelIsarQueryWhereSort
    on QueryBuilder<NoteCountModelIsar, NoteCountModelIsar, QWhere> {
  QueryBuilder<NoteCountModelIsar, NoteCountModelIsar, QAfterWhere> anyId() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(const IdWhereClause.any());
    });
  }
}

extension NoteCountModelIsarQueryWhere
    on QueryBuilder<NoteCountModelIsar, NoteCountModelIsar, QWhereClause> {
  QueryBuilder<NoteCountModelIsar, NoteCountModelIsar, QAfterWhereClause>
      idEqualTo(Id id) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(
        lower: id,
        upper: id,
      ));
    });
  }

  QueryBuilder<NoteCountModelIsar, NoteCountModelIsar, QAfterWhereClause>
      idNotEqualTo(Id id) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(
              IdWhereClause.lessThan(upper: id, includeUpper: false),
            )
            .addWhereClause(
              IdWhereClause.greaterThan(lower: id, includeLower: false),
            );
      } else {
        return query
            .addWhereClause(
              IdWhereClause.greaterThan(lower: id, includeLower: false),
            )
            .addWhereClause(
              IdWhereClause.lessThan(upper: id, includeUpper: false),
            );
      }
    });
  }

  QueryBuilder<NoteCountModelIsar, NoteCountModelIsar, QAfterWhereClause>
      idGreaterThan(Id id, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.greaterThan(lower: id, includeLower: include),
      );
    });
  }

  QueryBuilder<NoteCountModelIsar, NoteCountModelIsar, QAfterWhereClause>
      idLessThan(Id id, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.lessThan(upper: id, includeUpper: include),
      );
    });
  }

  QueryBuilder<NoteCountModelIsar, NoteCountModelIsar, QAfterWhereClause>
      idBetween(
    Id lowerId,
    Id upperId, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(
        lower: lowerId,
        includeLower: includeLower,
        upper: upperId,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<NoteCountModelIsar, NoteCountModelIsar, QAfterWhereClause>
      noteIdEqualTo(String noteId) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'noteId',
        value: [noteId],
      ));
    });
  }

  QueryBuilder<NoteCountModelIsar, NoteCountModelIsar, QAfterWhereClause>
      noteIdNotEqualTo(String noteId) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'noteId',
              lower: [],
              upper: [noteId],
              includeUpper: false,
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'noteId',
              lower: [noteId],
              includeLower: false,
              upper: [],
            ));
      } else {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'noteId',
              lower: [noteId],
              includeLower: false,
              upper: [],
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'noteId',
              lower: [],
              upper: [noteId],
              includeUpper: false,
            ));
      }
    });
  }
}

extension NoteCountModelIsarQueryFilter
    on QueryBuilder<NoteCountModelIsar, NoteCountModelIsar, QFilterCondition> {
  QueryBuilder<NoteCountModelIsar, NoteCountModelIsar, QAfterFilterCondition>
      cachedAtEqualTo(DateTime value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'cachedAt',
        value: value,
      ));
    });
  }

  QueryBuilder<NoteCountModelIsar, NoteCountModelIsar, QAfterFilterCondition>
      cachedAtGreaterThan(
    DateTime value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'cachedAt',
        value: value,
      ));
    });
  }

  QueryBuilder<NoteCountModelIsar, NoteCountModelIsar, QAfterFilterCondition>
      cachedAtLessThan(
    DateTime value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'cachedAt',
        value: value,
      ));
    });
  }

  QueryBuilder<NoteCountModelIsar, NoteCountModelIsar, QAfterFilterCondition>
      cachedAtBetween(
    DateTime lower,
    DateTime upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'cachedAt',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<NoteCountModelIsar, NoteCountModelIsar, QAfterFilterCondition>
      idEqualTo(Id value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<NoteCountModelIsar, NoteCountModelIsar, QAfterFilterCondition>
      idGreaterThan(
    Id value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<NoteCountModelIsar, NoteCountModelIsar, QAfterFilterCondition>
      idLessThan(
    Id value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<NoteCountModelIsar, NoteCountModelIsar, QAfterFilterCondition>
      idBetween(
    Id lower,
    Id upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'id',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<NoteCountModelIsar, NoteCountModelIsar, QAfterFilterCondition>
      noteIdEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'noteId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<NoteCountModelIsar, NoteCountModelIsar, QAfterFilterCondition>
      noteIdGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'noteId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<NoteCountModelIsar, NoteCountModelIsar, QAfterFilterCondition>
      noteIdLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'noteId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<NoteCountModelIsar, NoteCountModelIsar, QAfterFilterCondition>
      noteIdBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'noteId',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<NoteCountModelIsar, NoteCountModelIsar, QAfterFilterCondition>
      noteIdStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'noteId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<NoteCountModelIsar, NoteCountModelIsar, QAfterFilterCondition>
      noteIdEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'noteId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<NoteCountModelIsar, NoteCountModelIsar, QAfterFilterCondition>
      noteIdContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'noteId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<NoteCountModelIsar, NoteCountModelIsar, QAfterFilterCondition>
      noteIdMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'noteId',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<NoteCountModelIsar, NoteCountModelIsar, QAfterFilterCondition>
      noteIdIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'noteId',
        value: '',
      ));
    });
  }

  QueryBuilder<NoteCountModelIsar, NoteCountModelIsar, QAfterFilterCondition>
      noteIdIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'noteId',
        value: '',
      ));
    });
  }

  QueryBuilder<NoteCountModelIsar, NoteCountModelIsar, QAfterFilterCondition>
      reactionCountEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'reactionCount',
        value: value,
      ));
    });
  }

  QueryBuilder<NoteCountModelIsar, NoteCountModelIsar, QAfterFilterCondition>
      reactionCountGreaterThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'reactionCount',
        value: value,
      ));
    });
  }

  QueryBuilder<NoteCountModelIsar, NoteCountModelIsar, QAfterFilterCondition>
      reactionCountLessThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'reactionCount',
        value: value,
      ));
    });
  }

  QueryBuilder<NoteCountModelIsar, NoteCountModelIsar, QAfterFilterCondition>
      reactionCountBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'reactionCount',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<NoteCountModelIsar, NoteCountModelIsar, QAfterFilterCondition>
      replyCountEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'replyCount',
        value: value,
      ));
    });
  }

  QueryBuilder<NoteCountModelIsar, NoteCountModelIsar, QAfterFilterCondition>
      replyCountGreaterThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'replyCount',
        value: value,
      ));
    });
  }

  QueryBuilder<NoteCountModelIsar, NoteCountModelIsar, QAfterFilterCondition>
      replyCountLessThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'replyCount',
        value: value,
      ));
    });
  }

  QueryBuilder<NoteCountModelIsar, NoteCountModelIsar, QAfterFilterCondition>
      replyCountBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'replyCount',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<NoteCountModelIsar, NoteCountModelIsar, QAfterFilterCondition>
      repostCountEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'repostCount',
        value: value,
      ));
    });
  }

  QueryBuilder<NoteCountModelIsar, NoteCountModelIsar, QAfterFilterCondition>
      repostCountGreaterThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'repostCount',
        value: value,
      ));
    });
  }

  QueryBuilder<NoteCountModelIsar, NoteCountModelIsar, QAfterFilterCondition>
      repostCountLessThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'repostCount',
        value: value,
      ));
    });
  }

  QueryBuilder<NoteCountModelIsar, NoteCountModelIsar, QAfterFilterCondition>
      repostCountBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'repostCount',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<NoteCountModelIsar, NoteCountModelIsar, QAfterFilterCondition>
      updatedAtEqualTo(DateTime value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'updatedAt',
        value: value,
      ));
    });
  }

  QueryBuilder<NoteCountModelIsar, NoteCountModelIsar, QAfterFilterCondition>
      updatedAtGreaterThan(
    DateTime value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'updatedAt',
        value: value,
      ));
    });
  }

  QueryBuilder<NoteCountModelIsar, NoteCountModelIsar, QAfterFilterCondition>
      updatedAtLessThan(
    DateTime value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'updatedAt',
        value: value,
      ));
    });
  }

  QueryBuilder<NoteCountModelIsar, NoteCountModelIsar, QAfterFilterCondition>
      updatedAtBetween(
    DateTime lower,
    DateTime upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'updatedAt',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<NoteCountModelIsar, NoteCountModelIsar, QAfterFilterCondition>
      zapAmountEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'zapAmount',
        value: value,
      ));
    });
  }

  QueryBuilder<NoteCountModelIsar, NoteCountModelIsar, QAfterFilterCondition>
      zapAmountGreaterThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'zapAmount',
        value: value,
      ));
    });
  }

  QueryBuilder<NoteCountModelIsar, NoteCountModelIsar, QAfterFilterCondition>
      zapAmountLessThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'zapAmount',
        value: value,
      ));
    });
  }

  QueryBuilder<NoteCountModelIsar, NoteCountModelIsar, QAfterFilterCondition>
      zapAmountBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'zapAmount',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }
}

extension NoteCountModelIsarQueryObject
    on QueryBuilder<NoteCountModelIsar, NoteCountModelIsar, QFilterCondition> {}

extension NoteCountModelIsarQueryLinks
    on QueryBuilder<NoteCountModelIsar, NoteCountModelIsar, QFilterCondition> {}

extension NoteCountModelIsarQuerySortBy
    on QueryBuilder<NoteCountModelIsar, NoteCountModelIsar, QSortBy> {
  QueryBuilder<NoteCountModelIsar, NoteCountModelIsar, QAfterSortBy>
      sortByCachedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'cachedAt', Sort.asc);
    });
  }

  QueryBuilder<NoteCountModelIsar, NoteCountModelIsar, QAfterSortBy>
      sortByCachedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'cachedAt', Sort.desc);
    });
  }

  QueryBuilder<NoteCountModelIsar, NoteCountModelIsar, QAfterSortBy>
      sortByNoteId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'noteId', Sort.asc);
    });
  }

  QueryBuilder<NoteCountModelIsar, NoteCountModelIsar, QAfterSortBy>
      sortByNoteIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'noteId', Sort.desc);
    });
  }

  QueryBuilder<NoteCountModelIsar, NoteCountModelIsar, QAfterSortBy>
      sortByReactionCount() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'reactionCount', Sort.asc);
    });
  }

  QueryBuilder<NoteCountModelIsar, NoteCountModelIsar, QAfterSortBy>
      sortByReactionCountDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'reactionCount', Sort.desc);
    });
  }

  QueryBuilder<NoteCountModelIsar, NoteCountModelIsar, QAfterSortBy>
      sortByReplyCount() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'replyCount', Sort.asc);
    });
  }

  QueryBuilder<NoteCountModelIsar, NoteCountModelIsar, QAfterSortBy>
      sortByReplyCountDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'replyCount', Sort.desc);
    });
  }

  QueryBuilder<NoteCountModelIsar, NoteCountModelIsar, QAfterSortBy>
      sortByRepostCount() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'repostCount', Sort.asc);
    });
  }

  QueryBuilder<NoteCountModelIsar, NoteCountModelIsar, QAfterSortBy>
      sortByRepostCountDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'repostCount', Sort.desc);
    });
  }

  QueryBuilder<NoteCountModelIsar, NoteCountModelIsar, QAfterSortBy>
      sortByUpdatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updatedAt', Sort.asc);
    });
  }

  QueryBuilder<NoteCountModelIsar, NoteCountModelIsar, QAfterSortBy>
      sortByUpdatedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updatedAt', Sort.desc);
    });
  }

  QueryBuilder<NoteCountModelIsar, NoteCountModelIsar, QAfterSortBy>
      sortByZapAmount() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'zapAmount', Sort.asc);
    });
  }

  QueryBuilder<NoteCountModelIsar, NoteCountModelIsar, QAfterSortBy>
      sortByZapAmountDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'zapAmount', Sort.desc);
    });
  }
}

extension NoteCountModelIsarQuerySortThenBy
    on QueryBuilder<NoteCountModelIsar, NoteCountModelIsar, QSortThenBy> {
  QueryBuilder<NoteCountModelIsar, NoteCountModelIsar, QAfterSortBy>
      thenByCachedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'cachedAt', Sort.asc);
    });
  }

  QueryBuilder<NoteCountModelIsar, NoteCountModelIsar, QAfterSortBy>
      thenByCachedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'cachedAt', Sort.desc);
    });
  }

  QueryBuilder<NoteCountModelIsar, NoteCountModelIsar, QAfterSortBy>
      thenById() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.asc);
    });
  }

  QueryBuilder<NoteCountModelIsar, NoteCountModelIsar, QAfterSortBy>
      thenByIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.desc);
    });
  }

  QueryBuilder<NoteCountModelIsar, NoteCountModelIsar, QAfterSortBy>
      thenByNoteId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'noteId', Sort.asc);
    });
  }

  QueryBuilder<NoteCountModelIsar, NoteCountModelIsar, QAfterSortBy>
      thenByNoteIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'noteId', Sort.desc);
    });
  }

  QueryBuilder<NoteCountModelIsar, NoteCountModelIsar, QAfterSortBy>
      thenByReactionCount() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'reactionCount', Sort.asc);
    });
  }

  QueryBuilder<NoteCountModelIsar, NoteCountModelIsar, QAfterSortBy>
      thenByReactionCountDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'reactionCount', Sort.desc);
    });
  }

  QueryBuilder<NoteCountModelIsar, NoteCountModelIsar, QAfterSortBy>
      thenByReplyCount() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'replyCount', Sort.asc);
    });
  }

  QueryBuilder<NoteCountModelIsar, NoteCountModelIsar, QAfterSortBy>
      thenByReplyCountDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'replyCount', Sort.desc);
    });
  }

  QueryBuilder<NoteCountModelIsar, NoteCountModelIsar, QAfterSortBy>
      thenByRepostCount() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'repostCount', Sort.asc);
    });
  }

  QueryBuilder<NoteCountModelIsar, NoteCountModelIsar, QAfterSortBy>
      thenByRepostCountDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'repostCount', Sort.desc);
    });
  }

  QueryBuilder<NoteCountModelIsar, NoteCountModelIsar, QAfterSortBy>
      thenByUpdatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updatedAt', Sort.asc);
    });
  }

  QueryBuilder<NoteCountModelIsar, NoteCountModelIsar, QAfterSortBy>
      thenByUpdatedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updatedAt', Sort.desc);
    });
  }

  QueryBuilder<NoteCountModelIsar, NoteCountModelIsar, QAfterSortBy>
      thenByZapAmount() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'zapAmount', Sort.asc);
    });
  }

  QueryBuilder<NoteCountModelIsar, NoteCountModelIsar, QAfterSortBy>
      thenByZapAmountDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'zapAmount', Sort.desc);
    });
  }
}

extension NoteCountModelIsarQueryWhereDistinct
    on QueryBuilder<NoteCountModelIsar, NoteCountModelIsar, QDistinct> {
  QueryBuilder<NoteCountModelIsar, NoteCountModelIsar, QDistinct>
      distinctByCachedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'cachedAt');
    });
  }

  QueryBuilder<NoteCountModelIsar, NoteCountModelIsar, QDistinct>
      distinctByNoteId({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'noteId', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<NoteCountModelIsar, NoteCountModelIsar, QDistinct>
      distinctByReactionCount() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'reactionCount');
    });
  }

  QueryBuilder<NoteCountModelIsar, NoteCountModelIsar, QDistinct>
      distinctByReplyCount() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'replyCount');
    });
  }

  QueryBuilder<NoteCountModelIsar, NoteCountModelIsar, QDistinct>
      distinctByRepostCount() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'repostCount');
    });
  }

  QueryBuilder<NoteCountModelIsar, NoteCountModelIsar, QDistinct>
      distinctByUpdatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'updatedAt');
    });
  }

  QueryBuilder<NoteCountModelIsar, NoteCountModelIsar, QDistinct>
      distinctByZapAmount() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'zapAmount');
    });
  }
}

extension NoteCountModelIsarQueryProperty
    on QueryBuilder<NoteCountModelIsar, NoteCountModelIsar, QQueryProperty> {
  QueryBuilder<NoteCountModelIsar, int, QQueryOperations> idProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'id');
    });
  }

  QueryBuilder<NoteCountModelIsar, DateTime, QQueryOperations>
      cachedAtProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'cachedAt');
    });
  }

  QueryBuilder<NoteCountModelIsar, String, QQueryOperations> noteIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'noteId');
    });
  }

  QueryBuilder<NoteCountModelIsar, int, QQueryOperations>
      reactionCountProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'reactionCount');
    });
  }

  QueryBuilder<NoteCountModelIsar, int, QQueryOperations> replyCountProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'replyCount');
    });
  }

  QueryBuilder<NoteCountModelIsar, int, QQueryOperations>
      repostCountProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'repostCount');
    });
  }

  QueryBuilder<NoteCountModelIsar, DateTime, QQueryOperations>
      updatedAtProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'updatedAt');
    });
  }

  QueryBuilder<NoteCountModelIsar, int, QQueryOperations> zapAmountProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'zapAmount');
    });
  }
}
