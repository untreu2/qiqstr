import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:bech32/bech32.dart';

class WalletProvider extends ChangeNotifier {
  final String _apiUrl = "https://api.blink.sv/graphql";
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  String? _balance;
  String? get balance => _balance;

  String? _invoice;
  String? get invoice => _invoice;

  String? _status;
  String? get status => _status;

  bool _paymentSuccessful = false;
  bool get paymentSuccessful => _paymentSuccessful;

  Timer? _paymentTimer;
  String? _authToken;

  final Map<String, double> _exchangeRateCache = {};
  final Map<String, DateTime> _exchangeRateTimestamp = {};
  final Duration _cacheDuration = Duration(minutes: 5);

  String? _lightningAddress;
  String? get lightningAddress => _lightningAddress;

  String? _onChainAddress;
  String? get onChainAddress => _onChainAddress;

  WalletProvider() {
    _loadApiKey();
  }

  Future<void> _loadApiKey() async {
    _authToken = await _secureStorage.read(key: 'API_KEY');

    // Load cached balance and lightning address from secure storage
    _balance = await _secureStorage.read(key: 'WALLET_BALANCE');
    _lightningAddress = await _secureStorage.read(key: 'LIGHTNING_ADDRESS');

    if (_authToken != null) {
      await fetchBalance();
      await fetchLightningAddress();
    }
    notifyListeners();
  }

  Future<void> saveApiKey(String apiKey) async {
    await _secureStorage.write(key: 'API_KEY', value: apiKey);
    _authToken = apiKey;
    await fetchBalance();
    await fetchLightningAddress();
    notifyListeners();
  }

  Future<void> clearApiKey() async {
    await _secureStorage.delete(key: 'API_KEY');
    await _secureStorage.delete(key: 'WALLET_BALANCE');
    await _secureStorage.delete(key: 'LIGHTNING_ADDRESS');
    _authToken = null;
    _balance = null;
    _lightningAddress = null;
    _onChainAddress = null;
    notifyListeners();
  }

  Future<bool> isLoggedIn() async {
    _authToken = await _secureStorage.read(key: 'API_KEY');
    return _authToken != null;
  }

