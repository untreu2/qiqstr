// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'following_model.dart';

// **************************************************************************
// IsarCollectionGenerator
// **************************************************************************

// coverage:ignore-file
// ignore_for_file: duplicate_ignore, non_constant_identifier_names, constant_identifier_names, invalid_use_of_protected_member, unnecessary_cast, prefer_const_constructors, lines_longer_than_80_chars, require_trailing_commas, inference_failure_on_function_invocation, unnecessary_parenthesis, unnecessary_raw_strings, unnecessary_null_checks, join_return_with_assignment, prefer_final_locals, avoid_js_rounded_ints, avoid_positional_boolean_parameters, always_specify_types

extension GetFollowingModelCollection on Isar {
  IsarCollection<FollowingModel> get followingModels => this.collection();
}

const FollowingModelSchema = CollectionSchema(
  name: r'FollowingModel',
  id: 4322624184509111460,
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
  estimateSize: _followingModelEstimateSize,
  serialize: _followingModelSerialize,
  deserialize: _followingModelDeserialize,
  deserializeProp: _followingModelDeserializeProp,
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
  getId: _followingModelGetId,
  getLinks: _followingModelGetLinks,
  attach: _followingModelAttach,
  version: '3.1.0+1',
);

int _followingModelEstimateSize(
  FollowingModel object,
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

void _followingModelSerialize(
  FollowingModel object,
  IsarWriter writer,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  writer.writeDateTime(offsets[0], object.cachedAt);
  writer.writeStringList(offsets[1], object.followingPubkeys);
  writer.writeDateTime(offsets[2], object.updatedAt);
  writer.writeString(offsets[3], object.userPubkeyHex);
}

FollowingModel _followingModelDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = FollowingModel();
  object.cachedAt = reader.readDateTime(offsets[0]);
  object.followingPubkeys = reader.readStringList(offsets[1]) ?? [];
  object.id = id;
  object.updatedAt = reader.readDateTime(offsets[2]);
  object.userPubkeyHex = reader.readString(offsets[3]);
  return object;
}

P _followingModelDeserializeProp<P>(
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

Id _followingModelGetId(FollowingModel object) {
  return object.id;
}

List<IsarLinkBase<dynamic>> _followingModelGetLinks(FollowingModel object) {
  return [];
}

void _followingModelAttach(
    IsarCollection<dynamic> col, Id id, FollowingModel object) {
  object.id = id;
}

extension FollowingModelByIndex on IsarCollection<FollowingModel> {
  Future<FollowingModel?> getByUserPubkeyHex(String userPubkeyHex) {
    return getByIndex(r'userPubkeyHex', [userPubkeyHex]);
  }

  FollowingModel? getByUserPubkeyHexSync(String userPubkeyHex) {
    return getByIndexSync(r'userPubkeyHex', [userPubkeyHex]);
  }

  Future<bool> deleteByUserPubkeyHex(String userPubkeyHex) {
    return deleteByIndex(r'userPubkeyHex', [userPubkeyHex]);
  }

  bool deleteByUserPubkeyHexSync(String userPubkeyHex) {
    return deleteByIndexSync(r'userPubkeyHex', [userPubkeyHex]);
  }

  Future<List<FollowingModel?>> getAllByUserPubkeyHex(
      List<String> userPubkeyHexValues) {
    final values = userPubkeyHexValues.map((e) => [e]).toList();
    return getAllByIndex(r'userPubkeyHex', values);
  }

  List<FollowingModel?> getAllByUserPubkeyHexSync(
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

  Future<Id> putByUserPubkeyHex(FollowingModel object) {
    return putByIndex(r'userPubkeyHex', object);
  }

  Id putByUserPubkeyHexSync(FollowingModel object, {bool saveLinks = true}) {
    return putByIndexSync(r'userPubkeyHex', object, saveLinks: saveLinks);
  }

  Future<List<Id>> putAllByUserPubkeyHex(List<FollowingModel> objects) {
    return putAllByIndex(r'userPubkeyHex', objects);
  }

  List<Id> putAllByUserPubkeyHexSync(List<FollowingModel> objects,
      {bool saveLinks = true}) {
    return putAllByIndexSync(r'userPubkeyHex', objects, saveLinks: saveLinks);
  }
}

extension FollowingModelQueryWhereSort
    on QueryBuilder<FollowingModel, FollowingModel, QWhere> {
  QueryBuilder<FollowingModel, FollowingModel, QAfterWhere> anyId() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(const IdWhereClause.any());
    });
  }
}

