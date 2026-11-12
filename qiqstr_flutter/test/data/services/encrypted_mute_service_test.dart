import 'package:flutter_test/flutter_test.dart';

import '../../../lib/data/services/encrypted_mute_service.dart';
import '../../../lib/src/rust/frb_generated.dart';

class _Api implements RustLibApi {
  List<String> pubkeys = [];
  List<String> words = [];
  bool fail = false;

  @override
  Future<void> crateApiDatabaseSetActiveMuteList({
    required List<String> mutedPubkeys,
    required List<String> mutedWords,
  }) async {
    if (fail) throw StateError('database unavailable');
    pubkeys = mutedPubkeys;
    words = mutedWords;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late _Api api;
  final service = EncryptedMuteService.instance;

  setUpAll(() {
    api = _Api();
    RustLib.initMock(api: api);
  });

  tearDownAll(RustLib.dispose);

  setUp(() {
    api.fail = false;
    service.clear();
  });

  tearDown(() {
    service.clear();
  });

  test(
    'adding, removing and rolling back mutes updates native filters',
    () async {
      service.addMutedPubkey('author');
      service.addMutedWord('  WORD  ');
      await Future<void>.delayed(Duration.zero);
      expect(api.pubkeys, ['author']);
      expect(api.words, ['word']);
      expect(service.containsMutedWord('A Word'), isTrue);
      service.removeMutedPubkey('author');
      service.removeMutedWord('word');
      await Future<void>.delayed(Duration.zero);
      expect(api.pubkeys, isEmpty);
      expect(api.words, isEmpty);
      service.addMutedPubkey('author');
      service.addMutedWord('word');
      await Future<void>.delayed(Duration.zero);
      expect(api.pubkeys, ['author']);
      expect(api.words, ['word']);
      service.clear();
      await Future<void>.delayed(Duration.zero);
      expect(api.pubkeys, isEmpty);
      expect(api.words, isEmpty);
    },
  );

  test('muted words treat regular expression characters as literal text', () {
    service.addMutedWord('a.b');
    expect(service.containsMutedWord('A.B'), isTrue);
    expect(service.containsMutedWord('axb'), isFalse);
  });

  test(
    'native filter failures cannot escape an asynchronous service boundary',
    () async {
      api.fail = true;
      service.addMutedWord('word');
      await Future<void>.delayed(Duration.zero);
      expect(service.containsMutedWord('word'), isTrue);
    },
  );
}
