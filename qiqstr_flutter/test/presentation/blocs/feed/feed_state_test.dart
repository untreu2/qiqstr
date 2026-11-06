import 'package:flutter_test/flutter_test.dart';
import 'package:qiqstr/presentation/blocs/feed/feed_state.dart';

void main() {
  final userHex = List.filled(64, 'a').join();

  test('clears hashtag when switching away from a hashtag feed', () {
    final state = FeedLoaded(
      notes: const [],
      profiles: const {},
      currentUserHex: userHex,
      hashtag: 'nostr',
    );

    final updated = state.copyWith(clearHashtag: true);

    expect(updated.hashtag, isNull);
  });

  test('clears active list without retaining its title', () {
    final state = FeedLoaded(
      notes: const [],
      profiles: const {},
      currentUserHex: userHex,
      activeListId: 'friends',
      activeListTitle: 'Friends',
    );

    final updated = state.copyWith(clearActiveList: true);

    expect(updated.activeListId, isNull);
    expect(updated.activeListTitle, isNull);
  });
}
