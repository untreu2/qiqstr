// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'mute_model_isar.dart';

// **************************************************************************
// IsarCollectionGenerator
// **************************************************************************

// coverage:ignore-file
// ignore_for_file: duplicate_ignore, non_constant_identifier_names, constant_identifier_names, invalid_use_of_protected_member, unnecessary_cast, prefer_const_constructors, lines_longer_than_80_chars, require_trailing_commas, inference_failure_on_function_invocation, unnecessary_parenthesis, unnecessary_raw_strings, unnecessary_null_checks, join_return_with_assignment, prefer_final_locals, avoid_js_rounded_ints, avoid_positional_boolean_parameters, always_specify_types

extension GetMuteModelIsarCollection on Isar {
  IsarCollection<MuteModelIsar> get muteModelIsars => this.collection();
}

const MuteModelIsarSchema = CollectionSchema(
  name: r'MuteModelIsar',
  id: -712695253317615430,
  properties: {
    r'cachedAt': PropertySchema(
      id: 0,
      name: r'cachedAt',
      type: IsarType.dateTime,
    ),
    r'mutedPubkeys': PropertySchema(
      id: 1,
      name: r'mutedPubkeys',
      type: IsarType.stringList,
    ),
    r'updatedAt': PropertySchema(
      id: 2,
      name: r'updatedAt',
      type: IsarType.dateTime,
    ),
    r'userPubkeyHex': PropertySchema(
      id: 3,
      name: r'userPubkeyHex',
      type: IsarType.string,
    )
  },
  estimateSize: _muteModelIsarEstimateSize,
  serialize: _muteModelIsarSerialize,
  deserialize: _muteModelIsarDeserialize,
  deserializeProp: _muteModelIsarDeserializeProp,
  idName: r'id',
  indexes: {
    r'userPubkeyHex': IndexSchema(
      id: -2519041683017558653,
      name: r'userPubkeyHex',
      unique: true,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'userPubkeyHex',
          type: IndexType.hash,
          caseSensitive: true,
        )
      ],
    )
  },
  links: {},
  embeddedSchemas: {},
  getId: _muteModelIsarGetId,
  getLinks: _muteModelIsarGetLinks,
  attach: _muteModelIsarAttach,
  version: '3.1.0+1',
);

int _muteModelIsarEstimateSize(
  MuteModelIsar object,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  var bytesCount = offsets.last;
  bytesCount += 3 + object.mutedPubkeys.length * 3;
  {
    for (var i = 0; i < object.mutedPubkeys.length; i++) {
      final value = object.mutedPubkeys[i];
      bytesCount += value.length * 3;
    }
  }
  bytesCount += 3 + object.userPubkeyHex.length * 3;
  return bytesCount;
}

void _muteModelIsarSerialize(
  MuteModelIsar object,
  IsarWriter writer,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  writer.writeDateTime(offsets[0], object.cachedAt);
  writer.writeStringList(offsets[1], object.mutedPubkeys);
  writer.writeDateTime(offsets[2], object.updatedAt);
  writer.writeString(offsets[3], object.userPubkeyHex);
}

MuteModelIsar _muteModelIsarDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = MuteModelIsar();
  object.cachedAt = reader.readDateTime(offsets[0]);
  object.id = id;
  object.mutedPubkeys = reader.readStringList(offsets[1]) ?? [];
  object.updatedAt = reader.readDateTime(offsets[2]);
  object.userPubkeyHex = reader.readString(offsets[3]);
  return object;
}

P _muteModelIsarDeserializeProp<P>(
  IsarReader reader,
  int propertyId,
  int offset,
  Map<Type, List<int>> allOffsets,
) {
  switch (propertyId) {
    case 0:
      return (reader.readDateTime(offset)) as P;
    case 1:
      return (reader.readStringList(offset) ?? []) as P;
    case 2:
      return (reader.readDateTime(offset)) as P;
    case 3:
      return (reader.readString(offset)) as P;
    default:
      throw IsarError('Unknown property with id $propertyId');
  }
}

