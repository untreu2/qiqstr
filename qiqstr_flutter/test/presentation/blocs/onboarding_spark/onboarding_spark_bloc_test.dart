import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import '../../../../lib/core/base/result.dart';
import '../../../../lib/data/services/auth_service.dart';
import '../../../../lib/data/services/spark_service.dart';
import '../../../../lib/presentation/blocs/onboarding_spark/onboarding_spark_bloc.dart';
import '../../../../lib/presentation/blocs/onboarding_spark/onboarding_spark_event.dart';
import '../../../../lib/presentation/blocs/onboarding_spark/onboarding_spark_state.dart';

class _Auth implements AuthService {
  @override
  final String? currentUserNpub;

  _Auth(this.currentUserNpub);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Spark extends SparkService {
  final setupStarted = Completer<void>();
  final recovery = Completer<Result<String>>();
  int restoreCount = 0;
  String? account;

  @override
  void setActiveAccount(String npub) => account = npub;

  @override
  Future<Result<String>> getOrCreateMnemonic() {
    setupStarted.complete();
    return recovery.future;
  }

  @override
  Future<Result<void>> restoreWallet(String entropyHex) async {
    restoreCount++;
    return Result.success(null);
  }
}

void main() {
  test(
    'signed-out onboarding cannot reuse a previous wallet session',
    () async {
      final spark = _Spark()..setActiveAccount('previous-account');
      final bloc = OnboardingSparkBloc(
        sparkService: spark,
        authService: _Auth(null),
      );
      addTearDown(spark.dispose);
      addTearDown(bloc.close);
      final rejected = bloc.stream.firstWhere(
        (state) => state is OnboardingSparkError,
      );
      bloc.add(const OnboardingSparkWalletSetupRequested());
      expect(
        (await rejected as OnboardingSparkError).message,
        'Not authenticated',
      );
      expect(spark.setupStarted.isCompleted, isFalse);
    },
  );

  test(
    'setup and restore cannot compete for the same wallet recovery key',
    () async {
      final spark = _Spark();
      final bloc = OnboardingSparkBloc(
        sparkService: spark,
        authService: _Auth('alice'),
      );
      addTearDown(spark.dispose);
      addTearDown(bloc.close);
      bloc.add(const OnboardingSparkWalletSetupRequested());
      await spark.setupStarted.future;
      bloc.add(const OnboardingSparkRestoreRequested('recovery'));
      await Future<void>.delayed(Duration.zero);
      expect(spark.restoreCount, 0);
      final ready = bloc.stream.firstWhere(
        (state) => state is OnboardingSparkReady,
      );
      spark.recovery.complete(Result.success('recovery'));
      expect((await ready as OnboardingSparkReady).shouldNavigate, isTrue);
      expect(spark.account, 'alice');
    },
  );
}
