import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/native_rust.dart';
import '../support/onboarding_scenario.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(initializeNativeRust);
  testWidgets('onboarding and recovery backup on a narrow phone',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await runOnboardingScenario(tester);
  });
}
