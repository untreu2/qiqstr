import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../data/services/coinos_service.dart';
import '../../../data/services/nwc_service.dart';
import 'wallet_event.dart';
import 'wallet_state.dart';

class WalletBloc extends Bloc<WalletEvent, WalletState> {
  final CoinosService _coinosService;
  final NwcService _nwcService;

  Timer? _balanceTimer;
  final List<StreamSubscription> _subscriptions = [];

  WalletBloc({
    required CoinosService coinosService,
    required NwcService nwcService,
  })  : _coinosService = coinosService,
        _nwcService = nwcService,
        super(const WalletInitial()) {
    on<WalletAutoConnectRequested>(_onWalletAutoConnectRequested);
    on<WalletConnectWithNostrRequested>(_onWalletConnectWithNostrRequested);
    on<WalletBalanceRequested>(_onWalletBalanceRequested);
    on<WalletPaymentRequested>(_onWalletPaymentRequested);
    on<WalletInvoiceGenerated>(_onWalletInvoiceGenerated);
    on<WalletTransactionsLoaded>(_onWalletTransactionsLoaded);
    on<WalletPriceRequested>(_onWalletPriceRequested);
    on<WalletApiKeySet>(_onWalletApiKeySet);

    add(const WalletAutoConnectRequested());
    add(const WalletPriceRequested());
  }

  Future<void> _onWalletAutoConnectRequested(
    WalletAutoConnectRequested event,
    Emitter<WalletState> emit,
  ) async {
    emit(const WalletLoading());

    final hasNwcConnection = await _nwcService.hasConnection();

    if (hasNwcConnection) {
      emit(const WalletLoaded(
        user: {'username': 'NWC', 'id': 'nwc'},
        isNwcMode: true,
      ));
      add(const WalletBalanceRequested());
      add(const WalletTransactionsLoaded());
      add(const WalletPriceRequested());
      _startBalanceTimer(emit);
      return;
    }

    final isAuthResult = await _coinosService.isAuthenticated();
    if (isAuthResult.isSuccess && isAuthResult.data == true) {
      final userResult = await _coinosService.getStoredUser();
      if (userResult.isSuccess && userResult.data != null) {
        emit(WalletLoaded(user: userResult.data));
        add(const WalletBalanceRequested());
        add(const WalletTransactionsLoaded());
        add(const WalletPriceRequested());
        _startBalanceTimer(emit);
        return;
      }
    }

    if (event.recaptchaToken == null) {
      emit(const WalletLoaded());
      return;
    }

    final authResult =
        await _coinosService.autoLogin(recaptchaToken: event.recaptchaToken);
    authResult.fold(
      (data) {
        final user = data['user'] as Map<String, dynamic>?;
        if (user != null) {
          emit(WalletLoaded(user: user));
          add(const WalletBalanceRequested());
          add(const WalletTransactionsLoaded());
          _startBalanceTimer(emit);
        } else {
          emit(const WalletLoaded());
        }
      },
      (error) => emit(WalletError(error)),
    );
  }

  Future<void> _onWalletConnectWithNostrRequested(
    WalletConnectWithNostrRequested event,
    Emitter<WalletState> emit,
  ) async {
    emit(const WalletLoading());

    final result = await _coinosService.authenticateWithNostr(
      recaptchaToken: event.recaptchaToken,
    );

    result.fold(
      (data) {
        final user = data['user'] as Map<String, dynamic>?;
        emit(WalletLoaded(user: user));
        add(const WalletBalanceRequested());
        add(const WalletTransactionsLoaded());
        _startBalanceTimer(emit);
      },
      (error) => emit(WalletError(error)),
    );
  }

  Future<void> _onWalletBalanceRequested(
    WalletBalanceRequested event,
    Emitter<WalletState> emit,
  ) async {
    if (state is WalletLoaded && (state as WalletLoaded).isNwcMode) {
      final result = await _nwcService.getBalance();
      result.fold(
        (balanceMsat) {
          final balanceSats = balanceMsat ~/ 1000;
          if (state is WalletLoaded) {
            final currentState = state as WalletLoaded;
            emit(currentState.copyWith(
              balance: {'balance': balanceSats},
            ));
          }
        },
        (error) {
          debugPrint('[WalletBloc] NWC balance error: $error');
        },
      );
      return;
    }

    final result = await _coinosService.getBalance();
    result.fold(
      (data) {
        if (state is WalletLoaded) {
          final currentState = state as WalletLoaded;
          emit(currentState.copyWith(balance: data));
        } else {
          emit(WalletLoaded(balance: data));
        }
      },
      (error) => emit(WalletError('Failed to get balance: $error')),
    );
  }

