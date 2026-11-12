import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../lib/src/rust/frb_generated.dart';
import '../test/support/onboarding_scenario.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(RustLib.init);
  testWidgets(
      'onboarding and recovery backup on a device', runOnboardingScenario);
}
