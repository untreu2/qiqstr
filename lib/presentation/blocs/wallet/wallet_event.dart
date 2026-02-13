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
  final String? recaptchaToken;

  const WalletAutoConnectRequested({this.recaptchaToken});

  @override
  List<Object?> get props => [recaptchaToken];
}

class WalletConnectWithNostrRequested extends WalletEvent {
  final String? recaptchaToken;

  const WalletConnectWithNostrRequested({this.recaptchaToken});

  @override
  List<Object?> get props => [recaptchaToken];
}

class WalletPriceRequested extends WalletEvent {
  const WalletPriceRequested();
}

class WalletApiKeySet extends WalletEvent {
  final String apiKey;

  const WalletApiKeySet(this.apiKey);

  @override
  List<Object?> get props => [apiKey];
}
