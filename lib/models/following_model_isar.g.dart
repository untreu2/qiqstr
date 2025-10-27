// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'following_model_isar.dart';

// **************************************************************************
// IsarCollectionGenerator
// **************************************************************************

// coverage:ignore-file
// ignore_for_file: duplicate_ignore, non_constant_identifier_names, constant_identifier_names, invalid_use_of_protected_member, unnecessary_cast, prefer_const_constructors, lines_longer_than_80_chars, require_trailing_commas, inference_failure_on_function_invocation, unnecessary_parenthesis, unnecessary_raw_strings, unnecessary_null_checks, join_return_with_assignment, prefer_final_locals, avoid_js_rounded_ints, avoid_positional_boolean_parameters, always_specify_types

extension GetFollowingModelIsarCollection on Isar {
  IsarCollection<FollowingModelIsar> get followingModelIsars =>
      this.collection();
}

const FollowingModelIsarSchema = CollectionSchema(
  name: r'FollowingModelIsar',
  id: -1092012351052453835,
  properties: {
    r'cachedAt': PropertySchema(
      id: 0,
      name: r'cachedAt',
      type: IsarType.dateTime,
    ),
    r'followingPubkeys': PropertySchema(
      id: 1,
      name: r'followingPubkeys',
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
  estimateSize: _followingModelIsarEstimateSize,
  serialize: _followingModelIsarSerialize,
  deserialize: _followingModelIsarDeserialize,
  deserializeProp: _followingModelIsarDeserializeProp,
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
  getId: _followingModelIsarGetId,
  getLinks: _followingModelIsarGetLinks,
  attach: _followingModelIsarAttach,
  version: '3.1.0+1',
);

int _followingModelIsarEstimateSize(
  FollowingModelIsar object,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  var bytesCount = offsets.last;
  bytesCount += 3 + object.followingPubkeys.length * 3;
  {
    for (var i = 0; i < object.followingPubkeys.length; i++) {
      final value = object.followingPubkeys[i];
      bytesCount += value.length * 3;
    }
  }
  bytesCount += 3 + object.userPubkeyHex.length * 3;
  return bytesCount;
}

void _followingModelIsarSerialize(
  FollowingModelIsar object,
  IsarWriter writer,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  writer.writeDateTime(offsets[0], object.cachedAt);
  writer.writeStringList(offsets[1], object.followingPubkeys);
  writer.writeDateTime(offsets[2], object.updatedAt);
  writer.writeString(offsets[3], object.userPubkeyHex);
}

FollowingModelIsar _followingModelIsarDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = FollowingModelIsar();
  object.cachedAt = reader.readDateTime(offsets[0]);
  object.followingPubkeys = reader.readStringList(offsets[1]) ?? [];
  object.id = id;
  object.updatedAt = reader.readDateTime(offsets[2]);
  object.userPubkeyHex = reader.readString(offsets[3]);
  return object;
}

P _followingModelIsarDeserializeProp<P>(
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

Id _followingModelIsarGetId(FollowingModelIsar object) {
  return object.id;
}

List<IsarLinkBase<dynamic>> _followingModelIsarGetLinks(
    FollowingModelIsar object) {
  return [];
}

void _followingModelIsarAttach(
    IsarCollection<dynamic> col, Id id, FollowingModelIsar object) {
  object.id = id;
}

extension FollowingModelIsarByIndex on IsarCollection<FollowingModelIsar> {
  Future<FollowingModelIsar?> getByUserPubkeyHex(String userPubkeyHex) {
    return getByIndex(r'userPubkeyHex', [userPubkeyHex]);
  }

  FollowingModelIsar? getByUserPubkeyHexSync(String userPubkeyHex) {
    return getByIndexSync(r'userPubkeyHex', [userPubkeyHex]);
  }

  Future<bool> deleteByUserPubkeyHex(String userPubkeyHex) {
    return deleteByIndex(r'userPubkeyHex', [userPubkeyHex]);
  }

  bool deleteByUserPubkeyHexSync(String userPubkeyHex) {
    return deleteByIndexSync(r'userPubkeyHex', [userPubkeyHex]);
  }

  Future<List<FollowingModelIsar?>> getAllByUserPubkeyHex(
      List<String> userPubkeyHexValues) {
    final values = userPubkeyHexValues.map((e) => [e]).toList();
    return getAllByIndex(r'userPubkeyHex', values);
  }

  List<FollowingModelIsar?> getAllByUserPubkeyHexSync(
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

  Future<Id> putByUserPubkeyHex(FollowingModelIsar object) {
    return putByIndex(r'userPubkeyHex', object);
  }

  Id putByUserPubkeyHexSync(FollowingModelIsar object,
      {bool saveLinks = true}) {
    return putByIndexSync(r'userPubkeyHex', object, saveLinks: saveLinks);
  }

  Future<List<Id>> putAllByUserPubkeyHex(List<FollowingModelIsar> objects) {
    return putAllByIndex(r'userPubkeyHex', objects);
  }

  List<Id> putAllByUserPubkeyHexSync(List<FollowingModelIsar> objects,
      {bool saveLinks = true}) {
    return putAllByIndexSync(r'userPubkeyHex', objects, saveLinks: saveLinks);
  }
}

extension FollowingModelIsarQueryWhereSort
    on QueryBuilder<FollowingModelIsar, FollowingModelIsar, QWhere> {
  QueryBuilder<FollowingModelIsar, FollowingModelIsar, QAfterWhere> anyId() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(const IdWhereClause.any());
    });
  }
}

