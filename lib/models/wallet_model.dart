import 'dart:convert';

/// Models for NIP-47 Nostr Wallet Connect operations
/// Based on the Go NWC implementation

/// Result of wallet operations
class WalletResult<T> {
  final T? data;
  final String? error;
  final bool isSuccess;

  const WalletResult.success(this.data)
      : error = null,
        isSuccess = true;

  const WalletResult.error(this.error)
      : data = null,
        isSuccess = false;

  bool get isError => !isSuccess;
}

/// Wallet connection configuration
class WalletConnection {
  final String relayUrl;
  final String walletPubKey;
  final String clientSecret;
  final String clientPubKey;

  const WalletConnection({
    required this.relayUrl,
    required this.walletPubKey,
    required this.clientSecret,
    required this.clientPubKey,
  });

  factory WalletConnection.fromUri(String nwcUri) {
    final uri = Uri.parse(nwcUri);
    final walletPubKey = uri.host.isNotEmpty ? uri.host : uri.path.replaceFirst('/', '');
    final query = uri.queryParameters;

    final relayUrl = Uri.decodeComponent(query['relay'] ?? '');
    final secret = query['secret'] ?? '';

    if (relayUrl.isEmpty) {
      throw Exception('relay parameter missing');
    }
    if (secret.isEmpty) {
      throw Exception('secret parameter missing');
    }

    return WalletConnection(
      relayUrl: relayUrl,
      walletPubKey: walletPubKey,
      clientSecret: secret,
      clientPubKey: '', // Will be generated from secret
    );
  }

  @override
  String toString() => 'WalletConnection(relay: $relayUrl, wallet: $walletPubKey)';
}

/// Wallet balance information
class WalletBalance {
  final int balance; // in millisatoshis

  const WalletBalance({required this.balance});