  Future<void> fetchBalance() async {
    if (_authToken == null) {
      _balance = "Not authenticated.";
      await _secureStorage.delete(key: 'WALLET_BALANCE');
      notifyListeners();
      return;
    }
    final query = """
    query Me {
      me {
        defaultAccount {
          wallets {
            walletCurrency
            balance
          }
        }
      }
    }
    """;
    try {
      final response = await http.post(Uri.parse(_apiUrl),
          headers: {"Content-Type": "application/json", "X-API-KEY": _authToken!}, body: jsonEncode({"query": query}));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final wallets = data["data"]["me"]["defaultAccount"]["wallets"];
        for (var wallet in wallets) {
          if (wallet["walletCurrency"] == "BTC") {
            _balance = wallet["balance"].toString();
            // Save balance to secure storage
            await _secureStorage.write(key: 'WALLET_BALANCE', value: _balance!);
            notifyListeners();
            return;
          }
        }
        _balance = "BTC wallet not found.";
      } else {
        _balance = "Failed to fetch balance.";
      }
    } catch (e) {
      _balance = "Error: $e";
    }
    notifyListeners();
  }

  Future<void> fetchLightningAddress() async {
    if (_authToken == null) {
      _lightningAddress = "Not authenticated.";
      await _secureStorage.delete(key: 'LIGHTNING_ADDRESS');
      notifyListeners();
      return;
    }
    final query = """
    query GetUserAndGlobalData {
      me {
        username
      }
      globals {
        lightningAddressDomain
      }
    }
    """;
    try {
      final response = await http.post(Uri.parse(_apiUrl),
          headers: {"Content-Type": "application/json", "X-API-KEY": _authToken!}, body: jsonEncode({"query": query}));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data["data"] != null && data["data"]["me"] != null && data["data"]["globals"] != null) {
          final String username = data["data"]["me"]["username"];
          final String lightningDomain = data["data"]["globals"]["lightningAddressDomain"];
          _lightningAddress = "$username@$lightningDomain";
          // Save lightning address to secure storage
          await _secureStorage.write(key: 'LIGHTNING_ADDRESS', value: _lightningAddress!);
        } else {
          _lightningAddress = "Expected data not found in API response.";
        }
      } else if (response.statusCode == 401) {
        _lightningAddress = "Authorization Error: Check your API key.";
      } else {
        _lightningAddress = "API Error: ${response.statusCode}";
      }
    } catch (e) {
      _lightningAddress = "Error: $e";
    }
    notifyListeners();
  }

  Future<void> createInvoice(int amountSatoshis, String memo) async {
    if (_authToken == null) {
      _invoice = "Not authenticated.";
      notifyListeners();
      return;
    }
    final query = """
    mutation LnInvoiceCreate(\$input: LnInvoiceCreateInput!) {
      lnInvoiceCreate(input: \$input) {
        invoice {
          paymentRequest
          paymentHash
          paymentSecret
          satoshis
        }
        errors {
          message
        }
      }
    }
    """;
    final walletId = await getWalletId();
    if (walletId == null) {
      _invoice = "BTC wallet not found.";
      notifyListeners();
      return;
    }
    final variables = {
      "input": {"amount": amountSatoshis, "walletId": walletId, "memo": memo.isNotEmpty ? memo : ""}
    };
    try {
      final response = await http.post(Uri.parse(_apiUrl),
          headers: {"Content-Type": "application/json", "X-API-KEY": _authToken!},
          body: jsonEncode({"query": query, "variables": variables}));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data["data"]["lnInvoiceCreate"]["errors"] != null && data["data"]["lnInvoiceCreate"]["errors"].length > 0) {
          _invoice = data["data"]["lnInvoiceCreate"]["errors"][0]["message"];
        } else {
          _invoice = data["data"]["lnInvoiceCreate"]["invoice"]["paymentRequest"];
        }
      } else {
        _invoice = "Failed to create invoice.";
      }
    } catch (e) {
      _invoice = "Error: $e";
    }
    notifyListeners();
  }

  Future<String?> getWalletId() async {
    if (_authToken == null) {
      return null;
    }
    final query = """
    query Me {
      me {
        defaultAccount {
          wallets {
            id
            walletCurrency
            balance
          }
        }
      }
    }
    """;
    try {
      final response = await http.post(Uri.parse(_apiUrl),
          headers: {"Content-Type": "application/json", "X-API-KEY": _authToken!}, body: jsonEncode({"query": query}));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final wallets = data["data"]["me"]["defaultAccount"]["wallets"];
        for (var wallet in wallets) {
          if (wallet["walletCurrency"] == "BTC") {
            return wallet["id"];
          }
        }
        return null;
      } else {
        return null;
      }
    } catch (e) {
      return null;
    }
  }

  Future<double?> probeInvoiceFee(String paymentRequest) async {
    if (_authToken == null) return null;
    final walletId = await getWalletId();
    if (walletId == null) return null;
    final query = """
    mutation lnInvoiceFeeProbe(\$input: LnInvoiceFeeProbeInput!) {
      lnInvoiceFeeProbe(input: \$input) {
        errors {
          message
        }
        amount
      }
    }
    """;
    final variables = {
      "input": {"paymentRequest": paymentRequest, "walletId": walletId}
    };
    try {
      final response = await http.post(Uri.parse(_apiUrl),
          headers: {"Content-Type": "application/json", "X-API-KEY": _authToken!},
          body: jsonEncode({"query": query, "variables": variables}));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final result = data["data"]["lnInvoiceFeeProbe"];
        if (result["errors"] != null && (result["errors"] as List).isNotEmpty) {
          return null;
        } else {
          double fee = (result["amount"] as num).toDouble();
          return fee;
        }
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  Future<void> payInvoice(String paymentRequest) async {
    if (_authToken == null) {
      _status = "Not authenticated.";
      notifyListeners();
      return;
    }
    final query = """
    mutation LnInvoicePaymentSend(\$input: LnInvoicePaymentInput!) {
      lnInvoicePaymentSend(input: \$input) {
        status
        errors {
          message
          path
          code
        }
      }
    }
    """;
    final walletId = await getWalletId();
    if (walletId == null) {
      _status = "BTC wallet not found.";
      notifyListeners();
      return;
    }
    final variables = {
      "input": {"paymentRequest": paymentRequest, "walletId": walletId}
    };
    try {
      final response = await http.post(Uri.parse(_apiUrl),
          headers: {"Content-Type": "application/json", "X-API-KEY": _authToken!},
          body: jsonEncode({"query": query, "variables": variables}));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data["data"]["lnInvoicePaymentSend"]["errors"] != null && data["data"]["lnInvoicePaymentSend"]["errors"].length > 0) {
          _status = data["data"]["lnInvoicePaymentSend"]["errors"][0]["message"];
        } else {
          _status = data["data"]["lnInvoicePaymentSend"]["status"];
        }
      } else {
        _status = "Failed to send payment.";
      }
    } catch (e) {
      _status = "Error: $e";
    }
    notifyListeners();
  }

  Future<void> payInvoiceWithFeeConfirmation(String paymentRequest, Future<bool> Function(double fee) confirmCallback) async {
    double? fee = await probeInvoiceFee(paymentRequest);
    if (fee == null) {
      _status = "Invoice fee could not be retrieved.";
      notifyListeners();
      return;
    }
    bool confirmed = await confirmCallback(fee);
    if (confirmed) {
      await payInvoice(paymentRequest);
    } else {
      _status = "Payment canceled.";
      notifyListeners();
    }
  }

  Future<String> createLnInvoiceFromLnurl(String lnurl, int amountSatoshis, String memo) async {
    int msat = amountSatoshis * 1000;
    String lnurlp;
    if (lnurl.contains('@')) {
      var parts = lnurl.split('@');
      if (parts.length != 2) throw Exception("Invalid lightning address format");
      String user = parts[0];
      String domain = parts[1];
      lnurlp = "https://$domain/.well-known/lnurlp/$user";
    } else {
      lnurlp = decodeLnurl(lnurl);
    }
    final res = await http.get(Uri.parse(lnurlp));
    if (res.statusCode != 200) {
      throw Exception("Could not fetch LNURL-pay info: ${res.statusCode}");
    }
    final lnurlData = jsonDecode(res.body);
    int minSendable = lnurlData["minSendable"] ?? 0;
    int maxSendable = lnurlData["maxSendable"] ?? 0;
    if (msat < minSendable || msat > maxSendable) {
      throw Exception("Amount out of range. Minimum ${minSendable ~/ 1000} and maximum ${maxSendable ~/ 1000} satoshis allowed.");
    }
    String callbackUrl = lnurlData["callback"];
    if (callbackUrl.isEmpty) {
      throw Exception("LNURL-pay info does not contain a callback URL");
    }
    var callbackUri = Uri.parse(callbackUrl);
    var queryParameters = Map<String, String>.from(callbackUri.queryParameters);
    queryParameters["amount"] = msat.toString();
    int commentAllowed = lnurlData["commentAllowed"] ?? 0;
    if (memo.isNotEmpty) {
      if (commentAllowed > 0 && memo.length > commentAllowed) {
        memo = memo.substring(0, commentAllowed);
      }
      queryParameters["comment"] = memo;
    }
    var newUri = callbackUri.replace(queryParameters: queryParameters);
    final invoiceRes = await http.get(newUri);
    if (invoiceRes.statusCode != 200) {
      throw Exception("Failed to fetch invoice: ${invoiceRes.statusCode}");
    }
    final invoiceData = jsonDecode(invoiceRes.body);
    if (invoiceData["status"] != null && invoiceData["status"].toString().toLowerCase() == "error") {
      throw Exception("Invoice error: ${invoiceData["reason"] ?? "Unknown error"}");
    }
    String invoice = invoiceData["pr"];
    if (invoice.isEmpty) {
      throw Exception("No invoice found in response");
    }
    return invoice;
  }

  Future<void> createAndPayLnurlInvoice(
      String lnurl, int amountSatoshis, String memo, Future<bool> Function(double fee) confirmCallback) async {
    try {
      String lnInvoice = await createLnInvoiceFromLnurl(lnurl, amountSatoshis, memo);
      double? fee = await probeInvoiceFee(lnInvoice);
      if (fee == null) {
        _status = "Invoice fee could not be fetched.";
        notifyListeners();
        return;
      }
      bool confirmed = await confirmCallback(fee);
      if (confirmed) {
        await payInvoice(lnInvoice);
      } else {
        _status = "Payment canceled.";
        notifyListeners();
      }
    } catch (e) {
      _status = "Error creating LN invoice: $e";
      notifyListeners();
    }
  }

  Future<List<Map<String, dynamic>>> getHistory(int count) async {
    if (_authToken == null) {
      return [];
    }
    final query = """
    query PaymentsWithProof(\$first: Int) {
      me {
        defaultAccount {
          transactions(first: \$first) {
            edges {
              node {
                id
                initiationVia {
                  ... on InitiationViaLn {
                    paymentRequest
                  }
                }
                settlementAmount
                status
              }
            }
          }
        }
      }
    }
    """;
    final variables = {"first": count};
    try {
      final response = await http.post(Uri.parse(_apiUrl),
          headers: {"Content-Type": "application/json", "X-API-KEY": _authToken!},
          body: jsonEncode({"query": query, "variables": variables}));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List<dynamic> transactions = data["data"]["me"]["defaultAccount"]["transactions"]["edges"];
        List<Map<String, dynamic>> txList = [];
        for (var tx in transactions) {
          final node = tx["node"];
          final initiationVia = node["initiationVia"];
          if (initiationVia != null && initiationVia["paymentRequest"] != null) {
            txList.add({
              "id": node["id"],
              "invoice": initiationVia["paymentRequest"],
              "settlementAmount": node["settlementAmount"],
              "status": node["status"],
            });
          }
        }
        return txList;
      } else {
        print("Failed to fetch transaction history. Status code: ${response.statusCode}");
        print("Response: ${response.body}");
        return [];
      }
    } catch (e) {
      print("Error fetching transaction history: $e");
      return [];
    }
  }

  void startPaymentCheck(String invoice) {
    if (_paymentTimer != null && _paymentTimer!.isActive) return;
    _paymentTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
      if (_authToken == null) {
        stopPaymentCheck();
        return;
      }
      bool isPaid = await checkPaymentStatus(invoice);
      if (isPaid) {
        _paymentSuccessful = true;
        notifyListeners();
        stopPaymentCheck();
      }
    });
  }

  void stopPaymentCheck() {
    if (_paymentTimer != null) {
      _paymentTimer!.cancel();
      _paymentTimer = null;
    }
  }

  Future<bool> checkPaymentStatus(String paymentRequest) async {
    if (_authToken == null) return false;
    final Map<String, dynamic> requestBody = {
      "query": """
        query PaymentsWithProof(\$first: Int) {
          me {
            defaultAccount {
              transactions(first: \$first) {
                edges {
                  node {
                    initiationVia {
                      ... on InitiationViaLn {
                        paymentRequest
                      }
                    }
                    settlementAmount
                    status
                  }
                }
              }
            }
          }
        }
      """,
      "variables": {"first": 10},
    };
    try {
      final response = await http.post(Uri.parse(_apiUrl),
          headers: {"Content-Type": "application/json", "X-API-KEY": _authToken!}, body: jsonEncode(requestBody));
      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        final transactions = responseData['data']['me']['defaultAccount']['transactions']['edges'];
        for (var transaction in transactions) {
          if (transaction['node']['initiationVia']['paymentRequest'] == paymentRequest && transaction['node']['status'] == 'SUCCESS') {
            return true;
          }
        }
      }
    } catch (e) {
      print("Error checking payment status: $e");
    }
    return false;
  }

  Future<double?> convertSatoshisToCurrency(int satoshis, String currency) async {
    try {
      double? btcPrice = await _fetchBtcPrice(currency);
      if (btcPrice == null) return null;
      double btcAmount = satoshis / 100000000;
      double fiatAmount = btcAmount * btcPrice;
      return fiatAmount;
    } catch (e) {
      print("Error converting satoshis to $currency: $e");
      return null;
    }
  }

  Future<int?> convertCurrencyToSatoshis(double amount, String currency) async {
    try {
      double? btcPrice = await _fetchBtcPrice(currency);
      if (btcPrice == null) return null;
      double btcAmount = amount / btcPrice;
      int satoshis = (btcAmount * 100000000).round();
      return satoshis;
    } catch (e) {
      print("Error converting $currency to satoshis: $e");
      return null;
    }
  }

  Future<double?> _fetchBtcPrice(String currency) async {
    if (_exchangeRateCache.containsKey(currency)) {
      DateTime fetchedTime = _exchangeRateTimestamp[currency]!;
      if (DateTime.now().difference(fetchedTime) < _cacheDuration) {
        return _exchangeRateCache[currency];
      }
    }
    final String query = r'''
      query realtimePrice($currency: DisplayCurrency) {
        realtimePrice(currency: $currency) {
          btcSatPrice {
            base
            offset
          }
          denominatorCurrencyDetails {
            symbol
          }
        }
      }
    ''';
    final variables = {"currency": currency.toUpperCase()};
    try {
      final response = await http.post(
        Uri.parse(_apiUrl),
        headers: {
          "Content-Type": "application/json",
          if (_authToken != null) "X-API-KEY": _authToken!,
        },
        body: jsonEncode({"query": query, "variables": variables}),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final realtimePrice = data["data"]?["realtimePrice"];
        if (realtimePrice == null) {
          print("Unexpected response format: $data");
          return null;
        }
        final btcSatPrice = realtimePrice["btcSatPrice"];
        if (btcSatPrice == null || btcSatPrice["base"] == null || btcSatPrice["offset"] == null) {
          print("Failed to retrieve satoshi price information.");
          return null;
        }
        double base =
            (btcSatPrice["base"] is num) ? btcSatPrice["base"].toDouble() : double.tryParse(btcSatPrice["base"].toString()) ?? 0.0;
        int offset = int.tryParse(btcSatPrice["offset"].toString()) ?? 0;
        double pricePerSatMinor = base / (pow(10, offset));
        int divisor = 100;
        double pricePerSat = pricePerSatMinor / divisor;
        double btcPrice = pricePerSat * 100000000;
        _exchangeRateCache[currency] = btcPrice;
        _exchangeRateTimestamp[currency] = DateTime.now();
        return btcPrice;
      } else {
        print("Request failed. Status code: ${response.statusCode}");
        print("Response: ${response.body}");
        return null;
      }
    } catch (e) {
      print("Error fetching BTC price from GraphQL API: $e");
      return null;
    }
  }

  Future<void> sendOnChainPayment({
    required String destinationAddress,
    required int amountSats,
    String memo = "",
  }) async {
    if (_authToken == null) {
      _status = "Not authenticated.";
      notifyListeners();
      return;
    }

    final walletId = await getWalletId();
    if (walletId == null) {
      _status = "BTC wallet not found.";
      notifyListeners();
      return;
    }

    final query = """
    mutation OnChainPaymentSend(\$input: OnChainPaymentSendInput!) {
      onChainPaymentSend(input: \$input) {
        status
        errors {
          message
          path
          code
        }
      }
    }
    """;

    final variables = {
      "input": {
        "address": destinationAddress,
        "amount": amountSats,
        "walletId": walletId,
        if (memo.isNotEmpty) "memo": memo,
      }
    };

    try {
      final response = await http.post(
        Uri.parse(_apiUrl),
        headers: {
          "Content-Type": "application/json",
          "X-API-KEY": _authToken!,
        },
        body: jsonEncode({
          "query": query,
          "variables": variables,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final result = data["data"]["onChainPaymentSend"];
        if (result["errors"] != null && result["errors"].length > 0) {
          _status = "Error: ${result["errors"][0]["message"]}";
        } else {
          _status = result["status"] ?? "Unknown status.";
        }
      } else {
        _status = "Failed to send payment. Status: ${response.statusCode}";
      }
    } catch (e) {
      _status = "Error: $e";
    }

    notifyListeners();
  }

  Future<void> createOnChainAddress() async {
    if (_authToken == null) {
      _onChainAddress = "Not authenticated.";
      notifyListeners();
      return;
    }
    final walletId = await getWalletId();
    if (walletId == null) {
      _onChainAddress = "BTC wallet not found.";
      notifyListeners();
      return;
    }
    final query = """
    mutation onChainAddressCreate(\$input: OnChainAddressCreateInput!) {
      onChainAddressCreate(input: \$input) {
        address
        errors {
          message
        }
      }
    }
    """;
    final variables = {
      "input": {"walletId": walletId}
    };
    try {
      final response = await http.post(Uri.parse(_apiUrl),
          headers: {"Content-Type": "application/json", "X-API-KEY": _authToken!},
          body: jsonEncode({"query": query, "variables": variables}));
      print("Status Code: ${response.statusCode}");
      print("Response Body: ${response.body}");
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final result = data["data"]["onChainAddressCreate"];
        if (result["errors"] != null && result["errors"].length > 0) {
          _onChainAddress = "Error: ${result["errors"][0]["message"]}";
        } else {
          _onChainAddress = result["address"];
        }
      } else {
        _onChainAddress = "Failed to create on-chain address. Status Code: ${response.statusCode}";
      }
    } catch (e) {
      _onChainAddress = "Error: $e";
    }
    notifyListeners();
  }

  Future<Map<String, dynamic>?> getTransactionDetails(String transactionId) async {
    if (_authToken == null) {
      return null;
    }

    final query = """
    query GetTransactions(\$first: Int) {
      me {
        defaultAccount {
          transactions(first: \$first) {
            edges {
              node {
                id
                createdAt
                direction
                externalId
                memo
                settlementAmount
                settlementCurrency
                settlementDisplayAmount
                settlementDisplayCurrency
                settlementDisplayFee
                settlementFee
                status
                initiationVia {
                  ... on InitiationViaLn {
                    paymentRequest
                    paymentHash
                  }
                  ... on InitiationViaOnChain {
                    address
                  }
                  ... on InitiationViaIntraLedger {
                    counterPartyUsername
                    counterPartyWalletId
                  }
                }
                settlementVia {
                  ... on SettlementViaLn {
                    preImage
                    paymentSecret
                  }
                  ... on SettlementViaOnChain {
                    transactionHash
                    vout
                    arrivalInMempoolEstimatedAt
                  }
                  ... on SettlementViaIntraLedger {
                    counterPartyUsername
                    counterPartyWalletId
                    preImage
                  }
                }
                settlementPrice {
                  base
                  offset
                  currencyUnit
                  formattedAmount
                }
              }
            }
          }
        }
      }
    }
    """;

    final variables = {"first": 100};

    try {
      final response = await http.post(
        Uri.parse(_apiUrl),
        headers: {
          "Content-Type": "application/json",
          "X-API-KEY": _authToken!,
        },
        body: jsonEncode({"query": query, "variables": variables}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        print("Transaction details response: $data");

        if (data["errors"] != null) {
          print("GraphQL errors: ${data["errors"]}");
          return null;
        }

        final transactions = data["data"]?["me"]?["defaultAccount"]?["transactions"]?["edges"];
        if (transactions == null) {
          print("No transactions found");
          return null;
        }

        for (var edge in transactions) {
          final transaction = edge["node"];
          if (transaction["id"] == transactionId) {
            print("Found transaction: $transaction");
            return transaction;
          }
        }

        print("Transaction not found for ID: $transactionId");
        return null;
      } else {
        print("Failed to fetch transaction details. Status: ${response.statusCode}");
        print("Response body: ${response.body}");
        return null;
      }
    } catch (e) {
      print("Error fetching transaction details: $e");
      return null;
    }
  }

  @override
  void dispose() {
    stopPaymentCheck();
    super.dispose();
  }
}

String decodeLnurl(String lnurl) {
  final codec = Bech32Codec();
  final bech32Obj = codec.decode(lnurl, lnurl.length);
  final data = bech32Obj.data;
  final converted = convertBits(data, 5, 8, false);
  return utf8.decode(converted);
}

List<int> convertBits(List<int> data, int fromBits, int toBits, bool pad) {
  int acc = 0;
  int bits = 0;
  final int maxv = (1 << toBits) - 1;
  List<int> result = [];
  for (var value in data) {
    if (value < 0 || (value >> fromBits) != 0) {
      throw Exception("Invalid value in convertBits");
    }
    acc = (acc << fromBits) | value;
    bits += fromBits;
    while (bits >= toBits) {
      bits -= toBits;
      result.add((acc >> bits) & maxv);
    }
  }
  if (pad) {
    if (bits > 0) {
      result.add((acc << (toBits - bits)) & maxv);
    }
  } else {
    if (bits >= fromBits) {
      throw Exception("Excess padding");
    }
    if (((acc << (toBits - bits)) & maxv) != 0) {
      throw Exception("Non-zero padding");
    }
  }
  return result;
}
