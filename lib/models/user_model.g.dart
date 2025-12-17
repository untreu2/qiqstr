// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'user_model.dart';

// **************************************************************************
// IsarCollectionGenerator
// **************************************************************************

// coverage:ignore-file
// ignore_for_file: duplicate_ignore, non_constant_identifier_names, constant_identifier_names, invalid_use_of_protected_member, unnecessary_cast, prefer_const_constructors, lines_longer_than_80_chars, require_trailing_commas, inference_failure_on_function_invocation, unnecessary_parenthesis, unnecessary_raw_strings, unnecessary_null_checks, join_return_with_assignment, prefer_final_locals, avoid_js_rounded_ints, avoid_positional_boolean_parameters, always_specify_types

extension GetUserModelCollection on Isar {
  IsarCollection<UserModel> get userModels => this.collection();
}

const UserModelSchema = CollectionSchema(
  name: r'UserModel',
  id: 7195426469378571114,
  properties: {
    r'about': PropertySchema(
      id: 0,
      name: r'about',
      type: IsarType.string,
    ),
    r'banner': PropertySchema(
      id: 1,
      name: r'banner',
      type: IsarType.string,
    ),
    r'cachedAt': PropertySchema(
      id: 2,
      name: r'cachedAt',
      type: IsarType.dateTime,
    ),
    r'followerCount': PropertySchema(
      id: 3,
      name: r'followerCount',
      type: IsarType.long,
    ),
    r'lud16': PropertySchema(
      id: 4,
      name: r'lud16',
      type: IsarType.string,
    ),
    r'name': PropertySchema(
      id: 5,
      name: r'name',
      type: IsarType.string,
    ),
    r'nip05': PropertySchema(
      id: 6,
      name: r'nip05',
      type: IsarType.string,
    ),
    r'nip05Verified': PropertySchema(
      id: 7,
      name: r'nip05Verified',
      type: IsarType.bool,
    ),
    r'npub': PropertySchema(
      id: 8,
      name: r'npub',
      type: IsarType.string,
    ),
    r'profileImage': PropertySchema(
      id: 9,
      name: r'profileImage',
      type: IsarType.string,
    ),
    r'pubkeyHex': PropertySchema(
      id: 10,
      name: r'pubkeyHex',
      type: IsarType.string,
    ),
    r'updatedAt': PropertySchema(
      id: 11,
      name: r'updatedAt',
      type: IsarType.dateTime,
    ),
    r'website': PropertySchema(
      id: 12,
      name: r'website',
      type: IsarType.string,
    )
  },
  estimateSize: _userModelEstimateSize,
  serialize: _userModelSerialize,
  deserialize: _userModelDeserialize,
  deserializeProp: _userModelDeserializeProp,
  idName: r'id',
  indexes: {
    r'pubkeyHex': IndexSchema(
      id: 5838006650964594011,
      name: r'pubkeyHex',
      unique: true,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'pubkeyHex',
          type: IndexType.hash,
          caseSensitive: true,
        )
      ],
    )
  },
  links: {},
  embeddedSchemas: {},
  getId: _userModelGetId,
  getLinks: _userModelGetLinks,
  attach: _userModelAttach,
  version: '3.1.0+1',
);

int _userModelEstimateSize(
  UserModel object,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  var bytesCount = offsets.last;
  bytesCount += 3 + object.about.length * 3;
  bytesCount += 3 + object.banner.length * 3;
  bytesCount += 3 + object.lud16.length * 3;
  bytesCount += 3 + object.name.length * 3;
  bytesCount += 3 + object.nip05.length * 3;
  bytesCount += 3 + object.npub.length * 3;
  bytesCount += 3 + object.profileImage.length * 3;
  bytesCount += 3 + object.pubkeyHex.length * 3;
  bytesCount += 3 + object.website.length * 3;
  return bytesCount;
}

