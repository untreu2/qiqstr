import 'package:flutter/foundation.dart';
import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../data/services/auth_service.dart';
import '../../../data/services/spark_service.dart';
import 'onboarding_spark_event.dart';
import 'onboarding_spark_state.dart';

class OnboardingSparkBloc
    extends Bloc<OnboardingSparkEvent, OnboardingSparkState> {
  final SparkService _sparkService;
  final AuthService _authService;

  OnboardingSparkBloc({
    required this._sparkService,
    required this._authService,
  })  : super(const OnboardingSparkInitial()) {
    on<OnboardingSparkEvent>((event, emit) async {
      switch (event) {
        case OnboardingSparkWalletSetupRequested():
          await _onWalletSetupRequested(event, emit);
        case OnboardingSparkRestoreRequested():
          await _onRestoreRequested(event, emit);
        case OnboardingSparkSkipped():
          _onSkipped(event, emit);
      }
    }, transformer: droppable());
  }

  Future<void> _onWalletSetupRequested(
    OnboardingSparkWalletSetupRequested event,
    Emitter<OnboardingSparkState> emit,
  ) async {
    emit(const OnboardingSparkLoading());

    try {
      final npub = _authService.currentUserNpub;
      if (npub == null || npub.isEmpty) {
        emit(const OnboardingSparkError('Not authenticated'));
        return;
      }
      _sparkService.setActiveAccount(npub);

      final mnemonicResult = await _sparkService.getOrCreateMnemonic();
      if (emit.isDone) return;

      if (mnemonicResult.isError) {
        emit(OnboardingSparkError(
            mnemonicResult.error ?? 'Failed to set up wallet'));
        return;
      }

      emit(const OnboardingSparkReady(shouldNavigate: true));
    } catch (e) {
      if (kDebugMode) debugPrint('[OnboardingSparkBloc] Setup error: $e');
      emit(OnboardingSparkError('Wallet setup failed: $e'));
    }
  }

  void _onSkipped(
    OnboardingSparkSkipped event,
    Emitter<OnboardingSparkState> emit,
  ) {
    emit(const OnboardingSparkSkippedState());
  }

  Future<void> _onRestoreRequested(
    OnboardingSparkRestoreRequested event,
    Emitter<OnboardingSparkState> emit,
  ) async {
    emit(const OnboardingSparkLoading());

    try {
      final npub = _authService.currentUserNpub;
      if (npub == null || npub.isEmpty) {
        emit(const OnboardingSparkError('Not authenticated'));
        return;
      }
      _sparkService.setActiveAccount(npub);

      final result = await _sparkService.restoreWallet(event.entropyHex);
      if (emit.isDone) return;

      if (result.isError) {
        emit(OnboardingSparkError(result.error ?? 'Failed to restore wallet'));
        return;
      }

      emit(const OnboardingSparkReady(shouldNavigate: true));
    } catch (e) {
      if (kDebugMode) debugPrint('[OnboardingSparkBloc] Restore error: $e');
      emit(OnboardingSparkError('Wallet restore failed: $e'));
    }
  }
}