extension FollowingModelQueryWhere
    on QueryBuilder<FollowingModel, FollowingModel, QWhereClause> {
  QueryBuilder<FollowingModel, FollowingModel, QAfterWhereClause> idEqualTo(
      Id id) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(
        lower: id,
        upper: id,
      ));
    });
  }

  QueryBuilder<FollowingModel, FollowingModel, QAfterWhereClause> idNotEqualTo(
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

  QueryBuilder<FollowingModel, FollowingModel, QAfterWhereClause> idGreaterThan(
      Id id,
      {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.greaterThan(lower: id, includeLower: include),
      );
    });
  }

  QueryBuilder<FollowingModel, FollowingModel, QAfterWhereClause> idLessThan(
      Id id,
      {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.lessThan(upper: id, includeUpper: include),
      );
    });
  }

  QueryBuilder<FollowingModel, FollowingModel, QAfterWhereClause> idBetween(
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

  QueryBuilder<FollowingModel, FollowingModel, QAfterWhereClause>
      userPubkeyHexEqualTo(String userPubkeyHex) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'userPubkeyHex',
        value: [userPubkeyHex],
      ));
    });
  }

  QueryBuilder<FollowingModel, FollowingModel, QAfterWhereClause>
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

extension FollowingModelQueryFilter
    on QueryBuilder<FollowingModel, FollowingModel, QFilterCondition> {
  QueryBuilder<FollowingModel, FollowingModel, QAfterFilterCondition>
      cachedAtEqualTo(DateTime value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'cachedAt',
        value: value,
      ));
    });
  }

  QueryBuilder<FollowingModel, FollowingModel, QAfterFilterCondition>
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

  QueryBuilder<FollowingModel, FollowingModel, QAfterFilterCondition>
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

  QueryBuilder<FollowingModel, FollowingModel, QAfterFilterCondition>
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

  QueryBuilder<FollowingModel, FollowingModel, QAfterFilterCondition>
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

  QueryBuilder<FollowingModel, FollowingModel, QAfterFilterCondition>
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

  QueryBuilder<FollowingModel, FollowingModel, QAfterFilterCondition>
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

  QueryBuilder<FollowingModel, FollowingModel, QAfterFilterCondition>
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

  QueryBuilder<FollowingModel, FollowingModel, QAfterFilterCondition>
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

  QueryBuilder<FollowingModel, FollowingModel, QAfterFilterCondition>
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

  QueryBuilder<FollowingModel, FollowingModel, QAfterFilterCondition>
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

  QueryBuilder<FollowingModel, FollowingModel, QAfterFilterCondition>
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

  QueryBuilder<FollowingModel, FollowingModel, QAfterFilterCondition>
      followingPubkeysElementIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'followingPubkeys',
        value: '',
      ));
    });
  }

  QueryBuilder<FollowingModel, FollowingModel, QAfterFilterCondition>
      followingPubkeysElementIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'followingPubkeys',
        value: '',
      ));
    });
  }

  QueryBuilder<FollowingModel, FollowingModel, QAfterFilterCondition>
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

  QueryBuilder<FollowingModel, FollowingModel, QAfterFilterCondition>
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

  QueryBuilder<FollowingModel, FollowingModel, QAfterFilterCondition>
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

  QueryBuilder<FollowingModel, FollowingModel, QAfterFilterCondition>
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

  QueryBuilder<FollowingModel, FollowingModel, QAfterFilterCondition>
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

  QueryBuilder<FollowingModel, FollowingModel, QAfterFilterCondition>
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

  QueryBuilder<FollowingModel, FollowingModel, QAfterFilterCondition> idEqualTo(
      Id value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<FollowingModel, FollowingModel, QAfterFilterCondition>
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

  QueryBuilder<FollowingModel, FollowingModel, QAfterFilterCondition>
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

  QueryBuilder<FollowingModel, FollowingModel, QAfterFilterCondition> idBetween(
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

  QueryBuilder<FollowingModel, FollowingModel, QAfterFilterCondition>
      updatedAtEqualTo(DateTime value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'updatedAt',
        value: value,
      ));
    });
  }

  QueryBuilder<FollowingModel, FollowingModel, QAfterFilterCondition>
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

  QueryBuilder<FollowingModel, FollowingModel, QAfterFilterCondition>
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

  QueryBuilder<FollowingModel, FollowingModel, QAfterFilterCondition>
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

  QueryBuilder<FollowingModel, FollowingModel, QAfterFilterCondition>
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

  QueryBuilder<FollowingModel, FollowingModel, QAfterFilterCondition>
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

  QueryBuilder<FollowingModel, FollowingModel, QAfterFilterCondition>
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

  QueryBuilder<FollowingModel, FollowingModel, QAfterFilterCondition>
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

  QueryBuilder<FollowingModel, FollowingModel, QAfterFilterCondition>
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

  QueryBuilder<FollowingModel, FollowingModel, QAfterFilterCondition>
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

  QueryBuilder<FollowingModel, FollowingModel, QAfterFilterCondition>
      userPubkeyHexContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'userPubkeyHex',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<FollowingModel, FollowingModel, QAfterFilterCondition>
      userPubkeyHexMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'userPubkeyHex',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<FollowingModel, FollowingModel, QAfterFilterCondition>
      userPubkeyHexIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'userPubkeyHex',
        value: '',
      ));
    });
  }

  QueryBuilder<FollowingModel, FollowingModel, QAfterFilterCondition>
      userPubkeyHexIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'userPubkeyHex',
        value: '',
      ));
    });
  }
}