void _userModelSerialize(
  UserModel object,
  IsarWriter writer,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  writer.writeString(offsets[0], object.about);
  writer.writeString(offsets[1], object.banner);
  writer.writeDateTime(offsets[2], object.cachedAt);
  writer.writeLong(offsets[3], object.followerCount);
  writer.writeString(offsets[4], object.lud16);
  writer.writeString(offsets[5], object.name);
  writer.writeString(offsets[6], object.nip05);
  writer.writeBool(offsets[7], object.nip05Verified);
  writer.writeString(offsets[8], object.npub);
  writer.writeString(offsets[9], object.profileImage);
  writer.writeString(offsets[10], object.pubkeyHex);
  writer.writeDateTime(offsets[11], object.updatedAt);
  writer.writeString(offsets[12], object.website);
}

UserModel _userModelDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = UserModel();
  object.about = reader.readString(offsets[0]);
  object.banner = reader.readString(offsets[1]);
  object.cachedAt = reader.readDateTime(offsets[2]);
  object.followerCount = reader.readLongOrNull(offsets[3]);
  object.id = id;
  object.lud16 = reader.readString(offsets[4]);
  object.name = reader.readString(offsets[5]);
  object.nip05 = reader.readString(offsets[6]);
  object.nip05Verified = reader.readBool(offsets[7]);
  object.profileImage = reader.readString(offsets[9]);
  object.pubkeyHex = reader.readString(offsets[10]);
  object.updatedAt = reader.readDateTime(offsets[11]);
  object.website = reader.readString(offsets[12]);
  return object;
}

P _userModelDeserializeProp<P>(
  IsarReader reader,
  int propertyId,
  int offset,
  Map<Type, List<int>> allOffsets,
) {
  switch (propertyId) {
    case 0:
      return (reader.readString(offset)) as P;
    case 1:
      return (reader.readString(offset)) as P;
    case 2:
      return (reader.readDateTime(offset)) as P;
    case 3:
      return (reader.readLongOrNull(offset)) as P;
    case 4:
      return (reader.readString(offset)) as P;
    case 5:
      return (reader.readString(offset)) as P;
    case 6:
      return (reader.readString(offset)) as P;
    case 7:
      return (reader.readBool(offset)) as P;
    case 8:
      return (reader.readString(offset)) as P;
    case 9:
      return (reader.readString(offset)) as P;
    case 10:
      return (reader.readString(offset)) as P;
    case 11:
      return (reader.readDateTime(offset)) as P;
    case 12:
      return (reader.readString(offset)) as P;
    default:
      throw IsarError('Unknown property with id $propertyId');
  }
}

Id _userModelGetId(UserModel object) {
  return object.id;
}

List<IsarLinkBase<dynamic>> _userModelGetLinks(UserModel object) {
  return [];
}

void _userModelAttach(IsarCollection<dynamic> col, Id id, UserModel object) {
  object.id = id;
}

extension UserModelByIndex on IsarCollection<UserModel> {
  Future<UserModel?> getByPubkeyHex(String pubkeyHex) {
    return getByIndex(r'pubkeyHex', [pubkeyHex]);
  }

  UserModel? getByPubkeyHexSync(String pubkeyHex) {
    return getByIndexSync(r'pubkeyHex', [pubkeyHex]);
  }

  Future<bool> deleteByPubkeyHex(String pubkeyHex) {
    return deleteByIndex(r'pubkeyHex', [pubkeyHex]);
  }

  bool deleteByPubkeyHexSync(String pubkeyHex) {
    return deleteByIndexSync(r'pubkeyHex', [pubkeyHex]);
  }

  Future<List<UserModel?>> getAllByPubkeyHex(List<String> pubkeyHexValues) {
    final values = pubkeyHexValues.map((e) => [e]).toList();
    return getAllByIndex(r'pubkeyHex', values);
  }

  List<UserModel?> getAllByPubkeyHexSync(List<String> pubkeyHexValues) {
    final values = pubkeyHexValues.map((e) => [e]).toList();
    return getAllByIndexSync(r'pubkeyHex', values);
  }

  Future<int> deleteAllByPubkeyHex(List<String> pubkeyHexValues) {
    final values = pubkeyHexValues.map((e) => [e]).toList();
    return deleteAllByIndex(r'pubkeyHex', values);
  }

  int deleteAllByPubkeyHexSync(List<String> pubkeyHexValues) {
    final values = pubkeyHexValues.map((e) => [e]).toList();
    return deleteAllByIndexSync(r'pubkeyHex', values);
  }

  Future<Id> putByPubkeyHex(UserModel object) {
    return putByIndex(r'pubkeyHex', object);
  }

