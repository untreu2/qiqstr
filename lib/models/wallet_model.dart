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

class CoinosUser {
  final String id;
  final String username;
  final String pubkey;
  final String display;
  final String? picture;
  final String currency;
  final int? balance;
  final String? lud16;

  const CoinosUser({
    required this.id,
    required this.username,
    required this.pubkey,
    required this.display,
    this.picture,
    required this.currency,
    this.balance,
    this.lud16,
  });

  factory CoinosUser.fromJson(Map<String, dynamic> json) {
    final username = json['username'] as String? ?? '';
    final lud16 = json['lud16'] as String?;
    final cleanUsername = username.replaceAll(' ', '');
    final finalLud16 = lud16 ?? (cleanUsername.isNotEmpty ? '$cleanUsername@coinos.io' : null);
    
    return CoinosUser(
      id: json['id'] as String? ?? '',
      username: username,
      pubkey: json['pubkey'] as String? ?? '',
      display: json['display'] as String? ?? '',
      picture: json['picture'] as String?,
      currency: json['currency'] as String? ?? 'USD',
      balance: _parseToInt(json['balance']),
      lud16: finalLud16,
    );
  }

  static int? _parseToInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'username': username,
        'pubkey': pubkey,
        'display': display,
        'picture': picture,
        'currency': currency,
        'balance': balance,
        'lud16': lud16,
      };

  @override
  String toString() => 'CoinosUser(id: $id, username: $username, pubkey: $pubkey)';
}

class CoinosAuthResult {
  final CoinosUser user;
  final String token;

  const CoinosAuthResult({
    required this.user,
    required this.token,
  });

  factory CoinosAuthResult.fromJson(Map<String, dynamic> json) {
    return CoinosAuthResult(
      user: CoinosUser.fromJson(json['user'] as Map<String, dynamic>),
      token: json['token'] as String,
    );
  }

  Map<String, dynamic> toJson() => {
        'user': user.toJson(),
        'token': token,
      };

  @override
  String toString() => 'CoinosAuthResult(user: $user, token: $token)';
}

class CoinosBalance {
  final int balance;

  const CoinosBalance({required this.balance});

  factory CoinosBalance.fromJson(Map<String, dynamic> json) {
    return CoinosBalance(
      balance: _parseToInt(json['balance']) ?? 0,
    );
  }

  static int? _parseToInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  Map<String, dynamic> toJson() => {'balance': balance};

  @override
  String toString() => 'CoinosBalance(balance: $balance sats)';
}

class CoinosInvoice {
  final String? id;
  final String? hash;
  final String? bolt11;
  final String? address;
  final String? text;
  final int amount;
  final String? description;
  final String? webhook;
  final String? secret;
  final String type;
  final int? rate;
  final int? tip;
  final int? network;
  final int? received;
  final String? currency;
  final int? createdAt;
  final int? confirmedAt;
  final String? preimage;
  final String? paymentHash;

  const CoinosInvoice({
    this.id,
    this.hash,
    this.bolt11,
    this.address,
    this.text,
    required this.amount,
    this.description,
    this.webhook,
    this.secret,
    required this.type,
    this.rate,
    this.tip,
    this.network,
    this.received,
    this.currency,
    this.createdAt,
    this.confirmedAt,
    this.preimage,
    this.paymentHash,
  });

  factory CoinosInvoice.fromJson(Map<String, dynamic> json) {
    return CoinosInvoice(
      id: json['id'] as String?,
      hash: json['hash'] as String?,
      bolt11: json['bolt11'] as String?,
      address: json['address'] as String?,
      text: json['text'] as String?,
      amount: _parseToInt(json['amount']) ?? 0,
      description: json['description'] as String?,
      webhook: json['webhook'] as String?,
      secret: json['secret'] as String?,
      type: json['type'] as String? ?? 'lightning',
      rate: _parseToInt(json['rate']),
      tip: _parseToInt(json['tip']),
      network: _parseToInt(json['network']),
      received: _parseToInt(json['received']),
      currency: json['currency'] as String?,
      createdAt: _parseToInt(json['created']),
      confirmedAt: _parseToInt(json['confirmed']),
      preimage: json['preimage'] as String?,
      paymentHash: json['hash'] as String?,
    );
  }

