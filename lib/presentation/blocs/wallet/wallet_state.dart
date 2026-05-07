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
  final bool isConnected;
  final int? balanceSats;
  final List<Map<String, dynamic>>? transactions;
  final bool isLoadingTransactions;
  final bool isNwcMode;
  final String? lightningAddress;
  final String? balanceError;
  final String? watchedInvoice;
  final bool invoiceReceived;
  final bool isRedeemingCashu;
  final String? cashuRedeemError;
  final int? cashuRedeemedAmountSats;
  final int? cashuBalanceSats;

  const WalletLoaded({
    this.isConnected = false,
    this.balanceSats,
    this.transactions,
    this.isLoadingTransactions = false,
    this.isNwcMode = false,
    this.lightningAddress,
    this.balanceError,
    this.watchedInvoice,
    this.invoiceReceived = false,
    this.isRedeemingCashu = false,
    this.cashuRedeemError,
    this.cashuRedeemedAmountSats,
    this.cashuBalanceSats,
  });

  @override
  List<Object?> get props => [
        isConnected,
        balanceSats,
        transactions,
        isLoadingTransactions,
        isNwcMode,
        lightningAddress,
        balanceError,
        watchedInvoice,
        invoiceReceived,
        isRedeemingCashu,
        cashuRedeemError,
        cashuRedeemedAmountSats,
        cashuBalanceSats,
      ];

  WalletLoaded copyWith({
    bool? isConnected,
    int? balanceSats,
    List<Map<String, dynamic>>? transactions,
    bool? isLoadingTransactions,
    bool? isNwcMode,
    String? lightningAddress,
    bool clearLightningAddress = false,
    String? balanceError,
    bool clearBalanceError = false,
    String? watchedInvoice,
    bool clearWatchedInvoice = false,
    bool? invoiceReceived,
    bool? isRedeemingCashu,
    String? cashuRedeemError,
    bool clearCashuRedeemError = false,
    int? cashuRedeemedAmountSats,
    bool clearCashuRedeemedAmount = false,
    int? cashuBalanceSats,
    bool clearCashuBalance = false,
  }) {
    return WalletLoaded(
      isConnected: isConnected ?? this.isConnected,
      balanceSats: balanceSats ?? this.balanceSats,
      transactions: transactions ?? this.transactions,
      isLoadingTransactions:
          isLoadingTransactions ?? this.isLoadingTransactions,
      isNwcMode: isNwcMode ?? this.isNwcMode,
      lightningAddress: clearLightningAddress
          ? null
          : lightningAddress ?? this.lightningAddress,
      balanceError:
          clearBalanceError ? null : balanceError ?? this.balanceError,
      watchedInvoice:
          clearWatchedInvoice ? null : watchedInvoice ?? this.watchedInvoice,
      invoiceReceived: invoiceReceived ?? this.invoiceReceived,
      isRedeemingCashu: isRedeemingCashu ?? this.isRedeemingCashu,
      cashuRedeemError: clearCashuRedeemError
          ? null
          : cashuRedeemError ?? this.cashuRedeemError,
      cashuRedeemedAmountSats: clearCashuRedeemedAmount
          ? null
          : cashuRedeemedAmountSats ?? this.cashuRedeemedAmountSats,
      cashuBalanceSats: clearCashuBalance
          ? null
          : cashuBalanceSats ?? this.cashuBalanceSats,
    );
  }
}

class WalletError extends WalletState {
  final String message;

  const WalletError(this.message);

  @override
  List<Object?> get props => [message];
}