  Id putByPubkeyHexSync(UserModel object, {bool saveLinks = true}) {
    return putByIndexSync(r'pubkeyHex', object, saveLinks: saveLinks);
  }

  Future<List<Id>> putAllByPubkeyHex(List<UserModel> objects) {
    return putAllByIndex(r'pubkeyHex', objects);
  }

  List<Id> putAllByPubkeyHexSync(List<UserModel> objects,
      {bool saveLinks = true}) {
    return putAllByIndexSync(r'pubkeyHex', objects, saveLinks: saveLinks);
  }
}

extension UserModelQueryWhereSort
    on QueryBuilder<UserModel, UserModel, QWhere> {
  QueryBuilder<UserModel, UserModel, QAfterWhere> anyId() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(const IdWhereClause.any());
    });
  }
}

extension UserModelQueryWhere
    on QueryBuilder<UserModel, UserModel, QWhereClause> {
  QueryBuilder<UserModel, UserModel, QAfterWhereClause> idEqualTo(Id id) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(
        lower: id,
        upper: id,
      ));
    });
  }

  QueryBuilder<UserModel, UserModel, QAfterWhereClause> idNotEqualTo(Id id) {
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

  QueryBuilder<UserModel, UserModel, QAfterWhereClause> idGreaterThan(Id id,
      {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.greaterThan(lower: id, includeLower: include),
      );
    });
  }

  QueryBuilder<UserModel, UserModel, QAfterWhereClause> idLessThan(Id id,
      {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.lessThan(upper: id, includeUpper: include),
      );
    });
  }

  QueryBuilder<UserModel, UserModel, QAfterWhereClause> idBetween(
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

  QueryBuilder<UserModel, UserModel, QAfterWhereClause> pubkeyHexEqualTo(
      String pubkeyHex) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'pubkeyHex',
        value: [pubkeyHex],
      ));
    });
  }

  QueryBuilder<UserModel, UserModel, QAfterWhereClause> pubkeyHexNotEqualTo(
      String pubkeyHex) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'pubkeyHex',
              lower: [],
              upper: [pubkeyHex],
              includeUpper: false,
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'pubkeyHex',
              lower: [pubkeyHex],
              includeLower: false,
              upper: [],
            ));
      } else {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'pubkeyHex',
              lower: [pubkeyHex],
              includeLower: false,
              upper: [],
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'pubkeyHex',
              lower: [],
              upper: [pubkeyHex],
              includeUpper: false,
            ));
      }
    });
  }
}

