import 'package:flutter/foundation.dart';
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
    required SparkService sparkService,
    required AuthService authService,
  })  : _sparkService = sparkService,
        _authService = authService,
        super(const OnboardingSparkInitial()) {
    on<OnboardingSparkWalletSetupRequested>(_onWalletSetupRequested);
    on<OnboardingSparkSkipped>(_onSkipped);
  }

  Future<void> _onWalletSetupRequested(
    OnboardingSparkWalletSetupRequested event,
    Emitter<OnboardingSparkState> emit,
  ) async {
    emit(const OnboardingSparkLoading());

    try {
      final npub = _authService.currentUserNpub;
      if (npub != null && npub.isNotEmpty) {
        _sparkService.setActiveAccount(npub);
      }

      final mnemonicResult = await _sparkService.getOrCreateMnemonic();

      if (mnemonicResult.isError) {
        emit(OnboardingSparkError(
            mnemonicResult.error ?? 'Failed to set up wallet'));
        return;
      }

      emit(const OnboardingSparkReady(shouldNavigate: true));
    } catch (e) {
      debugPrint('[OnboardingSparkBloc] Setup error: $e');
      emit(OnboardingSparkError('Wallet setup failed: $e'));
    }
  }

  void _onSkipped(
    OnboardingSparkSkipped event,
    Emitter<OnboardingSparkState> emit,
  ) {
    emit(const OnboardingSparkSkippedState());
  }
}