extension FollowingModelIsarQueryWhere
    on QueryBuilder<FollowingModelIsar, FollowingModelIsar, QWhereClause> {
  QueryBuilder<FollowingModelIsar, FollowingModelIsar, QAfterWhereClause>
      idEqualTo(Id id) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(
        lower: id,
        upper: id,
      ));
    });
  }

  QueryBuilder<FollowingModelIsar, FollowingModelIsar, QAfterWhereClause>
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

  QueryBuilder<FollowingModelIsar, FollowingModelIsar, QAfterWhereClause>
      idGreaterThan(Id id, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.greaterThan(lower: id, includeLower: include),
      );
    });
  }

  QueryBuilder<FollowingModelIsar, FollowingModelIsar, QAfterWhereClause>
      idLessThan(Id id, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.lessThan(upper: id, includeUpper: include),
      );
    });
  }

  QueryBuilder<FollowingModelIsar, FollowingModelIsar, QAfterWhereClause>
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

  QueryBuilder<FollowingModelIsar, FollowingModelIsar, QAfterWhereClause>
      userPubkeyHexEqualTo(String userPubkeyHex) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'userPubkeyHex',
        value: [userPubkeyHex],
      ));
    });
  }

  QueryBuilder<FollowingModelIsar, FollowingModelIsar, QAfterWhereClause>
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