extension UserModelQueryFilter
    on QueryBuilder<UserModel, UserModel, QFilterCondition> {
  QueryBuilder<UserModel, UserModel, QAfterFilterCondition> aboutEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'about',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<UserModel, UserModel, QAfterFilterCondition> aboutGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'about',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<UserModel, UserModel, QAfterFilterCondition> aboutLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'about',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<UserModel, UserModel, QAfterFilterCondition> aboutBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'about',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<UserModel, UserModel, QAfterFilterCondition> aboutStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'about',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<UserModel, UserModel, QAfterFilterCondition> aboutEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'about',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<UserModel, UserModel, QAfterFilterCondition> aboutContains(
      String value,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'about',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<UserModel, UserModel, QAfterFilterCondition> aboutMatches(
      String pattern,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'about',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<UserModel, UserModel, QAfterFilterCondition> aboutIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'about',
        value: '',
      ));
    });
  }

  QueryBuilder<UserModel, UserModel, QAfterFilterCondition> aboutIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'about',
        value: '',
      ));
    });
  }

  QueryBuilder<UserModel, UserModel, QAfterFilterCondition> bannerEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'banner',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<UserModel, UserModel, QAfterFilterCondition> bannerGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'banner',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<UserModel, UserModel, QAfterFilterCondition> bannerLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'banner',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<UserModel, UserModel, QAfterFilterCondition> bannerBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'banner',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<UserModel, UserModel, QAfterFilterCondition> bannerStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'banner',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<UserModel, UserModel, QAfterFilterCondition> bannerEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'banner',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<UserModel, UserModel, QAfterFilterCondition> bannerContains(
      String value,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'banner',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<UserModel, UserModel, QAfterFilterCondition> bannerMatches(
      String pattern,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'banner',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<UserModel, UserModel, QAfterFilterCondition> bannerIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'banner',
        value: '',
      ));
    });
  }

  QueryBuilder<UserModel, UserModel, QAfterFilterCondition> bannerIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'banner',
        value: '',
      ));
    });
  }

  QueryBuilder<UserModel, UserModel, QAfterFilterCondition> cachedAtEqualTo(
      DateTime value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'cachedAt',
        value: value,
      ));
    });
  }

  QueryBuilder<UserModel, UserModel, QAfterFilterCondition> cachedAtGreaterThan(
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

  QueryBuilder<UserModel, UserModel, QAfterFilterCondition> cachedAtLessThan(
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

  QueryBuilder<UserModel, UserModel, QAfterFilterCondition> cachedAtBetween(
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

  QueryBuilder<UserModel, UserModel, QAfterFilterCondition>
      followerCountIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'followerCount',
      ));
    });
  }

  QueryBuilder<UserModel, UserModel, QAfterFilterCondition>
      followerCountIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'followerCount',
      ));
    });
  }

  QueryBuilder<UserModel, UserModel, QAfterFilterCondition>
      followerCountEqualTo(int? value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'followerCount',
        value: value,
      ));
    });
  }

  QueryBuilder<UserModel, UserModel, QAfterFilterCondition>
      followerCountGreaterThan(
    int? value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'followerCount',
        value: value,
      ));
    });
  }

  QueryBuilder<UserModel, UserModel, QAfterFilterCondition>
      followerCountLessThan(
    int? value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'followerCount',
        value: value,
      ));
    });
  }

  QueryBuilder<UserModel, UserModel, QAfterFilterCondition>
      followerCountBetween(
    int? lower,
    int? upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'followerCount',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<UserModel, UserModel, QAfterFilterCondition> idEqualTo(
      Id value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<UserModel, UserModel, QAfterFilterCondition> idGreaterThan(
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

  QueryBuilder<UserModel, UserModel, QAfterFilterCondition> idLessThan(
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

  QueryBuilder<UserModel, UserModel, QAfterFilterCondition> idBetween(
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

  QueryBuilder<UserModel, UserModel, QAfterFilterCondition> lud16EqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'lud16',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<UserModel, UserModel, QAfterFilterCondition> lud16GreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'lud16',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<UserModel, UserModel, QAfterFilterCondition> lud16LessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'lud16',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<UserModel, UserModel, QAfterFilterCondition> lud16Between(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'lud16',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<UserModel, UserModel, QAfterFilterCondition> lud16StartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'lud16',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<UserModel, UserModel, QAfterFilterCondition> lud16EndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'lud16',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<UserModel, UserModel, QAfterFilterCondition> lud16Contains(
      String value,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'lud16',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<UserModel, UserModel, QAfterFilterCondition> lud16Matches(
      String pattern,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'lud16',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<UserModel, UserModel, QAfterFilterCondition> lud16IsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'lud16',
        value: '',
      ));
    });
  }

  QueryBuilder<UserModel, UserModel, QAfterFilterCondition> lud16IsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'lud16',
        value: '',
      ));
    });
  }

  QueryBuilder<UserModel, UserModel, QAfterFilterCondition> nameEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'name',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<UserModel, UserModel, QAfterFilterCondition> nameGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'name',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<UserModel, UserModel, QAfterFilterCondition> nameLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'name',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<UserModel, UserModel, QAfterFilterCondition> nameBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'name',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<UserModel, UserModel, QAfterFilterCondition> nameStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'name',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<UserModel, UserModel, QAfterFilterCondition> nameEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'name',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<UserModel, UserModel, QAfterFilterCondition> nameContains(
      String value,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'name',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<UserModel, UserModel, QAfterFilterCondition> nameMatches(
      String pattern,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'name',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<UserModel, UserModel, QAfterFilterCondition> nameIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'name',
        value: '',
      ));
    });
  }

  QueryBuilder<UserModel, UserModel, QAfterFilterCondition> nameIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'name',
        value: '',
      ));
    });
  }

  QueryBuilder<UserModel, UserModel, QAfterFilterCondition> nip05EqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'nip05',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<UserModel, UserModel, QAfterFilterCondition> nip05GreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'nip05',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<UserModel, UserModel, QAfterFilterCondition> nip05LessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'nip05',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<UserModel, UserModel, QAfterFilterCondition> nip05Between(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'nip05',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<UserModel, UserModel, QAfterFilterCondition> nip05StartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'nip05',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<UserModel, UserModel, QAfterFilterCondition> nip05EndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'nip05',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<UserModel, UserModel, QAfterFilterCondition> nip05Contains(
      String value,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'nip05',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<UserModel, UserModel, QAfterFilterCondition> nip05Matches(
      String pattern,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'nip05',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<UserModel, UserModel, QAfterFilterCondition> nip05IsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'nip05',
        value: '',
      ));
    });
  }

  QueryBuilder<UserModel, UserModel, QAfterFilterCondition> nip05IsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'nip05',
        value: '',
      ));
    });
  }

  QueryBuilder<UserModel, UserModel, QAfterFilterCondition>
      nip05VerifiedEqualTo(bool value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'nip05Verified',
        value: value,
      ));
    });
  }

  QueryBuilder<UserModel, UserModel, QAfterFilterCondition> npubEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'npub',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<UserModel, UserModel, QAfterFilterCondition> npubGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'npub',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<UserModel, UserModel, QAfterFilterCondition> npubLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'npub',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<UserModel, UserModel, QAfterFilterCondition> npubBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'npub',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<UserModel, UserModel, QAfterFilterCondition> npubStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'npub',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<UserModel, UserModel, QAfterFilterCondition> npubEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'npub',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<UserModel, UserModel, QAfterFilterCondition> npubContains(
      String value,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'npub',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<UserModel, UserModel, QAfterFilterCondition> npubMatches(
      String pattern,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'npub',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<UserModel, UserModel, QAfterFilterCondition> npubIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'npub',
        value: '',
      ));
    });
  }

  QueryBuilder<UserModel, UserModel, QAfterFilterCondition> npubIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'npub',
        value: '',
      ));
    });
  }

  QueryBuilder<UserModel, UserModel, QAfterFilterCondition> profileImageEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'profileImage',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<UserModel, UserModel, QAfterFilterCondition>
      profileImageGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'profileImage',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<UserModel, UserModel, QAfterFilterCondition>
      profileImageLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'profileImage',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<UserModel, UserModel, QAfterFilterCondition> profileImageBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'profileImage',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<UserModel, UserModel, QAfterFilterCondition>
      profileImageStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'profileImage',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<UserModel, UserModel, QAfterFilterCondition>
      profileImageEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'profileImage',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<UserModel, UserModel, QAfterFilterCondition>
      profileImageContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'profileImage',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<UserModel, UserModel, QAfterFilterCondition> profileImageMatches(
      String pattern,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'profileImage',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<UserModel, UserModel, QAfterFilterCondition>
      profileImageIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'profileImage',
        value: '',
      ));
    });
  }

  QueryBuilder<UserModel, UserModel, QAfterFilterCondition>
      profileImageIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'profileImage',
        value: '',
      ));
    });
  }

  QueryBuilder<UserModel, UserModel, QAfterFilterCondition> pubkeyHexEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'pubkeyHex',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<UserModel, UserModel, QAfterFilterCondition>
      pubkeyHexGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'pubkeyHex',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<UserModel, UserModel, QAfterFilterCondition> pubkeyHexLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'pubkeyHex',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<UserModel, UserModel, QAfterFilterCondition> pubkeyHexBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'pubkeyHex',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<UserModel, UserModel, QAfterFilterCondition> pubkeyHexStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'pubkeyHex',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<UserModel, UserModel, QAfterFilterCondition> pubkeyHexEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'pubkeyHex',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<UserModel, UserModel, QAfterFilterCondition> pubkeyHexContains(
      String value,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'pubkeyHex',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<UserModel, UserModel, QAfterFilterCondition> pubkeyHexMatches(
      String pattern,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'pubkeyHex',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<UserModel, UserModel, QAfterFilterCondition> pubkeyHexIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'pubkeyHex',
        value: '',
      ));
    });
  }

  QueryBuilder<UserModel, UserModel, QAfterFilterCondition>
      pubkeyHexIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'pubkeyHex',
        value: '',
      ));
    });
  }

  QueryBuilder<UserModel, UserModel, QAfterFilterCondition> updatedAtEqualTo(
      DateTime value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'updatedAt',
        value: value,
      ));
    });
  }

  QueryBuilder<UserModel, UserModel, QAfterFilterCondition>
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

  QueryBuilder<UserModel, UserModel, QAfterFilterCondition> updatedAtLessThan(
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

  QueryBuilder<UserModel, UserModel, QAfterFilterCondition> updatedAtBetween(
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

  QueryBuilder<UserModel, UserModel, QAfterFilterCondition> websiteEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'website',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<UserModel, UserModel, QAfterFilterCondition> websiteGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'website',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<UserModel, UserModel, QAfterFilterCondition> websiteLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'website',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<UserModel, UserModel, QAfterFilterCondition> websiteBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'website',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<UserModel, UserModel, QAfterFilterCondition> websiteStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'website',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<UserModel, UserModel, QAfterFilterCondition> websiteEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'website',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<UserModel, UserModel, QAfterFilterCondition> websiteContains(
      String value,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'website',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<UserModel, UserModel, QAfterFilterCondition> websiteMatches(
      String pattern,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'website',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<UserModel, UserModel, QAfterFilterCondition> websiteIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'website',
        value: '',
      ));
    });
  }

  QueryBuilder<UserModel, UserModel, QAfterFilterCondition>
      websiteIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'website',
        value: '',
      ));
    });
  }
}

