import '../../../core/bloc/base/base_state.dart';

abstract class WalletState extends BaseState {
  const WalletState();
}

class WalletInitial extends WalletState {
  const WalletInitial();
}

class WalletLoading extends WalletState {
  const WalletLoading();
}

class WalletLoaded extends WalletState {
  final Map<String, dynamic>? user;
  final Map<String, dynamic>? balance;
  final List<Map<String, dynamic>>? transactions;
  final bool isLoadingTransactions;
  final double? btcPriceUsd;
  final bool isNwcMode;

  const WalletLoaded({
    this.user,
    this.balance,
    this.transactions,
    this.isLoadingTransactions = false,
    this.btcPriceUsd,
    this.isNwcMode = false,
  });

  @override
  List<Object?> get props =>
      [user, balance, transactions, isLoadingTransactions, btcPriceUsd, isNwcMode];

  WalletLoaded copyWith({
    Map<String, dynamic>? user,
    Map<String, dynamic>? balance,
    List<Map<String, dynamic>>? transactions,
    bool? isLoadingTransactions,
    double? btcPriceUsd,
    bool? isNwcMode,
  }) {
    return WalletLoaded(
      user: user ?? this.user,
      balance: balance ?? this.balance,
      transactions: transactions ?? this.transactions,
      isLoadingTransactions:
          isLoadingTransactions ?? this.isLoadingTransactions,
      btcPriceUsd: btcPriceUsd ?? this.btcPriceUsd,
      isNwcMode: isNwcMode ?? this.isNwcMode,
    );
  }
}

class WalletError extends WalletState {
  final String message;

  const WalletError(this.message);

  @override
  List<Object?> get props => [message];
}
