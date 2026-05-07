import 'dart:async';

import 'package:breez_sdk_spark_flutter/breez_sdk_spark.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../data/repositories/profile_repository.dart';
import '../../../data/services/auth_service.dart';
import '../../../data/services/cashu_service.dart';
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
  final CashuService _cashuService;

  Timer? _balanceTimer;
  StreamSubscription<SdkEvent>? _sdkEventSubscription;

  WalletBloc({
    required SparkService sparkService,
    required NwcService nwcService,
    required AuthService authService,
    required ProfileRepository profileRepository,
    required SyncService syncService,
    CashuService? cashuService,
  })  : _sparkService = sparkService,
        _nwcService = nwcService,
        _authService = authService,
        _profileRepository = profileRepository,
        _syncService = syncService,
        _cashuService = cashuService ?? const CashuService(),
        super(const WalletInitial()) {
    on<WalletInitialized>(_onWalletInitialized);
    on<WalletBalanceRequested>(_onWalletBalanceRequested);
    on<WalletPaymentRequested>(_onWalletPaymentRequested);
    on<WalletTransactionsLoaded>(_onWalletTransactionsLoaded);
    on<WalletLightningAddressRequested>(_onWalletLightningAddressRequested);
    on<WalletLightningAddressRegistered>(_onWalletLightningAddressRegistered);
    on<WalletInvoiceWatched>(_onWalletInvoiceWatched);
    on<WalletInvoiceCleared>(_onWalletInvoiceCleared);
    on<WalletPaymentReceivedEvent>(_onWalletPaymentReceivedEvent);
    on<WalletSdkSyncedEvent>(_onWalletSdkSyncedEvent);
    on<WalletCashuTokenRedeemRequested>(_onCashuTokenRedeemRequested);
    on<WalletCashuBalanceRequested>(_onCashuBalanceRequested);
    on<WalletCashuMeltAllRequested>(_onCashuMeltAllRequested);

    add(const WalletInitialized());
  }

  Future<void> _onWalletInitialized(
    WalletInitialized event,
    Emitter<WalletState> emit,
  ) async {
    emit(const WalletLoading());

    final hasNwcConnection = await _nwcService.hasConnection();
    if (isClosed) return;

    if (hasNwcConnection) {
      emit(const WalletLoaded(isConnected: true, isNwcMode: true));
      if (isClosed) return;
      add(const WalletBalanceRequested());
      add(const WalletTransactionsLoaded());
      _startBalanceTimer();
      return;
    }

    final isConnectedResult = await _sparkService.isConnected();
    if (isClosed) return;
    final isConnected =
        isConnectedResult.isSuccess && isConnectedResult.data == true;

    emit(WalletLoaded(isConnected: isConnected));

    if (isConnected) {
      if (isClosed) return;
      add(const WalletBalanceRequested());
      add(const WalletTransactionsLoaded());
      add(const WalletLightningAddressRequested());
      add(const WalletCashuBalanceRequested());
      _startBalanceTimer();
      _subscribeSdkEvents();
    }
  }

  void _subscribeSdkEvents() {
    _sdkEventSubscription?.cancel();
    _sdkEventSubscription = _sparkService.eventStream.listen(
      (event) {
        if (isClosed) return;
        switch (event) {
          case SdkEvent_PaymentSucceeded(:final payment):
            final paymentMap = _paymentToMap(payment);
            add(WalletPaymentReceivedEvent(paymentMap));
          case SdkEvent_PaymentPending(:final payment):
            final paymentMap = _paymentToMap(payment);
            add(WalletPaymentReceivedEvent(paymentMap));
          case SdkEvent_PaymentFailed():
            add(const WalletTransactionsLoaded());
          case SdkEvent_Synced():
            add(const WalletSdkSyncedEvent());
          default:
            break;
        }
      },
      onError: (e) => debugPrint('[WalletBloc] SDK event error: $e'),
    );
  }

  Map<String, dynamic> _paymentToMap(Payment payment) {
    return {
      'id': payment.id,
      'isIncoming': payment.paymentType == PaymentType.receive,
      'amount': payment.amount.toInt(),
      'timestamp': payment.timestamp.toInt(),
      'status': payment.status.name,
    };
  }

  Future<void> _onWalletPaymentReceivedEvent(
    WalletPaymentReceivedEvent event,
    Emitter<WalletState> emit,
  ) async {
    if (state is! WalletLoaded) return;
    final current = state as WalletLoaded;

    final isIncoming = event.payment['isIncoming'] == true;
    final paymentId = event.payment['id'] as String?;
    final paymentStatus = event.payment['status'] as String?;

    final isInvoiceMatch = current.watchedInvoice != null &&
        isIncoming &&
        paymentStatus == 'completed';

    final existingTxs = current.transactions ?? [];
    final idx = existingTxs.indexWhere((t) => t['id'] == paymentId);
    List<Map<String, dynamic>> updatedTxs;
    if (idx >= 0) {
      updatedTxs = List.from(existingTxs);
      updatedTxs[idx] = event.payment;
    } else {
      updatedTxs = [event.payment, ...existingTxs];
    }

    emit(current.copyWith(
      transactions: updatedTxs,
      invoiceReceived: isInvoiceMatch ? true : current.invoiceReceived,
    ));

    add(const WalletBalanceRequested());
  }

  Future<void> _onWalletSdkSyncedEvent(
    WalletSdkSyncedEvent event,
    Emitter<WalletState> emit,
  ) async {
    add(const WalletBalanceRequested());
    add(const WalletTransactionsLoaded());
  }

  Future<void> _onWalletInvoiceWatched(
    WalletInvoiceWatched event,
    Emitter<WalletState> emit,
  ) async {
    if (state is WalletLoaded) {
      emit((state as WalletLoaded).copyWith(
        watchedInvoice: event.invoice,
        invoiceReceived: false,
      ));
    }
  }

  Future<void> _onWalletInvoiceCleared(
    WalletInvoiceCleared event,
    Emitter<WalletState> emit,
  ) async {
    if (state is WalletLoaded) {
      emit((state as WalletLoaded).copyWith(
        clearWatchedInvoice: true,
        invoiceReceived: false,
      ));
    }
  }

  Future<void> _onWalletBalanceRequested(
    WalletBalanceRequested event,
    Emitter<WalletState> emit,
  ) async {
    if (state is WalletLoaded && (state as WalletLoaded).isNwcMode) {
      final result = await _nwcService.getBalance();
      if (isClosed) return;
      result.fold(
        (balanceMsat) {
          if (state is WalletLoaded) {
            emit((state as WalletLoaded).copyWith(
              balanceSats: balanceMsat ~/ 1000,
              balanceError: null,
            ));
          }
        },
        (error) {
          debugPrint('[WalletBloc] NWC balance error: $error');
          if (state is WalletLoaded) {
            emit((state as WalletLoaded).copyWith(balanceError: error));
          }
        },
      );
      return;
    }

    final result = await _sparkService.getBalance();
    if (isClosed) return;
    result.fold(
      (balanceSats) {
        if (state is WalletLoaded) {
          emit((state as WalletLoaded).copyWith(
            isConnected: true,
            balanceSats: balanceSats,
            balanceError: null,
          ));
        } else {
          emit(WalletLoaded(isConnected: true, balanceSats: balanceSats));
        }
      },
      (error) {
        debugPrint('[WalletBloc] Spark balance error: $error');
        if (state is WalletLoaded) {
          emit((state as WalletLoaded).copyWith(balanceError: error));
        }
      },
    );
  }

  Future<void> _onWalletPaymentRequested(
    WalletPaymentRequested event,
    Emitter<WalletState> emit,
  ) async {
    if (state is WalletLoaded && (state as WalletLoaded).isNwcMode) {
      final result = await _nwcService.payInvoice(event.invoice);
      if (isClosed) return;
      result.fold(
        (_) {
          add(const WalletBalanceRequested());
          add(const WalletTransactionsLoaded());
        },
        (error) => emit(WalletError('Payment failed: $error')),
      );
      return;
    }

    final result = await _sparkService.payLightningInvoice(event.invoice);
    if (isClosed) return;
    result.fold(
      (_) {
        add(const WalletBalanceRequested());
        add(const WalletTransactionsLoaded());
      },
      (error) => emit(WalletError('Payment failed: $error')),
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
      if (isClosed) return;
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
    if (isClosed) return;
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
    if (isClosed) return;
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
    if (isClosed) return;
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

  Future<void> _onCashuTokenRedeemRequested(
    WalletCashuTokenRedeemRequested event,
    Emitter<WalletState> emit,
  ) async {
    if (state is! WalletLoaded) return;
    final current = state as WalletLoaded;

    emit(current.copyWith(
      isRedeemingCashu: true,
      clearCashuRedeemError: true,
      clearCashuRedeemedAmount: true,
    ));

    final result = await _cashuService.receiveAndMelt(
      token: event.token,
      lightningTarget: event.lightningTarget,
    );

    if (isClosed) return;

    result.fold(
      (amountSats) {
        if (state is WalletLoaded) {
          emit((state as WalletLoaded).copyWith(
            isRedeemingCashu: false,
            cashuRedeemedAmountSats: amountSats,
          ));
          add(const WalletBalanceRequested());
          add(const WalletTransactionsLoaded());
          add(const WalletCashuBalanceRequested());
        }
      },
      (error) {
        if (state is WalletLoaded) {
          emit((state as WalletLoaded).copyWith(
            isRedeemingCashu: false,
            cashuRedeemError: error,
          ));
        }
      },
    );
  }

  Future<void> _onCashuMeltAllRequested(
    WalletCashuMeltAllRequested event,
    Emitter<WalletState> emit,
  ) async {
    if (state is! WalletLoaded) return;
    final current = state as WalletLoaded;

    emit(current.copyWith(
      isRedeemingCashu: true,
      clearCashuRedeemError: true,
      clearCashuRedeemedAmount: true,
    ));

    final result = await _cashuService.meltAll(
      lightningTarget: event.lightningTarget,
    );

    if (isClosed) return;

    result.fold(
      (totalSats) {
        if (state is WalletLoaded) {
          emit((state as WalletLoaded).copyWith(
            isRedeemingCashu: false,
            cashuRedeemedAmountSats: totalSats,
            cashuBalanceSats: 0,
          ));
          add(const WalletBalanceRequested());
          add(const WalletTransactionsLoaded());
        }
      },
      (error) {
        if (state is WalletLoaded) {
          emit((state as WalletLoaded).copyWith(
            isRedeemingCashu: false,
            cashuRedeemError: error,
          ));
        }
      },
    );
  }

  Future<void> _onCashuBalanceRequested(
    WalletCashuBalanceRequested event,
    Emitter<WalletState> emit,
  ) async {
    final result = await _cashuService.getBalance();
    if (isClosed) return;
    result.fold(
      (balance) {
        if (state is WalletLoaded) {
          emit((state as WalletLoaded).copyWith(
            cashuBalanceSats: balance.totalSats,
          ));
        }
      },
      (_) {},
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
      if (!isClosed) add(const WalletBalanceRequested());
    });
  }

  @override
  Future<void> close() {
    _balanceTimer?.cancel();
    _sdkEventSubscription?.cancel();
    return super.close();
  }
}