extension UserModelQueryObject
    on QueryBuilder<UserModel, UserModel, QFilterCondition> {}

extension UserModelQueryLinks
    on QueryBuilder<UserModel, UserModel, QFilterCondition> {}

extension UserModelQuerySortBy on QueryBuilder<UserModel, UserModel, QSortBy> {
  QueryBuilder<UserModel, UserModel, QAfterSortBy> sortByAbout() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'about', Sort.asc);
    });
  }

  QueryBuilder<UserModel, UserModel, QAfterSortBy> sortByAboutDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'about', Sort.desc);
    });
  }

  QueryBuilder<UserModel, UserModel, QAfterSortBy> sortByBanner() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'banner', Sort.asc);
    });
  }

  QueryBuilder<UserModel, UserModel, QAfterSortBy> sortByBannerDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'banner', Sort.desc);
    });
  }

  QueryBuilder<UserModel, UserModel, QAfterSortBy> sortByCachedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'cachedAt', Sort.asc);
    });
  }

  QueryBuilder<UserModel, UserModel, QAfterSortBy> sortByCachedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'cachedAt', Sort.desc);
    });
  }

  QueryBuilder<UserModel, UserModel, QAfterSortBy> sortByFollowerCount() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'followerCount', Sort.asc);
    });
  }

  QueryBuilder<UserModel, UserModel, QAfterSortBy> sortByFollowerCountDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'followerCount', Sort.desc);
    });
  }

  QueryBuilder<UserModel, UserModel, QAfterSortBy> sortByLud16() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lud16', Sort.asc);
    });
  }

  QueryBuilder<UserModel, UserModel, QAfterSortBy> sortByLud16Desc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lud16', Sort.desc);
    });
  }

  QueryBuilder<UserModel, UserModel, QAfterSortBy> sortByName() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'name', Sort.asc);
    });
  }

  QueryBuilder<UserModel, UserModel, QAfterSortBy> sortByNameDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'name', Sort.desc);
    });
  }

  QueryBuilder<UserModel, UserModel, QAfterSortBy> sortByNip05() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'nip05', Sort.asc);
    });
  }

  QueryBuilder<UserModel, UserModel, QAfterSortBy> sortByNip05Desc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'nip05', Sort.desc);
    });
  }

  QueryBuilder<UserModel, UserModel, QAfterSortBy> sortByNip05Verified() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'nip05Verified', Sort.asc);
    });
  }

  QueryBuilder<UserModel, UserModel, QAfterSortBy> sortByNip05VerifiedDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'nip05Verified', Sort.desc);
    });
  }

  QueryBuilder<UserModel, UserModel, QAfterSortBy> sortByNpub() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'npub', Sort.asc);
    });
  }

  QueryBuilder<UserModel, UserModel, QAfterSortBy> sortByNpubDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'npub', Sort.desc);
    });
  }

  QueryBuilder<UserModel, UserModel, QAfterSortBy> sortByProfileImage() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'profileImage', Sort.asc);
    });
  }

  QueryBuilder<UserModel, UserModel, QAfterSortBy> sortByProfileImageDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'profileImage', Sort.desc);
    });
  }

  QueryBuilder<UserModel, UserModel, QAfterSortBy> sortByPubkeyHex() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'pubkeyHex', Sort.asc);
    });
  }

  QueryBuilder<UserModel, UserModel, QAfterSortBy> sortByPubkeyHexDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'pubkeyHex', Sort.desc);
    });
  }

  QueryBuilder<UserModel, UserModel, QAfterSortBy> sortByUpdatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updatedAt', Sort.asc);
    });
  }

  QueryBuilder<UserModel, UserModel, QAfterSortBy> sortByUpdatedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updatedAt', Sort.desc);
    });
  }

  QueryBuilder<UserModel, UserModel, QAfterSortBy> sortByWebsite() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'website', Sort.asc);
    });
  }

  QueryBuilder<UserModel, UserModel, QAfterSortBy> sortByWebsiteDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'website', Sort.desc);
    });
  }
}

