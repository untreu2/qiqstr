import '../../../core/bloc/base/base_event.dart';

abstract class WalletEvent extends BaseEvent {
  const WalletEvent();
}

class WalletBalanceRequested extends WalletEvent {
  const WalletBalanceRequested();
}

class WalletPaymentRequested extends WalletEvent {
  final String invoice;

  const WalletPaymentRequested(this.invoice);

  @override
  List<Object?> get props => [invoice];
}

class WalletInvoiceGenerated extends WalletEvent {
  final int amount;

  const WalletInvoiceGenerated(this.amount);

  @override
  List<Object?> get props => [amount];
}

class WalletTransactionsLoaded extends WalletEvent {
  const WalletTransactionsLoaded();
}

class WalletAutoConnectRequested extends WalletEvent {
  const WalletAutoConnectRequested();
}

class WalletConnectWithNostrRequested extends WalletEvent {
  const WalletConnectWithNostrRequested();
}