Id _muteModelIsarGetId(MuteModelIsar object) {
  return object.id;
}

List<IsarLinkBase<dynamic>> _muteModelIsarGetLinks(MuteModelIsar object) {
  return [];
}

void _muteModelIsarAttach(
    IsarCollection<dynamic> col, Id id, MuteModelIsar object) {
  object.id = id;
}

extension MuteModelIsarByIndex on IsarCollection<MuteModelIsar> {
  Future<MuteModelIsar?> getByUserPubkeyHex(String userPubkeyHex) {
    return getByIndex(r'userPubkeyHex', [userPubkeyHex]);
  }

  MuteModelIsar? getByUserPubkeyHexSync(String userPubkeyHex) {
    return getByIndexSync(r'userPubkeyHex', [userPubkeyHex]);
  }

  Future<bool> deleteByUserPubkeyHex(String userPubkeyHex) {
    return deleteByIndex(r'userPubkeyHex', [userPubkeyHex]);
  }

  bool deleteByUserPubkeyHexSync(String userPubkeyHex) {
    return deleteByIndexSync(r'userPubkeyHex', [userPubkeyHex]);
  }

  Future<List<MuteModelIsar?>> getAllByUserPubkeyHex(
      List<String> userPubkeyHexValues) {
    final values = userPubkeyHexValues.map((e) => [e]).toList();
    return getAllByIndex(r'userPubkeyHex', values);
  }

  List<MuteModelIsar?> getAllByUserPubkeyHexSync(
      List<String> userPubkeyHexValues) {
    final values = userPubkeyHexValues.map((e) => [e]).toList();
    return getAllByIndexSync(r'userPubkeyHex', values);
  }

  Future<int> deleteAllByUserPubkeyHex(List<String> userPubkeyHexValues) {
    final values = userPubkeyHexValues.map((e) => [e]).toList();
    return deleteAllByIndex(r'userPubkeyHex', values);
  }

  int deleteAllByUserPubkeyHexSync(List<String> userPubkeyHexValues) {
    final values = userPubkeyHexValues.map((e) => [e]).toList();
    return deleteAllByIndexSync(r'userPubkeyHex', values);
  }

  Future<Id> putByUserPubkeyHex(MuteModelIsar object) {
    return putByIndex(r'userPubkeyHex', object);
  }

  Id putByUserPubkeyHexSync(MuteModelIsar object, {bool saveLinks = true}) {
    return putByIndexSync(r'userPubkeyHex', object, saveLinks: saveLinks);
  }

  Future<List<Id>> putAllByUserPubkeyHex(List<MuteModelIsar> objects) {
    return putAllByIndex(r'userPubkeyHex', objects);
  }

  List<Id> putAllByUserPubkeyHexSync(List<MuteModelIsar> objects,
      {bool saveLinks = true}) {
    return putAllByIndexSync(r'userPubkeyHex', objects, saveLinks: saveLinks);
  }
}

extension MuteModelIsarQueryWhereSort
    on QueryBuilder<MuteModelIsar, MuteModelIsar, QWhere> {
  QueryBuilder<MuteModelIsar, MuteModelIsar, QAfterWhere> anyId() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(const IdWhereClause.any());
    });
  }
}