extension FollowingModelQueryObject
    on QueryBuilder<FollowingModel, FollowingModel, QFilterCondition> {}

extension FollowingModelQueryLinks
    on QueryBuilder<FollowingModel, FollowingModel, QFilterCondition> {}

extension FollowingModelQuerySortBy
    on QueryBuilder<FollowingModel, FollowingModel, QSortBy> {
  QueryBuilder<FollowingModel, FollowingModel, QAfterSortBy> sortByCachedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'cachedAt', Sort.asc);
    });
  }

  QueryBuilder<FollowingModel, FollowingModel, QAfterSortBy>
      sortByCachedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'cachedAt', Sort.desc);
    });
  }

  QueryBuilder<FollowingModel, FollowingModel, QAfterSortBy> sortByUpdatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updatedAt', Sort.asc);
    });
  }

  QueryBuilder<FollowingModel, FollowingModel, QAfterSortBy>
      sortByUpdatedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updatedAt', Sort.desc);
    });
  }

  QueryBuilder<FollowingModel, FollowingModel, QAfterSortBy>
      sortByUserPubkeyHex() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'userPubkeyHex', Sort.asc);
    });
  }

  QueryBuilder<FollowingModel, FollowingModel, QAfterSortBy>
      sortByUserPubkeyHexDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'userPubkeyHex', Sort.desc);
    });
  }
}

extension FollowingModelQuerySortThenBy
    on QueryBuilder<FollowingModel, FollowingModel, QSortThenBy> {
  QueryBuilder<FollowingModel, FollowingModel, QAfterSortBy> thenByCachedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'cachedAt', Sort.asc);
    });
  }

  QueryBuilder<FollowingModel, FollowingModel, QAfterSortBy>
      thenByCachedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'cachedAt', Sort.desc);
    });
  }

  QueryBuilder<FollowingModel, FollowingModel, QAfterSortBy> thenById() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.asc);
    });
  }

  QueryBuilder<FollowingModel, FollowingModel, QAfterSortBy> thenByIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.desc);
    });
  }

  QueryBuilder<FollowingModel, FollowingModel, QAfterSortBy> thenByUpdatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updatedAt', Sort.asc);
    });
  }

  QueryBuilder<FollowingModel, FollowingModel, QAfterSortBy>
      thenByUpdatedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updatedAt', Sort.desc);
    });
  }

  QueryBuilder<FollowingModel, FollowingModel, QAfterSortBy>
      thenByUserPubkeyHex() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'userPubkeyHex', Sort.asc);
    });
  }

  QueryBuilder<FollowingModel, FollowingModel, QAfterSortBy>
      thenByUserPubkeyHexDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'userPubkeyHex', Sort.desc);
    });
  }
}

extension FollowingModelQueryWhereDistinct
    on QueryBuilder<FollowingModel, FollowingModel, QDistinct> {
  QueryBuilder<FollowingModel, FollowingModel, QDistinct> distinctByCachedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'cachedAt');
    });
  }

  QueryBuilder<FollowingModel, FollowingModel, QDistinct>
      distinctByFollowingPubkeys() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'followingPubkeys');
    });
  }

  QueryBuilder<FollowingModel, FollowingModel, QDistinct>
      distinctByUpdatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'updatedAt');
    });
  }

  QueryBuilder<FollowingModel, FollowingModel, QDistinct>
      distinctByUserPubkeyHex({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'userPubkeyHex',
          caseSensitive: caseSensitive);
    });
  }
}

extension FollowingModelQueryProperty
    on QueryBuilder<FollowingModel, FollowingModel, QQueryProperty> {
  QueryBuilder<FollowingModel, int, QQueryOperations> idProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'id');
    });
  }

  QueryBuilder<FollowingModel, DateTime, QQueryOperations> cachedAtProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'cachedAt');
    });
  }

  QueryBuilder<FollowingModel, List<String>, QQueryOperations>
      followingPubkeysProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'followingPubkeys');
    });
  }

  QueryBuilder<FollowingModel, DateTime, QQueryOperations> updatedAtProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'updatedAt');
    });
  }

  QueryBuilder<FollowingModel, String, QQueryOperations>
      userPubkeyHexProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'userPubkeyHex');
    });
  }
}
