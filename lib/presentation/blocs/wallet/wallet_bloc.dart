import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../data/repositories/wallet_repository.dart';
import 'wallet_event.dart';
import 'wallet_state.dart';

class WalletBloc extends Bloc<WalletEvent, WalletState> {
  final WalletRepository _walletRepository;

  Timer? _balanceTimer;
  final List<StreamSubscription> _subscriptions = [];

  WalletBloc({
    required WalletRepository walletRepository,
  })  : _walletRepository = walletRepository,
        super(const WalletInitial()) {
    on<WalletAutoConnectRequested>(_onWalletAutoConnectRequested);
    on<WalletConnectWithNostrRequested>(_onWalletConnectWithNostrRequested);
    on<WalletBalanceRequested>(_onWalletBalanceRequested);
    on<WalletPaymentRequested>(_onWalletPaymentRequested);
    on<WalletInvoiceGenerated>(_onWalletInvoiceGenerated);
    on<WalletTransactionsLoaded>(_onWalletTransactionsLoaded);

    add(const WalletAutoConnectRequested());
  }

  Future<void> _onWalletAutoConnectRequested(
    WalletAutoConnectRequested event,
    Emitter<WalletState> emit,
  ) async {
    emit(const WalletLoading());

    final result = await _walletRepository.autoConnect();

    result.fold(
      (user) {
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

    final result = await _walletRepository.authenticateWithNostr();

    result.fold(
      (user) {
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
    final result = await _walletRepository.getBalance();

    result.fold(
      (balance) {
        if (state is WalletLoaded) {
          final currentState = state as WalletLoaded;
          emit(currentState.copyWith(balance: balance));
        } else {
          emit(WalletLoaded(balance: balance));
        }
      },
      (error) => emit(WalletError('Failed to get balance: $error')),
    );
  }

  Future<void> _onWalletPaymentRequested(
    WalletPaymentRequested event,
    Emitter<WalletState> emit,
  ) async {
    final result = await _walletRepository.payInvoice(event.invoice);

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
    final result = await _walletRepository.makeInvoice(event.amount, '');

    result.fold(
      (invoice) {},
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

    final result = await _walletRepository.listTransactions();

    result.fold(
      (transactions) {
        if (state is WalletLoaded) {
          final currentState = state as WalletLoaded;
          emit(currentState.copyWith(
            transactions: transactions,
            isLoadingTransactions: false,
          ));
        } else {
          emit(WalletLoaded(transactions: transactions, isLoadingTransactions: false));
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

  void _startBalanceTimer(Emitter<WalletState> emit) {
    _balanceTimer?.cancel();

    _balanceTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      add(const WalletBalanceRequested());
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