extension MuteModelIsarQueryWhere
    on QueryBuilder<MuteModelIsar, MuteModelIsar, QWhereClause> {
  QueryBuilder<MuteModelIsar, MuteModelIsar, QAfterWhereClause> idEqualTo(
      Id id) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(
        lower: id,
        upper: id,
      ));
    });
  }

  QueryBuilder<MuteModelIsar, MuteModelIsar, QAfterWhereClause> idNotEqualTo(
      Id id) {
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

  QueryBuilder<MuteModelIsar, MuteModelIsar, QAfterWhereClause> idGreaterThan(
      Id id,
      {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.greaterThan(lower: id, includeLower: include),
      );
    });
  }

  QueryBuilder<MuteModelIsar, MuteModelIsar, QAfterWhereClause> idLessThan(
      Id id,
      {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.lessThan(upper: id, includeUpper: include),
      );
    });
  }

  QueryBuilder<MuteModelIsar, MuteModelIsar, QAfterWhereClause> idBetween(
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

  QueryBuilder<MuteModelIsar, MuteModelIsar, QAfterWhereClause>
      userPubkeyHexEqualTo(String userPubkeyHex) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'userPubkeyHex',
        value: [userPubkeyHex],
      ));
    });
  }

  QueryBuilder<MuteModelIsar, MuteModelIsar, QAfterWhereClause>
      userPubkeyHexNotEqualTo(String userPubkeyHex) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'userPubkeyHex',
              lower: [],
              upper: [userPubkeyHex],
              includeUpper: false,
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'userPubkeyHex',
              lower: [userPubkeyHex],
              includeLower: false,
              upper: [],
            ));
      } else {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'userPubkeyHex',
              lower: [userPubkeyHex],
              includeLower: false,
              upper: [],
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'userPubkeyHex',
              lower: [],
              upper: [userPubkeyHex],
              includeUpper: false,
            ));
      }
    });
  }
}

