import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../data/repositories/profile_repository.dart';
import '../../../data/services/auth_service.dart';
import '../../../data/services/nwc_service.dart';
import '../../../data/services/spark_service.dart';
import '../../../data/sync/sync_service.dart';
import 'wallet_event.dart';
import 'wallet_state.dart';

class WalletBloc extends Bloc<WalletEvent, WalletState> {
  final SparkService _sparkService;
  final NwcService _nwcService;
  final AuthService _authService;
  final ProfileRepository _profileRepository;
  final SyncService _syncService;

  Timer? _balanceTimer;

  WalletBloc({
    required SparkService sparkService,
    required NwcService nwcService,
    required AuthService authService,
    required ProfileRepository profileRepository,
    required SyncService syncService,
  })  : _sparkService = sparkService,
        _nwcService = nwcService,
        _authService = authService,
        _profileRepository = profileRepository,
        _syncService = syncService,
        super(const WalletInitial()) {
    on<WalletInitialized>(_onWalletInitialized);
    on<WalletBalanceRequested>(_onWalletBalanceRequested);
    on<WalletPaymentRequested>(_onWalletPaymentRequested);
    on<WalletInvoiceGenerated>(_onWalletInvoiceGenerated);
    on<WalletTransactionsLoaded>(_onWalletTransactionsLoaded);
    on<WalletLightningAddressRequested>(_onWalletLightningAddressRequested);
    on<WalletLightningAddressRegistered>(_onWalletLightningAddressRegistered);

    add(const WalletInitialized());
  }

  Future<void> _onWalletInitialized(
    WalletInitialized event,
    Emitter<WalletState> emit,
  ) async {
    emit(const WalletLoading());

    final hasNwcConnection = await _nwcService.hasConnection();

    if (hasNwcConnection) {
      emit(const WalletLoaded(isConnected: true, isNwcMode: true));
      add(const WalletBalanceRequested());
      add(const WalletTransactionsLoaded());
      _startBalanceTimer();
      return;
    }

    final isConnectedResult = await _sparkService.isConnected();
    final isConnected =
        isConnectedResult.isSuccess && isConnectedResult.data == true;

    emit(WalletLoaded(isConnected: isConnected));

    if (isConnected) {
      add(const WalletBalanceRequested());
      add(const WalletTransactionsLoaded());
      add(const WalletLightningAddressRequested());
      _startBalanceTimer();
    }
  }

  Future<void> _onWalletBalanceRequested(
    WalletBalanceRequested event,
    Emitter<WalletState> emit,
  ) async {
    if (state is WalletLoaded && (state as WalletLoaded).isNwcMode) {
      final result = await _nwcService.getBalance();
      result.fold(
        (balanceMsat) {
          if (state is WalletLoaded) {
            emit((state as WalletLoaded).copyWith(
              balanceSats: balanceMsat ~/ 1000,
            ));
          }
        },
        (error) => debugPrint('[WalletBloc] NWC balance error: $error'),
      );
      return;
    }

    final result = await _sparkService.getBalance();
    result.fold(
      (balanceSats) {
        if (state is WalletLoaded) {
          emit((state as WalletLoaded).copyWith(
            isConnected: true,
            balanceSats: balanceSats,
          ));
        } else {
          emit(WalletLoaded(isConnected: true, balanceSats: balanceSats));
        }
      },
      (error) => debugPrint('[WalletBloc] Spark balance error: $error'),
    );
  }

  Future<void> _onWalletPaymentRequested(
    WalletPaymentRequested event,
    Emitter<WalletState> emit,
  ) async {
    if (state is WalletLoaded && (state as WalletLoaded).isNwcMode) {
      final result = await _nwcService.payInvoice(event.invoice);
      result.fold(
        (_) => add(const WalletBalanceRequested()),
        (error) => emit(WalletError('Payment failed: $error')),
      );
      return;
    }

    final result = await _sparkService.payLightningInvoice(event.invoice);
    result.fold(
      (_) => add(const WalletBalanceRequested()),
      (error) => emit(WalletError('Payment failed: $error')),
    );
  }

