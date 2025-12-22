import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../core/base/base_view_model.dart';
import '../../data/repositories/wallet_repository.dart';
import '../../models/wallet_model.dart';

class WalletViewModel extends BaseViewModel {
  final WalletRepository _walletRepository;

  WalletViewModel({
    required WalletRepository walletRepository,
  }) : _walletRepository = walletRepository;

  CoinosUser? _user;
  CoinosBalance? _balance;
  List<CoinosPayment>? _transactions;
  bool _isConnecting = false;
  bool _isLoadingTransactions = false;
  String? _error;
  Timer? _balanceTimer;
  bool _isInitialized = false;

  CoinosUser? get user => _user;
  CoinosBalance? get balance => _balance;
  List<CoinosPayment>? get transactions => _transactions;
  bool get isConnecting => _isConnecting;
  bool get isLoadingTransactions => _isLoadingTransactions;
  String? get error => _error;
  bool get isInitialized => _isInitialized;

  @override
  void initialize() {
    super.initialize();
    _autoConnect();
  }

  Future<void> _autoConnect() async {
    final result = await _walletRepository.autoConnect();
    result.fold(
      (user) {
        if (user != null) {
          _user = user;
          _isInitialized = true;
          safeNotifyListeners();
          _getBalance();
          _getTransactions();
          _startBalanceTimer();
        } else {
          _isInitialized = true;
          safeNotifyListeners();
        }
      },
      (error) {
        _isInitialized = true;
        safeNotifyListeners();
      },
    );
  }

  Future<void> _getBalance() async {
    final result = await _walletRepository.getBalance();

    result.fold(
      (balance) {
        _balance = balance;
        _error = null;
        safeNotifyListeners();
      },
      (error) {
        _error = 'Failed to get balance: $error';
        safeNotifyListeners();
      },
    );
  }

  Future<void> _getTransactions() async {
    _isLoadingTransactions = true;
    safeNotifyListeners();

    final result = await _walletRepository.listTransactions();

    result.fold(
      (transactions) {
        _transactions = transactions;
        _isLoadingTransactions = false;
        safeNotifyListeners();
      },
      (error) {
        _isLoadingTransactions = false;
        debugPrint('Failed to get transactions: $error');
        safeNotifyListeners();
      },
    );
  }

  void _startBalanceTimer() {
    _balanceTimer?.cancel();

    _balanceTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (_user != null && !isDisposed) {
        _getBalance();
      }
    });
  }

  void _stopBalanceTimer() {
    _balanceTimer?.cancel();
    _balanceTimer = null;
  }

  Future<void> connectWithNostr() async {
    _isConnecting = true;
    _error = null;
    safeNotifyListeners();

    try {
      final result = await _walletRepository.authenticateWithNostr();

      result.fold(
        (user) {
          _user = user;
          _isConnecting = false;
          safeNotifyListeners();
          _getBalance();
          _getTransactions();
          _startBalanceTimer();
        },
        (error) {
          _error = error;
          _isConnecting = false;
          safeNotifyListeners();
        },
      );
    } catch (e) {
      _error = 'Failed to connect: $e';
      _isConnecting = false;
      safeNotifyListeners();
    }
  }

  Future<void> refreshBalance() async {
    await _getBalance();
  }

  Future<void> refreshTransactions() async {
    await _getTransactions();
  }

  String? getCoinosLud16() {
    return _user?.lud16;
  }

  void onPaymentSuccess() {
    _getBalance();
    _getTransactions();
  }

  @override
  void dispose() {
    _stopBalanceTimer();
    super.dispose();
  }
}