extension MuteModelIsarQueryFilter
    on QueryBuilder<MuteModelIsar, MuteModelIsar, QFilterCondition> {
  QueryBuilder<MuteModelIsar, MuteModelIsar, QAfterFilterCondition>
      cachedAtEqualTo(DateTime value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'cachedAt',
        value: value,
      ));
    });
  }

  QueryBuilder<MuteModelIsar, MuteModelIsar, QAfterFilterCondition>
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

  QueryBuilder<MuteModelIsar, MuteModelIsar, QAfterFilterCondition>
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

  QueryBuilder<MuteModelIsar, MuteModelIsar, QAfterFilterCondition>
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

  QueryBuilder<MuteModelIsar, MuteModelIsar, QAfterFilterCondition> idEqualTo(
      Id value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<MuteModelIsar, MuteModelIsar, QAfterFilterCondition>
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

  QueryBuilder<MuteModelIsar, MuteModelIsar, QAfterFilterCondition> idLessThan(
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

  QueryBuilder<MuteModelIsar, MuteModelIsar, QAfterFilterCondition> idBetween(
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

  QueryBuilder<MuteModelIsar, MuteModelIsar, QAfterFilterCondition>
      mutedPubkeysElementEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'mutedPubkeys',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MuteModelIsar, MuteModelIsar, QAfterFilterCondition>
      mutedPubkeysElementGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'mutedPubkeys',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MuteModelIsar, MuteModelIsar, QAfterFilterCondition>
      mutedPubkeysElementLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'mutedPubkeys',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MuteModelIsar, MuteModelIsar, QAfterFilterCondition>
      mutedPubkeysElementBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'mutedPubkeys',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MuteModelIsar, MuteModelIsar, QAfterFilterCondition>
      mutedPubkeysElementStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'mutedPubkeys',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MuteModelIsar, MuteModelIsar, QAfterFilterCondition>
      mutedPubkeysElementEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'mutedPubkeys',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MuteModelIsar, MuteModelIsar, QAfterFilterCondition>
      mutedPubkeysElementContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'mutedPubkeys',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MuteModelIsar, MuteModelIsar, QAfterFilterCondition>
      mutedPubkeysElementMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'mutedPubkeys',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MuteModelIsar, MuteModelIsar, QAfterFilterCondition>
      mutedPubkeysElementIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'mutedPubkeys',
        value: '',
      ));
    });
  }

  QueryBuilder<MuteModelIsar, MuteModelIsar, QAfterFilterCondition>
      mutedPubkeysElementIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'mutedPubkeys',
        value: '',
      ));
    });
  }

  QueryBuilder<MuteModelIsar, MuteModelIsar, QAfterFilterCondition>
      mutedPubkeysLengthEqualTo(int length) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'mutedPubkeys',
        length,
        true,
        length,
        true,
      );
    });
  }

  QueryBuilder<MuteModelIsar, MuteModelIsar, QAfterFilterCondition>
      mutedPubkeysIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'mutedPubkeys',
        0,
        true,
        0,
        true,
      );
    });
  }

  QueryBuilder<MuteModelIsar, MuteModelIsar, QAfterFilterCondition>
      mutedPubkeysIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'mutedPubkeys',
        0,
        false,
        999999,
        true,
      );
    });
  }

  QueryBuilder<MuteModelIsar, MuteModelIsar, QAfterFilterCondition>
      mutedPubkeysLengthLessThan(
    int length, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'mutedPubkeys',
        0,
        true,
        length,
        include,
      );
    });
  }

  QueryBuilder<MuteModelIsar, MuteModelIsar, QAfterFilterCondition>
      mutedPubkeysLengthGreaterThan(
    int length, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'mutedPubkeys',
        length,
        include,
        999999,
        true,
      );
    });
  }

  QueryBuilder<MuteModelIsar, MuteModelIsar, QAfterFilterCondition>
      mutedPubkeysLengthBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'mutedPubkeys',
        lower,
        includeLower,
        upper,
        includeUpper,
      );
    });
  }

  QueryBuilder<MuteModelIsar, MuteModelIsar, QAfterFilterCondition>
      updatedAtEqualTo(DateTime value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'updatedAt',
        value: value,
      ));
    });
  }

  QueryBuilder<MuteModelIsar, MuteModelIsar, QAfterFilterCondition>
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

  QueryBuilder<MuteModelIsar, MuteModelIsar, QAfterFilterCondition>
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

  QueryBuilder<MuteModelIsar, MuteModelIsar, QAfterFilterCondition>
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

  QueryBuilder<MuteModelIsar, MuteModelIsar, QAfterFilterCondition>
      userPubkeyHexEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'userPubkeyHex',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MuteModelIsar, MuteModelIsar, QAfterFilterCondition>
      userPubkeyHexGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'userPubkeyHex',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MuteModelIsar, MuteModelIsar, QAfterFilterCondition>
      userPubkeyHexLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'userPubkeyHex',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MuteModelIsar, MuteModelIsar, QAfterFilterCondition>
      userPubkeyHexBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'userPubkeyHex',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MuteModelIsar, MuteModelIsar, QAfterFilterCondition>
      userPubkeyHexStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'userPubkeyHex',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MuteModelIsar, MuteModelIsar, QAfterFilterCondition>
      userPubkeyHexEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'userPubkeyHex',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MuteModelIsar, MuteModelIsar, QAfterFilterCondition>
      userPubkeyHexContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'userPubkeyHex',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MuteModelIsar, MuteModelIsar, QAfterFilterCondition>
      userPubkeyHexMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'userPubkeyHex',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MuteModelIsar, MuteModelIsar, QAfterFilterCondition>
      userPubkeyHexIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'userPubkeyHex',
        value: '',
      ));
    });
  }

  QueryBuilder<MuteModelIsar, MuteModelIsar, QAfterFilterCondition>
      userPubkeyHexIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'userPubkeyHex',
        value: '',
      ));
    });
  }
}

extension MuteModelIsarQueryObject
    on QueryBuilder<MuteModelIsar, MuteModelIsar, QFilterCondition> {}

extension MuteModelIsarQueryLinks
    on QueryBuilder<MuteModelIsar, MuteModelIsar, QFilterCondition> {}