  Future<void> _onWalletPaymentRequested(
    WalletPaymentRequested event,
    Emitter<WalletState> emit,
  ) async {
    if (state is WalletLoaded && (state as WalletLoaded).isNwcMode) {
      final result = await _nwcService.payInvoice(event.invoice);
      result.fold(
        (_) {
          add(const WalletBalanceRequested());
        },
        (error) => emit(WalletError('Payment failed: $error')),
      );
      return;
    }

    final result = await _coinosService.payInvoice(event.invoice);
    result.fold(
      (_) {
        add(const WalletBalanceRequested());
      },
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

    final result = await _coinosService.createInvoice(
      amount: event.amount,
      type: 'lightning',
    );

    result.fold(
      (invoice) {
        if (kDebugMode) {
          print('[WalletBloc] Invoice created');
        }
      },
      (error) => emit(WalletError('Invoice generation failed: $error')),
    );
  }

  Future<void> _onWalletTransactionsLoaded(
    WalletTransactionsLoaded event,
    Emitter<WalletState> emit,
  ) async {
    if (state is WalletLoaded) {
      final currentState = state as WalletLoaded;
      emit(currentState.copyWith(isLoadingTransactions: true));
    }

    if (state is WalletLoaded && (state as WalletLoaded).isNwcMode) {
      final result = await _nwcService.listTransactions(limit: 20);
      result.fold(
        (transactions) {
          if (state is WalletLoaded) {
            final currentState = state as WalletLoaded;
            emit(currentState.copyWith(
              transactions: transactions,
              isLoadingTransactions: false,
            ));
          }
        },
        (error) {
          debugPrint('[WalletBloc] NWC transactions error: $error');
          if (state is WalletLoaded) {
            final currentState = state as WalletLoaded;
            emit(currentState.copyWith(isLoadingTransactions: false));
          }
        },
      );
      return;
    }

    final result = await _coinosService.getPaymentHistory();

    result.fold(
      (transactions) {
        if (state is WalletLoaded) {
          final currentState = state as WalletLoaded;
          emit(currentState.copyWith(
            transactions: transactions,
            isLoadingTransactions: false,
          ));
        } else {
          emit(WalletLoaded(
              transactions: transactions, isLoadingTransactions: false));
        }
      },
      (error) {
        if (state is WalletLoaded) {
          final currentState = state as WalletLoaded;
          emit(currentState.copyWith(isLoadingTransactions: false));
        }
      },
    );
  }

  Future<void> _onWalletPriceRequested(
    WalletPriceRequested event,
    Emitter<WalletState> emit,
  ) async {
    final result = await _coinosService.fetchBtcPrice();
    result.fold(
      (price) {
        if (state is WalletLoaded) {
          final currentState = state as WalletLoaded;
          emit(currentState.copyWith(btcPriceUsd: price));
        } else {
          emit(WalletLoaded(btcPriceUsd: price));
        }
      },
      (_) {},
    );
  }

  Future<void> _onWalletApiKeySet(
    WalletApiKeySet event,
    Emitter<WalletState> emit,
  ) async {
    final result = await _coinosService.setApiKey(event.apiKey);
    result.fold(
      (_) {
        debugPrint('[WalletBloc] API key stored');
        add(const WalletAutoConnectRequested());
      },
      (error) => emit(WalletError('Failed to set API key: $error')),
    );
  }

  void _startBalanceTimer(Emitter<WalletState> emit) {
    _balanceTimer?.cancel();

    _balanceTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      add(const WalletBalanceRequested());
      add(const WalletPriceRequested());
    });
  }

  @override
  Future<void> close() {
    _balanceTimer?.cancel();
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _subscriptions.clear();
    return super.close();
  }
}
