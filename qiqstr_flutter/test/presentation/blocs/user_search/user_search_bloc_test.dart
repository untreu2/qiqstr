import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import '../../../../lib/data/repositories/profile_repository.dart';
import '../../../../lib/data/services/auth_service.dart';
import '../../../../lib/data/services/vertex_search_service.dart';
import '../../../../lib/data/sync/sync_service.dart';
import '../../../../lib/domain/entities/user_profile.dart';
import '../../../../lib/presentation/blocs/user_search/user_search_bloc.dart';
import '../../../../lib/presentation/blocs/user_search/user_search_event.dart';
import '../../../../lib/presentation/blocs/user_search/user_search_state.dart';

class _Profiles implements ProfileRepository {
  @override
  Future<List<UserProfile>> searchProfiles(String query,
          {int limit = 50}) async =>
      [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Search implements VertexSearchService {
  final requests = <String, Completer<List<UserProfile>>>{};

  @override
  Future<List<UserProfile>> searchProfiles(String query, {int limit = 20}) =>
      (requests[query] = Completer<List<UserProfile>>()).future;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Auth implements AuthService {
  @override
  String? hexToNpub(String hex) => hex;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Sync implements SyncService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  for (final clearQuery in [false, true]) {
    test(
        'discards stale results when query ${clearQuery ? 'clears' : 'changes'}',
        () async {
      final search = _Search();
      final bloc = UserSearchBloc(
        profileRepository: _Profiles(),
        authService: _Auth(),
        syncService: _Sync(),
        vertexSearchService: search,
      );
      addTearDown(bloc.close);
      bloc.add(const UserSearchQueryChanged('old'));
      await Future<void>.delayed(Duration.zero);
      bloc.add(UserSearchQueryChanged(clearQuery ? '' : 'new'));
      await Future<void>.delayed(Duration.zero);
      if (!clearQuery) {
        search.requests['new']!.complete([
          const UserProfile(pubkey: 'new-user', name: 'New'),
        ]);
        await Future<void>.delayed(Duration.zero);
      }
      search.requests['old']!.complete([
        const UserProfile(pubkey: 'old-user', name: 'Old'),
      ]);
      await Future<void>.delayed(Duration.zero);
      final state = bloc.state as UserSearchLoaded;
      expect(state.isSearching, isFalse);
      expect(state.filteredUsers.map((user) => user['pubkey']),
          clearQuery ? isEmpty : ['new-user']);
    });
  }
}