extension MuteModelIsarQuerySortBy
    on QueryBuilder<MuteModelIsar, MuteModelIsar, QSortBy> {
  QueryBuilder<MuteModelIsar, MuteModelIsar, QAfterSortBy> sortByCachedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'cachedAt', Sort.asc);
    });
  }

  QueryBuilder<MuteModelIsar, MuteModelIsar, QAfterSortBy>
      sortByCachedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'cachedAt', Sort.desc);
    });
  }

  QueryBuilder<MuteModelIsar, MuteModelIsar, QAfterSortBy> sortByUpdatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updatedAt', Sort.asc);
    });
  }

  QueryBuilder<MuteModelIsar, MuteModelIsar, QAfterSortBy>
      sortByUpdatedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updatedAt', Sort.desc);
    });
  }

  QueryBuilder<MuteModelIsar, MuteModelIsar, QAfterSortBy>
      sortByUserPubkeyHex() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'userPubkeyHex', Sort.asc);
    });
  }

  QueryBuilder<MuteModelIsar, MuteModelIsar, QAfterSortBy>
      sortByUserPubkeyHexDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'userPubkeyHex', Sort.desc);
    });
  }
}

extension MuteModelIsarQuerySortThenBy
    on QueryBuilder<MuteModelIsar, MuteModelIsar, QSortThenBy> {
  QueryBuilder<MuteModelIsar, MuteModelIsar, QAfterSortBy> thenByCachedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'cachedAt', Sort.asc);
    });
  }

  QueryBuilder<MuteModelIsar, MuteModelIsar, QAfterSortBy>
      thenByCachedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'cachedAt', Sort.desc);
    });
  }

  QueryBuilder<MuteModelIsar, MuteModelIsar, QAfterSortBy> thenById() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.asc);
    });
  }

  QueryBuilder<MuteModelIsar, MuteModelIsar, QAfterSortBy> thenByIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.desc);
    });
  }

  QueryBuilder<MuteModelIsar, MuteModelIsar, QAfterSortBy> thenByUpdatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updatedAt', Sort.asc);
    });
  }

  QueryBuilder<MuteModelIsar, MuteModelIsar, QAfterSortBy>
      thenByUpdatedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updatedAt', Sort.desc);
    });
  }

  QueryBuilder<MuteModelIsar, MuteModelIsar, QAfterSortBy>
      thenByUserPubkeyHex() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'userPubkeyHex', Sort.asc);
    });
  }

  QueryBuilder<MuteModelIsar, MuteModelIsar, QAfterSortBy>
      thenByUserPubkeyHexDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'userPubkeyHex', Sort.desc);
    });
  }
}

extension MuteModelIsarQueryWhereDistinct
    on QueryBuilder<MuteModelIsar, MuteModelIsar, QDistinct> {
  QueryBuilder<MuteModelIsar, MuteModelIsar, QDistinct> distinctByCachedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'cachedAt');
    });
  }

  QueryBuilder<MuteModelIsar, MuteModelIsar, QDistinct>
      distinctByMutedPubkeys() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'mutedPubkeys');
    });
  }

  QueryBuilder<MuteModelIsar, MuteModelIsar, QDistinct> distinctByUpdatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'updatedAt');
    });
  }

  QueryBuilder<MuteModelIsar, MuteModelIsar, QDistinct> distinctByUserPubkeyHex(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'userPubkeyHex',
          caseSensitive: caseSensitive);
    });
  }
}

extension MuteModelIsarQueryProperty
    on QueryBuilder<MuteModelIsar, MuteModelIsar, QQueryProperty> {
  QueryBuilder<MuteModelIsar, int, QQueryOperations> idProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'id');
    });
  }

  QueryBuilder<MuteModelIsar, DateTime, QQueryOperations> cachedAtProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'cachedAt');
    });
  }

  QueryBuilder<MuteModelIsar, List<String>, QQueryOperations>
      mutedPubkeysProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'mutedPubkeys');
    });
  }

  QueryBuilder<MuteModelIsar, DateTime, QQueryOperations> updatedAtProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'updatedAt');
    });
  }

  QueryBuilder<MuteModelIsar, String, QQueryOperations>
      userPubkeyHexProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'userPubkeyHex');
    });
  }
}