extension FollowingModelIsarQueryFilter
    on QueryBuilder<FollowingModelIsar, FollowingModelIsar, QFilterCondition> {
  QueryBuilder<FollowingModelIsar, FollowingModelIsar, QAfterFilterCondition>
      cachedAtEqualTo(DateTime value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'cachedAt',
        value: value,
      ));
    });
  }

  QueryBuilder<FollowingModelIsar, FollowingModelIsar, QAfterFilterCondition>
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

  QueryBuilder<FollowingModelIsar, FollowingModelIsar, QAfterFilterCondition>
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

  QueryBuilder<FollowingModelIsar, FollowingModelIsar, QAfterFilterCondition>
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

  QueryBuilder<FollowingModelIsar, FollowingModelIsar, QAfterFilterCondition>
      followingPubkeysElementEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'followingPubkeys',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<FollowingModelIsar, FollowingModelIsar, QAfterFilterCondition>
      followingPubkeysElementGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'followingPubkeys',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<FollowingModelIsar, FollowingModelIsar, QAfterFilterCondition>
      followingPubkeysElementLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'followingPubkeys',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<FollowingModelIsar, FollowingModelIsar, QAfterFilterCondition>
      followingPubkeysElementBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'followingPubkeys',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<FollowingModelIsar, FollowingModelIsar, QAfterFilterCondition>
      followingPubkeysElementStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'followingPubkeys',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<FollowingModelIsar, FollowingModelIsar, QAfterFilterCondition>
      followingPubkeysElementEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'followingPubkeys',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<FollowingModelIsar, FollowingModelIsar, QAfterFilterCondition>
      followingPubkeysElementContains(String value,
          {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'followingPubkeys',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<FollowingModelIsar, FollowingModelIsar, QAfterFilterCondition>
      followingPubkeysElementMatches(String pattern,
          {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'followingPubkeys',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<FollowingModelIsar, FollowingModelIsar, QAfterFilterCondition>
      followingPubkeysElementIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'followingPubkeys',
        value: '',
      ));
    });
  }

  QueryBuilder<FollowingModelIsar, FollowingModelIsar, QAfterFilterCondition>
      followingPubkeysElementIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'followingPubkeys',
        value: '',
      ));
    });
  }

  QueryBuilder<FollowingModelIsar, FollowingModelIsar, QAfterFilterCondition>
      followingPubkeysLengthEqualTo(int length) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'followingPubkeys',
        length,
        true,
        length,
        true,
      );
    });
  }

  QueryBuilder<FollowingModelIsar, FollowingModelIsar, QAfterFilterCondition>
      followingPubkeysIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'followingPubkeys',
        0,
        true,
        0,
        true,
      );
    });
  }

  QueryBuilder<FollowingModelIsar, FollowingModelIsar, QAfterFilterCondition>
      followingPubkeysIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'followingPubkeys',
        0,
        false,
        999999,
        true,
      );
    });
  }

  QueryBuilder<FollowingModelIsar, FollowingModelIsar, QAfterFilterCondition>
      followingPubkeysLengthLessThan(
    int length, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'followingPubkeys',
        0,
        true,
        length,
        include,
      );
    });
  }

  QueryBuilder<FollowingModelIsar, FollowingModelIsar, QAfterFilterCondition>
      followingPubkeysLengthGreaterThan(
    int length, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'followingPubkeys',
        length,
        include,
        999999,
        true,
      );
    });
  }

  QueryBuilder<FollowingModelIsar, FollowingModelIsar, QAfterFilterCondition>
      followingPubkeysLengthBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'followingPubkeys',
        lower,
        includeLower,
        upper,
        includeUpper,
      );
    });
  }

  QueryBuilder<FollowingModelIsar, FollowingModelIsar, QAfterFilterCondition>
      idEqualTo(Id value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<FollowingModelIsar, FollowingModelIsar, QAfterFilterCondition>
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

  QueryBuilder<FollowingModelIsar, FollowingModelIsar, QAfterFilterCondition>
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

  QueryBuilder<FollowingModelIsar, FollowingModelIsar, QAfterFilterCondition>
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

  QueryBuilder<FollowingModelIsar, FollowingModelIsar, QAfterFilterCondition>
      updatedAtEqualTo(DateTime value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'updatedAt',
        value: value,
      ));
    });
  }

  QueryBuilder<FollowingModelIsar, FollowingModelIsar, QAfterFilterCondition>
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

  QueryBuilder<FollowingModelIsar, FollowingModelIsar, QAfterFilterCondition>
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

  QueryBuilder<FollowingModelIsar, FollowingModelIsar, QAfterFilterCondition>
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

  QueryBuilder<FollowingModelIsar, FollowingModelIsar, QAfterFilterCondition>
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

  QueryBuilder<FollowingModelIsar, FollowingModelIsar, QAfterFilterCondition>
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

  QueryBuilder<FollowingModelIsar, FollowingModelIsar, QAfterFilterCondition>
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

  QueryBuilder<FollowingModelIsar, FollowingModelIsar, QAfterFilterCondition>
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

  QueryBuilder<FollowingModelIsar, FollowingModelIsar, QAfterFilterCondition>
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

  QueryBuilder<FollowingModelIsar, FollowingModelIsar, QAfterFilterCondition>
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

  QueryBuilder<FollowingModelIsar, FollowingModelIsar, QAfterFilterCondition>
      userPubkeyHexContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'userPubkeyHex',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<FollowingModelIsar, FollowingModelIsar, QAfterFilterCondition>
      userPubkeyHexMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'userPubkeyHex',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<FollowingModelIsar, FollowingModelIsar, QAfterFilterCondition>
      userPubkeyHexIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'userPubkeyHex',
        value: '',
      ));
    });
  }

  QueryBuilder<FollowingModelIsar, FollowingModelIsar, QAfterFilterCondition>
      userPubkeyHexIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'userPubkeyHex',
        value: '',
      ));
    });
  }
}

extension FollowingModelIsarQueryObject
    on QueryBuilder<FollowingModelIsar, FollowingModelIsar, QFilterCondition> {}

extension FollowingModelIsarQueryLinks
    on QueryBuilder<FollowingModelIsar, FollowingModelIsar, QFilterCondition> {}

