import 'package:flutter_test/flutter_test.dart';

import '../../lib/src/rust/api/relay.dart' as relay;
import '../support/native_rust.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await initializeNativeRust();
    await relay.initClient(relayUrls: [], discoveryRelays: []);
  });

  test(
    'an offline subscription delivers its failure through the stream',
    () async {
      await expectLater(
        relay.subscribeToEvents(filterJson: '{"kinds":[1]}'),
        emitsInOrder([emitsError(anything), emitsDone]),
      );
    },
  );

  test('an invalid filter delivers its failure through the stream', () async {
    await expectLater(
      relay.subscribeToEvents(filterJson: 'not-json'),
      emitsInOrder([emitsError(anything), emitsDone]),
    );
  });
}