extension UserModelQuerySortThenBy
    on QueryBuilder<UserModel, UserModel, QSortThenBy> {
  QueryBuilder<UserModel, UserModel, QAfterSortBy> thenByAbout() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'about', Sort.asc);
    });
  }

  QueryBuilder<UserModel, UserModel, QAfterSortBy> thenByAboutDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'about', Sort.desc);
    });
  }

  QueryBuilder<UserModel, UserModel, QAfterSortBy> thenByBanner() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'banner', Sort.asc);
    });
  }

  QueryBuilder<UserModel, UserModel, QAfterSortBy> thenByBannerDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'banner', Sort.desc);
    });
  }

  QueryBuilder<UserModel, UserModel, QAfterSortBy> thenByCachedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'cachedAt', Sort.asc);
    });
  }

  QueryBuilder<UserModel, UserModel, QAfterSortBy> thenByCachedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'cachedAt', Sort.desc);
    });
  }

  QueryBuilder<UserModel, UserModel, QAfterSortBy> thenByFollowerCount() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'followerCount', Sort.asc);
    });
  }

  QueryBuilder<UserModel, UserModel, QAfterSortBy> thenByFollowerCountDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'followerCount', Sort.desc);
    });
  }

  QueryBuilder<UserModel, UserModel, QAfterSortBy> thenById() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.asc);
    });
  }

  QueryBuilder<UserModel, UserModel, QAfterSortBy> thenByIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.desc);
    });
  }

  QueryBuilder<UserModel, UserModel, QAfterSortBy> thenByLud16() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lud16', Sort.asc);
    });
  }

  QueryBuilder<UserModel, UserModel, QAfterSortBy> thenByLud16Desc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lud16', Sort.desc);
    });
  }

  QueryBuilder<UserModel, UserModel, QAfterSortBy> thenByName() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'name', Sort.asc);
    });
  }

  QueryBuilder<UserModel, UserModel, QAfterSortBy> thenByNameDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'name', Sort.desc);
    });
  }

  QueryBuilder<UserModel, UserModel, QAfterSortBy> thenByNip05() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'nip05', Sort.asc);
    });
  }

  QueryBuilder<UserModel, UserModel, QAfterSortBy> thenByNip05Desc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'nip05', Sort.desc);
    });
  }

  QueryBuilder<UserModel, UserModel, QAfterSortBy> thenByNip05Verified() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'nip05Verified', Sort.asc);
    });
  }

  QueryBuilder<UserModel, UserModel, QAfterSortBy> thenByNip05VerifiedDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'nip05Verified', Sort.desc);
    });
  }

  QueryBuilder<UserModel, UserModel, QAfterSortBy> thenByNpub() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'npub', Sort.asc);
    });
  }

  QueryBuilder<UserModel, UserModel, QAfterSortBy> thenByNpubDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'npub', Sort.desc);
    });
  }

  QueryBuilder<UserModel, UserModel, QAfterSortBy> thenByProfileImage() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'profileImage', Sort.asc);
    });
  }

  QueryBuilder<UserModel, UserModel, QAfterSortBy> thenByProfileImageDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'profileImage', Sort.desc);
    });
  }

  QueryBuilder<UserModel, UserModel, QAfterSortBy> thenByPubkeyHex() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'pubkeyHex', Sort.asc);
    });
  }

  QueryBuilder<UserModel, UserModel, QAfterSortBy> thenByPubkeyHexDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'pubkeyHex', Sort.desc);
    });
  }

  QueryBuilder<UserModel, UserModel, QAfterSortBy> thenByUpdatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updatedAt', Sort.asc);
    });
  }

  QueryBuilder<UserModel, UserModel, QAfterSortBy> thenByUpdatedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updatedAt', Sort.desc);
    });
  }

  QueryBuilder<UserModel, UserModel, QAfterSortBy> thenByWebsite() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'website', Sort.asc);
    });
  }

  QueryBuilder<UserModel, UserModel, QAfterSortBy> thenByWebsiteDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'website', Sort.desc);
    });
  }
}