extension FollowingModelIsarQuerySortBy
    on QueryBuilder<FollowingModelIsar, FollowingModelIsar, QSortBy> {
  QueryBuilder<FollowingModelIsar, FollowingModelIsar, QAfterSortBy>
      sortByCachedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'cachedAt', Sort.asc);
    });
  }

  QueryBuilder<FollowingModelIsar, FollowingModelIsar, QAfterSortBy>
      sortByCachedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'cachedAt', Sort.desc);
    });
  }

  QueryBuilder<FollowingModelIsar, FollowingModelIsar, QAfterSortBy>
      sortByUpdatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updatedAt', Sort.asc);
    });
  }

  QueryBuilder<FollowingModelIsar, FollowingModelIsar, QAfterSortBy>
      sortByUpdatedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updatedAt', Sort.desc);
    });
  }

  QueryBuilder<FollowingModelIsar, FollowingModelIsar, QAfterSortBy>
      sortByUserPubkeyHex() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'userPubkeyHex', Sort.asc);
    });
  }

  QueryBuilder<FollowingModelIsar, FollowingModelIsar, QAfterSortBy>
      sortByUserPubkeyHexDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'userPubkeyHex', Sort.desc);
    });
  }
}

extension FollowingModelIsarQuerySortThenBy
    on QueryBuilder<FollowingModelIsar, FollowingModelIsar, QSortThenBy> {
  QueryBuilder<FollowingModelIsar, FollowingModelIsar, QAfterSortBy>
      thenByCachedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'cachedAt', Sort.asc);
    });
  }

  QueryBuilder<FollowingModelIsar, FollowingModelIsar, QAfterSortBy>
      thenByCachedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'cachedAt', Sort.desc);
    });
  }

  QueryBuilder<FollowingModelIsar, FollowingModelIsar, QAfterSortBy>
      thenById() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.asc);
    });
  }

  QueryBuilder<FollowingModelIsar, FollowingModelIsar, QAfterSortBy>
      thenByIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.desc);
    });
  }

  QueryBuilder<FollowingModelIsar, FollowingModelIsar, QAfterSortBy>
      thenByUpdatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updatedAt', Sort.asc);
    });
  }

  QueryBuilder<FollowingModelIsar, FollowingModelIsar, QAfterSortBy>
      thenByUpdatedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updatedAt', Sort.desc);
    });
  }

  QueryBuilder<FollowingModelIsar, FollowingModelIsar, QAfterSortBy>
      thenByUserPubkeyHex() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'userPubkeyHex', Sort.asc);
    });
  }

  QueryBuilder<FollowingModelIsar, FollowingModelIsar, QAfterSortBy>
      thenByUserPubkeyHexDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'userPubkeyHex', Sort.desc);
    });
  }
}

extension FollowingModelIsarQueryWhereDistinct
    on QueryBuilder<FollowingModelIsar, FollowingModelIsar, QDistinct> {
  QueryBuilder<FollowingModelIsar, FollowingModelIsar, QDistinct>
      distinctByCachedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'cachedAt');
    });
  }

  QueryBuilder<FollowingModelIsar, FollowingModelIsar, QDistinct>
      distinctByFollowingPubkeys() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'followingPubkeys');
    });
  }

  QueryBuilder<FollowingModelIsar, FollowingModelIsar, QDistinct>
      distinctByUpdatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'updatedAt');
    });
  }

  QueryBuilder<FollowingModelIsar, FollowingModelIsar, QDistinct>
      distinctByUserPubkeyHex({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'userPubkeyHex',
          caseSensitive: caseSensitive);
    });
  }
}

extension FollowingModelIsarQueryProperty
    on QueryBuilder<FollowingModelIsar, FollowingModelIsar, QQueryProperty> {
  QueryBuilder<FollowingModelIsar, int, QQueryOperations> idProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'id');
    });
  }

  QueryBuilder<FollowingModelIsar, DateTime, QQueryOperations>
      cachedAtProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'cachedAt');
    });
  }

  QueryBuilder<FollowingModelIsar, List<String>, QQueryOperations>
      followingPubkeysProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'followingPubkeys');
    });
  }

  QueryBuilder<FollowingModelIsar, DateTime, QQueryOperations>
      updatedAtProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'updatedAt');
    });
  }

  QueryBuilder<FollowingModelIsar, String, QQueryOperations>
      userPubkeyHexProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'userPubkeyHex');
    });
  }
}