  static int? _parseToInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'hash': hash,
        'bolt11': bolt11,
        'address': address,
        'text': text,
        'amount': amount,
        'description': description,
        'webhook': webhook,
        'secret': secret,
        'type': type,
        'rate': rate,
        'tip': tip,
        'network': network,
        'received': received,
        'currency': currency,
        'created': createdAt,
        'confirmed': confirmedAt,
        'preimage': preimage,
      };

  bool get isPaid => received != null && received! > 0;
  bool get isExpired => false;

  @override
  String toString() => 'CoinosInvoice(id: $id, amount: $amount, type: $type)';
}

class CoinosPaymentResult {
  final String? preimage;
  final String? hash;
  final int? fee;
  final String? error;
  final bool? paid;
  final String? status;

  const CoinosPaymentResult({
    this.preimage,
    this.hash,
    this.fee,
    this.error,
    this.paid,
    this.status,
  });

  factory CoinosPaymentResult.fromJson(Map<String, dynamic> json) {
    return CoinosPaymentResult(
      preimage: json['preimage'] as String?,
      hash: json['hash'] as String?,
      fee: _parseToInt(json['fee']),
      error: json['error'] as String?,
      paid: json['paid'] as bool?,
      status: json['status'] as String?,
    );
  }

  static int? _parseToInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  Map<String, dynamic> toJson() => {
        'preimage': preimage,
        'hash': hash,
        'fee': fee,
        'error': error,
        'paid': paid,
        'status': status,
      };

  bool get isSuccess {
    if (error != null && error!.isNotEmpty) return false;

    if (paid == true) return true;

    if (status != null && (status == 'paid' || status == 'success' || status == 'complete')) return true;

    if (preimage != null && preimage!.isNotEmpty) return true;

    if (hash != null && hash!.isNotEmpty && error == null) return true;

    return false;
  }

  @override
  String toString() => 'CoinosPaymentResult(preimage: $preimage, fee: $fee, error: $error, paid: $paid, status: $status)';
}

class CoinosPayment {
  final String? id;
  final String? hash;
  final int amount;
  final String? description;
  final String type;
  final String? username;
  final String? address;
  final int? fee;
  final int? tip;
  final int? rate;
  final String? currency;
  final int? createdAt;
  final int? confirmedAt;
  final String? preimage;
  final bool confirmed;

  const CoinosPayment({
    this.id,
    this.hash,
    required this.amount,
    this.description,
    required this.type,
    this.username,
    this.address,
    this.fee,
    this.tip,
    this.rate,
    this.currency,
    this.createdAt,
    this.confirmedAt,
    this.preimage,
    required this.confirmed,
  });

  factory CoinosPayment.fromJson(Map<String, dynamic> json) {
    return CoinosPayment(
      id: json['id'] as String?,
      hash: json['hash'] as String?,
      amount: _parseToInt(json['amount']) ?? 0,
      description: json['description'] as String?,
      type: json['type'] as String? ?? 'lightning',
      username: json['username'] as String?,
      address: json['address'] as String?,
      fee: _parseToInt(json['fee']),
      tip: _parseToInt(json['tip']),
      rate: _parseToInt(json['rate']),
      currency: json['currency'] as String?,
      createdAt: _parseToInt(json['created']),
      confirmedAt: _parseToInt(json['confirmed']),
      preimage: json['preimage'] as String?,
      confirmed: json['confirmed'] != null,
    );
  }

  static int? _parseToInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'hash': hash,
        'amount': amount,
        'description': description,
        'type': type,
        'username': username,
        'address': address,
        'fee': fee,
        'tip': tip,
        'rate': rate,
        'currency': currency,
        'created': createdAt,
        'confirmed': confirmedAt,
        'preimage': preimage,
      };

  bool get isIncoming => type == 'lightning' && amount > 0 && confirmed;
  bool get isOutgoing => type == 'lightning' && amount < 0;

  @override
  String toString() => 'CoinosPayment(id: $id, amount: $amount, type: $type)';
}

typedef TransactionDetails = CoinosPayment;
