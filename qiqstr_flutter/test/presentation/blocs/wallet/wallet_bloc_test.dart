import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import '../../../../lib/core/base/result.dart';
import '../../../../lib/data/repositories/profile_repository.dart';
import '../../../../lib/data/services/auth_service.dart';
import '../../../../lib/data/services/cashu_service.dart';
import '../../../../lib/data/services/nwc_service.dart';
import '../../../../lib/data/services/spark_service.dart';
import '../../../../lib/data/sync/sync_service.dart';
import '../../../../lib/presentation/blocs/wallet/wallet_bloc.dart';
import '../../../../lib/presentation/blocs/wallet/wallet_event.dart';
import '../../../../lib/presentation/blocs/wallet/wallet_state.dart';

class _Nwc extends NwcService {
  bool failBalance = true;
  final payment = Completer<Result<Map<String, dynamic>>>();
  final paymentStarted = Completer<void>();
  int paymentCount = 0;

  @override
  Future<Result<Map<String, dynamic>>> payInvoice(String invoice) {
    paymentCount++;
    if (!paymentStarted.isCompleted) paymentStarted.complete();
    return payment.future;
  }

  @override
  Future<bool> hasConnection() async => true;

  @override
  Future<Result<int>> getBalance() async =>
      failBalance ? Result.error('Offline') : Result.success(42000);

  @override
  Future<Result<List<Map<String, dynamic>>>> listTransactions({
    int? limit,
    int? offset,
  }) async => Result.success([]);
}

class _Profiles implements ProfileRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Cashu extends CashuService {
  int balance = 50;

  @override
  Future<Result<CashuBalance>> getBalance() async =>
      Result.success(CashuBalance(totalSats: balance, mints: []));

  @override
  Future<Result<int>> meltAll({required String lightningTarget}) async {
    balance = 40;
    return Result.success(10);
  }
}

class _Sync implements SyncService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('partial Cashu melts retain and refresh the unspent balance', () async {
    final spark = SparkService();
    final bloc = WalletBloc(
      sparkService: spark,
      nwcService: _Nwc(),
      authService: AuthService.instance,
      profileRepository: _Profiles(),
      syncService: _Sync(),
      cashuService: _Cashu(),
    );
    addTearDown(spark.dispose);
    addTearDown(bloc.close);
    await bloc.stream.firstWhere((state) => state is WalletLoaded);
    final balance = bloc.stream.firstWhere(
      (state) => state is WalletLoaded && state.cashuBalanceSats == 50,
    );
    bloc.add(const WalletCashuBalanceRequested());
    await balance;
    final remaining = bloc.stream.firstWhere(
      (state) => state is WalletLoaded && state.cashuBalanceSats == 40,
    );
    bloc.add(
      const WalletCashuMeltAllRequested('alice@example.com'),
    );
    expect((await remaining as WalletLoaded).cashuRedeemedAmountSats, 10);
  });
  test('repeated payment requests cannot submit parallel payments', () async {
    final nwc = _Nwc();
    final spark = SparkService();
    final bloc = WalletBloc(
      sparkService: spark,
      nwcService: nwc,
      authService: AuthService.instance,
      profileRepository: _Profiles(),
      syncService: _Sync(),
    );
    addTearDown(spark.dispose);
    addTearDown(bloc.close);
    await bloc.stream.firstWhere((state) => state is WalletLoaded);
    bloc.add(const WalletPaymentRequested('invoice'));
    await nwc.paymentStarted.future;
    bloc.add(const WalletPaymentRequested('invoice'));
    await Future<void>.delayed(Duration.zero);
    expect(nwc.paymentCount, 1);
    nwc.payment.complete(Result.success({}));
    await Future<void>.delayed(Duration.zero);
  });
  test(
    'a successful balance refresh clears an earlier connection error',
    () async {
      final nwc = _Nwc();
      final spark = SparkService();
      final bloc = WalletBloc(
        sparkService: spark,
        nwcService: nwc,
        authService: AuthService.instance,
        profileRepository: _Profiles(),
        syncService: _Sync(),
      );
      addTearDown(spark.dispose);
      addTearDown(bloc.close);
      await bloc.stream.firstWhere(
        (state) => state is WalletLoaded && state.balanceError != null,
      );
      nwc.failBalance = false;
      final recovered = bloc.stream.firstWhere(
        (state) => state is WalletLoaded && state.balanceSats == 42,
      );
      bloc.add(const WalletBalanceRequested());
      expect((await recovered as WalletLoaded).balanceError, isNull);
    },
  );
}