extension UserModelQueryWhereDistinct
    on QueryBuilder<UserModel, UserModel, QDistinct> {
  QueryBuilder<UserModel, UserModel, QDistinct> distinctByAbout(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'about', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<UserModel, UserModel, QDistinct> distinctByBanner(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'banner', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<UserModel, UserModel, QDistinct> distinctByCachedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'cachedAt');
    });
  }

  QueryBuilder<UserModel, UserModel, QDistinct> distinctByFollowerCount() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'followerCount');
    });
  }

  QueryBuilder<UserModel, UserModel, QDistinct> distinctByLud16(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'lud16', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<UserModel, UserModel, QDistinct> distinctByName(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'name', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<UserModel, UserModel, QDistinct> distinctByNip05(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'nip05', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<UserModel, UserModel, QDistinct> distinctByNip05Verified() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'nip05Verified');
    });
  }

  QueryBuilder<UserModel, UserModel, QDistinct> distinctByNpub(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'npub', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<UserModel, UserModel, QDistinct> distinctByProfileImage(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'profileImage', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<UserModel, UserModel, QDistinct> distinctByPubkeyHex(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'pubkeyHex', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<UserModel, UserModel, QDistinct> distinctByUpdatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'updatedAt');
    });
  }

  QueryBuilder<UserModel, UserModel, QDistinct> distinctByWebsite(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'website', caseSensitive: caseSensitive);
    });
  }
}