  factory WalletBalance.fromJson(Map<String, dynamic> json) {
    return WalletBalance(
      balance: json['balance'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {'balance': balance};

  @override
  String toString() => 'WalletBalance(balance: $balance msat)';
}

/// Invoice details for lightning payments
class InvoiceDetails {
  final String type;
  final String invoice;
  final String description;
  final String descriptionHash;
  final String preimage;
  final String paymentHash;
  final int amount;
  final int feesPaid;
  final int createdAt;
  final int expiresAt;
  final int settledAt;
  final Map<String, dynamic> metadata;

  const InvoiceDetails({
    required this.type,
    required this.invoice,
    required this.description,
    required this.descriptionHash,
    required this.preimage,
    required this.paymentHash,
    required this.amount,
    required this.feesPaid,
    required this.createdAt,
    required this.expiresAt,
    required this.settledAt,
    required this.metadata,
  });

  factory InvoiceDetails.fromJson(Map<String, dynamic> json) {
    return InvoiceDetails(
      type: json['type'] as String? ?? '',
      invoice: json['invoice'] as String? ?? '',
      description: json['description'] as String? ?? '',
      descriptionHash: json['description_hash'] as String? ?? '',
      preimage: json['preimage'] as String? ?? '',
      paymentHash: json['payment_hash'] as String? ?? '',
      amount: json['amount'] as int? ?? 0,
      feesPaid: json['fees_paid'] as int? ?? 0,
      createdAt: json['created_at'] as int? ?? 0,
      expiresAt: json['expires_at'] as int? ?? 0,
      settledAt: json['settled_at'] as int? ?? 0,
      metadata: json['metadata'] as Map<String, dynamic>? ?? {},
    );
  }

  Map<String, dynamic> toJson() => {
        'type': type,
        'invoice': invoice,
        'description': description,
        'description_hash': descriptionHash,
        'preimage': preimage,
        'payment_hash': paymentHash,
        'amount': amount,
        'fees_paid': feesPaid,
        'created_at': createdAt,
        'expires_at': expiresAt,
        'settled_at': settledAt,
        'metadata': metadata,
      };

  @override
  String toString() => 'InvoiceDetails(type: $type, amount: $amount, hash: $paymentHash)';
}

/// Payment result for invoice payments
class PaymentResult {
  final String preimage;
  final int feesPaid;

  const PaymentResult({
    required this.preimage,
    required this.feesPaid,
  });

  factory PaymentResult.fromJson(Map<String, dynamic> json) {
    return PaymentResult(
      preimage: json['preimage'] as String? ?? '',
      feesPaid: json['fees_paid'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'preimage': preimage,
        'fees_paid': feesPaid,
      };

  @override
  String toString() => 'PaymentResult(preimage: $preimage, fees: $feesPaid)';
}

/// Keysend payment result
class KeysendResult {
  final String preimage;
  final int feesPaid;

  const KeysendResult({
    required this.preimage,
    required this.feesPaid,
  });

  factory KeysendResult.fromJson(Map<String, dynamic> json) {
    return KeysendResult(
      preimage: json['preimage'] as String? ?? '',
      feesPaid: json['fees_paid'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'preimage': preimage,
        'fees_paid': feesPaid,
      };

  @override
  String toString() => 'KeysendResult(preimage: $preimage, fees: $feesPaid)';
}

/// Transaction details
typedef TransactionDetails = InvoiceDetails;

/// Wallet information
class WalletInfo {
  final String alias;
  final String pubkey;
  final String network;
  final List<String> methods;
  final String color;
  final int blockHeight;
  final String blockHash;
  final List<String> notifications;

  const WalletInfo({
    required this.alias,
    required this.pubkey,
    required this.network,
    required this.methods,
    required this.color,
    required this.blockHeight,
    required this.blockHash,
    required this.notifications,
  });

  factory WalletInfo.fromJson(Map<String, dynamic> json) {
    return WalletInfo(
      alias: json['alias'] as String? ?? '',
      pubkey: json['pubkey'] as String? ?? '',
      network: json['network'] as String? ?? '',
      methods: (json['methods'] as List<dynamic>?)?.cast<String>() ?? [],
      color: json['color'] as String? ?? '',
      blockHeight: json['block_height'] as int? ?? 0,
      blockHash: json['block_hash'] as String? ?? '',
      notifications: (json['notifications'] as List<dynamic>?)?.cast<String>() ?? [],
    );
  }

  Map<String, dynamic> toJson() => {
        'alias': alias,
        'pubkey': pubkey,
        'network': network,
        'methods': methods,
        'color': color,
        'block_height': blockHeight,
        'block_hash': blockHash,
        'notifications': notifications,
      };

  @override
  String toString() => 'WalletInfo(alias: $alias, network: $network, methods: $methods)';
}

/// NWC request payload
class NWCRequest {
  final String method;
  final Map<String, dynamic> params;

  const NWCRequest({
    required this.method,
    required this.params,
  });

  Map<String, dynamic> toJson() => {
        'method': method,
        'params': params,
      };

  String toJsonString() => jsonEncode(toJson());

  @override
  String toString() => 'NWCRequest(method: $method, params: $params)';
}

/// NWC response payload
class NWCResponse<T> {
  final T? result;
  final String? error;

  const NWCResponse({this.result, this.error});

  factory NWCResponse.fromJson(Map<String, dynamic> json, T Function(Map<String, dynamic>) fromJson) {
    try {
      // Check for error field
      if (json.containsKey('error') && json['error'] != null) {
        final errorValue = json['error'];
        String errorMessage;
        if (errorValue is String) {
          errorMessage = errorValue;
        } else if (errorValue is Map) {
          errorMessage = errorValue['message']?.toString() ?? errorValue.toString();
        } else {
          errorMessage = errorValue.toString();
        }
        return NWCResponse<T>(error: errorMessage);
      }

      // Check for result field
      if (json.containsKey('result')) {
        final resultValue = json['result'];
        if (resultValue is Map<String, dynamic>) {
          return NWCResponse<T>(result: fromJson(resultValue));
        } else if (resultValue == null) {
          return NWCResponse<T>(error: 'Result is null');
        } else {
          return NWCResponse<T>(error: 'Invalid result format: ${resultValue.runtimeType}');
        }
      }

      return NWCResponse<T>(error: 'No result or error field in response');
    } catch (e) {
      return NWCResponse<T>(error: 'Failed to parse response: $e');
    }
  }

  bool get isSuccess => error == null && result != null;
  bool get isError => error != null;

  @override
  String toString() => 'NWCResponse(result: $result, error: $error)';
}
