import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../data/services/coinos_service.dart';
import '../../../data/services/auth_service.dart';
import '../../../data/repositories/profile_repository.dart';
import '../../../data/sync/sync_service.dart';
import 'onboarding_coinos_event.dart';
import 'onboarding_coinos_state.dart';

class OnboardingCoinosBloc
    extends Bloc<OnboardingCoinosEvent, OnboardingCoinosState> {
  final CoinosService _coinosService;
  final AuthService _authService;
  final ProfileRepository _profileRepository;
  final SyncService _syncService;

  OnboardingCoinosBloc({
    required CoinosService coinosService,
    required AuthService authService,
    required ProfileRepository profileRepository,
    required SyncService syncService,
  })  : _coinosService = coinosService,
        _authService = authService,
        _profileRepository = profileRepository,
        _syncService = syncService,
        super(const OnboardingCoinosInitial()) {
    on<OnboardingCoinosConnectRequested>(_onConnectRequested);
    on<OnboardingCoinosSkipped>(_onSkipped);
  }

  Future<void> _onConnectRequested(
    OnboardingCoinosConnectRequested event,
    Emitter<OnboardingCoinosState> emit,
  ) async {
    emit(const OnboardingCoinosLoading());

    try {
      final authResult = await _coinosService.authenticateWithNostr(
        recaptchaToken: event.recaptchaToken,
      );

      if (authResult.isError) {
        emit(
            OnboardingCoinosError(authResult.error ?? 'Authentication failed'));
        return;
      }

      final data = authResult.data!;
      final user = data['user'] as Map<String, dynamic>?;
      final username = (user?['username'] as String? ?? '').replaceAll(' ', '');

      if (username.isEmpty) {
        emit(const OnboardingCoinosError('Failed to get Coinos username'));
        return;
      }

      final lud16 = '$username@coinos.io';
      await _publishLud16Update(lud16);

      emit(OnboardingCoinosConnected(
        username: username,
        shouldNavigate: true,
      ));
    } catch (e) {
      debugPrint('[OnboardingCoinosBloc] Connect error: $e');
      emit(OnboardingCoinosError('Connection failed: $e'));
    }
  }

  Future<void> _publishLud16Update(String lud16) async {
    final pubkeyResult = await _authService.getCurrentUserPublicKeyHex();
    if (pubkeyResult.isError || pubkeyResult.data == null) return;

    final pubkeyHex = pubkeyResult.data!;
    var existingProfile = await _profileRepository.getProfile(pubkeyHex);

    if (existingProfile == null) {
      await _syncService.syncProfile(pubkeyHex);
      existingProfile = await _profileRepository.getProfile(pubkeyHex);
    }

    final profile = <String, dynamic>{
      'name': existingProfile?.name ?? '',
      'display_name': existingProfile?.displayName ?? '',
      'about': existingProfile?.about ?? '',
      'picture': existingProfile?.picture ?? '',
      'banner': existingProfile?.banner ?? '',
      'nip05': existingProfile?.nip05 ?? '',
      'lud16': lud16,
      'website': existingProfile?.website ?? '',
      if ((existingProfile?.location ?? '').isNotEmpty)
        'location': existingProfile!.location!,
    };

    await _syncService.publishProfileUpdate(profileContent: profile);
  }

  void _onSkipped(
    OnboardingCoinosSkipped event,
    Emitter<OnboardingCoinosState> emit,
  ) {
    emit(const OnboardingCoinosSkippedState());
  }
}