  Future<void> _onWalletInvoiceGenerated(
    WalletInvoiceGenerated event,
    Emitter<WalletState> emit,
  ) async {
    if (event.amount <= 0) {
      emit(const WalletError('Amount must be greater than 0'));
      return;
    }

    if (state is WalletLoaded && (state as WalletLoaded).isNwcMode) {
      final result = await _nwcService.makeInvoice(amountSats: event.amount);
      result.fold(
        (_) {},
        (error) => emit(WalletError('Invoice generation failed: $error')),
      );
      return;
    }

    final result = await _sparkService.createLightningInvoice(
      amountSats: event.amount,
    );
    result.fold(
      (_) {},
      (error) => emit(WalletError('Invoice generation failed: $error')),
    );
  }

  Future<void> _onWalletTransactionsLoaded(
    WalletTransactionsLoaded event,
    Emitter<WalletState> emit,
  ) async {
    if (state is WalletLoaded) {
      emit((state as WalletLoaded).copyWith(isLoadingTransactions: true));
    }

    if (state is WalletLoaded && (state as WalletLoaded).isNwcMode) {
      final result = await _nwcService.listTransactions(limit: 20);
      result.fold(
        (transactions) {
          if (state is WalletLoaded) {
            emit((state as WalletLoaded).copyWith(
              transactions: transactions,
              isLoadingTransactions: false,
            ));
          }
        },
        (error) {
          debugPrint('[WalletBloc] NWC transactions error: $error');
          if (state is WalletLoaded) {
            emit((state as WalletLoaded)
                .copyWith(isLoadingTransactions: false));
          }
        },
      );
      return;
    }

    final result = await _sparkService.listPayments(limit: 20);
    result.fold(
      (transactions) {
        if (state is WalletLoaded) {
          emit((state as WalletLoaded).copyWith(
            transactions: transactions,
            isLoadingTransactions: false,
          ));
        } else {
          emit(WalletLoaded(
            isConnected: true,
            transactions: transactions,
            isLoadingTransactions: false,
          ));
        }
      },
      (error) {
        if (state is WalletLoaded) {
          emit((state as WalletLoaded).copyWith(isLoadingTransactions: false));
        }
      },
    );
  }

  Future<void> _onWalletLightningAddressRequested(
    WalletLightningAddressRequested event,
    Emitter<WalletState> emit,
  ) async {
    final result = await _sparkService.getLightningAddress();
    result.fold(
      (address) {
        if (state is WalletLoaded) {
          emit((state as WalletLoaded).copyWith(lightningAddress: address));
        }
      },
      (error) => debugPrint('[WalletBloc] LN address error: $error'),
    );
  }

  Future<void> _onWalletLightningAddressRegistered(
    WalletLightningAddressRegistered event,
    Emitter<WalletState> emit,
  ) async {
    final result =
        await _sparkService.registerLightningAddress(event.username);
    await result.fold(
      (address) async {
        if (state is WalletLoaded) {
          emit((state as WalletLoaded).copyWith(lightningAddress: address));
        }
        await _publishLud16ToProfile(address);
      },
      (error) async =>
          emit(WalletError('Failed to register address: $error')),
    );
  }

  Future<void> _publishLud16ToProfile(String lud16) async {
    try {
      final pubkeyResult = await _authService.getCurrentUserPublicKeyHex();
      if (pubkeyResult.isError || pubkeyResult.data == null) return;

      final pubkeyHex = pubkeyResult.data!;
      var existingProfile =
          await _profileRepository.getProfile(pubkeyHex);

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
      debugPrint('[WalletBloc] Published lud16 to Nostr profile: $lud16');
    } catch (e) {
      debugPrint('[WalletBloc] Failed to publish lud16 to profile: $e');
    }
  }

  void _startBalanceTimer() {
    _balanceTimer?.cancel();
    _balanceTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      add(const WalletBalanceRequested());
    });
  }

  @override
  Future<void> close() {
    _balanceTimer?.cancel();
    return super.close();
  }
}
