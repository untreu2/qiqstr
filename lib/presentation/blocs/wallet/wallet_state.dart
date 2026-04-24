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

  const WalletLoaded({
    this.isConnected = false,
    this.balanceSats,
    this.transactions,
    this.isLoadingTransactions = false,
    this.isNwcMode = false,
    this.lightningAddress,
  });

  @override
  List<Object?> get props => [
        isConnected,
        balanceSats,
        transactions,
        isLoadingTransactions,
        isNwcMode,
        lightningAddress,
      ];

  WalletLoaded copyWith({
    bool? isConnected,
    int? balanceSats,
    List<Map<String, dynamic>>? transactions,
    bool? isLoadingTransactions,
    bool? isNwcMode,
    String? lightningAddress,
    bool clearLightningAddress = false,
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
    );
  }
}

class WalletError extends WalletState {
  final String message;

  const WalletError(this.message);

  @override
  List<Object?> get props => [message];
}