extension UserModelQueryProperty
    on QueryBuilder<UserModel, UserModel, QQueryProperty> {
  QueryBuilder<UserModel, int, QQueryOperations> idProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'id');
    });
  }

  QueryBuilder<UserModel, String, QQueryOperations> aboutProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'about');
    });
  }

  QueryBuilder<UserModel, String, QQueryOperations> bannerProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'banner');
    });
  }

  QueryBuilder<UserModel, DateTime, QQueryOperations> cachedAtProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'cachedAt');
    });
  }

  QueryBuilder<UserModel, int?, QQueryOperations> followerCountProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'followerCount');
    });
  }

  QueryBuilder<UserModel, String, QQueryOperations> lud16Property() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'lud16');
    });
  }

  QueryBuilder<UserModel, String, QQueryOperations> nameProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'name');
    });
  }

  QueryBuilder<UserModel, String, QQueryOperations> nip05Property() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'nip05');
    });
  }

  QueryBuilder<UserModel, bool, QQueryOperations> nip05VerifiedProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'nip05Verified');
    });
  }

  QueryBuilder<UserModel, String, QQueryOperations> npubProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'npub');
    });
  }

  QueryBuilder<UserModel, String, QQueryOperations> profileImageProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'profileImage');
    });
  }

  QueryBuilder<UserModel, String, QQueryOperations> pubkeyHexProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'pubkeyHex');
    });
  }

  QueryBuilder<UserModel, DateTime, QQueryOperations> updatedAtProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'updatedAt');
    });
  }

  QueryBuilder<UserModel, String, QQueryOperations> websiteProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'website');
    });
  }
}
