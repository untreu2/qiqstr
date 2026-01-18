import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:ndk/ndk.dart';
import 'package:ndk/shared/nips/nip01/bip340.dart';

import '../../core/base/result.dart';

class CoinosService {
  static const String _baseUrl = 'https://coinos.io/api';
  static const String _tokenKey = 'coinos_token';
  static const String _userKey = 'coinos_user';
  static const String _usernameKey = 'coinos_username';
  static const String _passwordKey = 'coinos_password';

  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  final http.Client _httpClient = http.Client();

  String? _cachedToken;
  Map<String, dynamic>? _cachedUser;

  Future<Result<Map<String, dynamic>>> authenticateWithNostr() async {
    try {
      debugPrint('[CoinosService] Starting Nostr authentication with Coinos');

      final privateKey = await _secureStorage.read(key: 'privateKey');
      if (privateKey == null || privateKey.isEmpty) {
        return const Result.error('No Nostr private key found');
      }

      final challengeResponse = await _httpClient.get(
        Uri.parse('$_baseUrl/challenge'),
        headers: {'Content-Type': 'application/json'},
      );

      if (challengeResponse.statusCode != 200) {
        return Result.error('Failed to get challenge: ${challengeResponse.statusCode}');
      }

      final challengeData = jsonDecode(challengeResponse.body) as Map<String, dynamic>;
      final challenge = challengeData['challenge'] as String?;

      if (challenge == null || challenge.isEmpty) {
        return const Result.error('Invalid challenge received');
      }

      debugPrint('[CoinosService] Got challenge: $challenge');

      final publicKey = Bip340.getPublicKey(privateKey);
      final authEvent = Nip01Event(
        pubKey: publicKey,
        kind: 27235,
        tags: [
          ['challenge', challenge]
        ],
        content: '',
      );
      authEvent.sig = Bip340.sign(authEvent.id, privateKey);
      final authResponse = await _httpClient.post(
        Uri.parse('$_baseUrl/nostrAuth'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'event': {
            'id': authEvent.id,
            'pubkey': authEvent.pubKey,
            'created_at': authEvent.createdAt,
            'kind': authEvent.kind,
            'tags': authEvent.tags,
            'content': authEvent.content,
            'sig': authEvent.sig,
          },
          'challenge': challenge,
        }),
      );

      if (authResponse.statusCode == 200) {
        final data = jsonDecode(authResponse.body) as Map<String, dynamic>;

        final userData = data['user'] as Map<String, dynamic>? ?? data;
        final user = <String, dynamic>{
          'username': userData['username'] as String? ?? '',
          'id': userData['id'] as String? ?? '',
        };
        final token = data['token'] as String? ?? '';

        _cachedToken = token;
        _cachedUser = user;

        await Future.wait([
          _secureStorage.write(key: _tokenKey, value: token),
          _secureStorage.write(key: _userKey, value: jsonEncode(user)),
        ]);

        final username = user['username'] as String? ?? '';
        debugPrint('[CoinosService] Nostr authentication successful for user: $username');

        return Result.success({
          'user': user,
          'token': token,
        });
      } else {
        debugPrint('[CoinosService] Nostr auth failed: ${authResponse.statusCode}');
        debugPrint('[CoinosService] Response body: ${authResponse.body}');
        return Result.error('Nostr authentication failed: ${authResponse.statusCode}');
      }
    } catch (e) {
      debugPrint('[CoinosService] Nostr authentication error: $e');
      return Result.error('Nostr authentication failed: $e');
    }
  }

  Future<Result<Map<String, dynamic>>> autoLogin() async {
    try {
      final tokenResult = await getStoredToken();
      if (tokenResult.isSuccess && tokenResult.data != null) {
        final userResult = await getStoredUser();
        if (userResult.isSuccess && userResult.data != null) {
          debugPrint('[CoinosService] Using stored auth data');
          return Result.success({
            'user': userResult.data!,
            'token': tokenResult.data!,
          });
        }
      }
      debugPrint('[CoinosService] Attempting Nostr auto-login');
      return await authenticateWithNostr();
    } catch (e) {
      debugPrint('[CoinosService] Auto-login error: $e');
      return Result.error('Auto-login failed: $e');
    }
  }

  Future<Result<String?>> getStoredToken() async {
    try {
      if (_cachedToken != null) {
        return Result.success(_cachedToken);
      }

      final token = await _secureStorage.read(key: _tokenKey);
      _cachedToken = token;
      return Result.success(token);
    } catch (e) {
      return Result.error('Failed to get stored token: $e');
    }
  }

  Future<Result<Map<String, dynamic>?>> getStoredUser() async {
    try {
      if (_cachedUser != null) {
        return Result.success(_cachedUser);
      }

      final userJson = await _secureStorage.read(key: _userKey);
      if (userJson != null) {
        final userData = jsonDecode(userJson) as Map<String, dynamic>;
        _cachedUser = userData;
        return Result.success(_cachedUser);
      }

      return Result.success(null);
    } catch (e) {
      return Result.error('Failed to get stored user: $e');
    }
  }

  Future<Result<Map<String, String>>> _getAuthHeaders() async {
    final tokenResult = await getStoredToken();
    if (tokenResult.isError || tokenResult.data == null) {
      return const Result.error('No authentication token available');
    }

    return Result.success({
      'Content-Type': 'application/json',
      'Authorization': 'Bearer ${tokenResult.data}',
    });
  }

  Future<Result<T>> _makeAuthenticatedRequest<T>(
    String endpoint,
    String method,
    T Function(Map<String, dynamic>) fromJson, {
    Map<String, dynamic>? body,
  }) async {
    try {
      final headersResult = await _getAuthHeaders();
      if (headersResult.isError) {
        return Result.error(headersResult.error!);
      }

      final headers = headersResult.data!;
      final uri = Uri.parse('$_baseUrl$endpoint');

      late http.Response response;

      switch (method.toUpperCase()) {
        case 'GET':
          response = await _httpClient.get(uri, headers: headers);
          break;
        case 'POST':
          response = await _httpClient.post(
            uri,
            headers: headers,
            body: body != null ? jsonEncode(body) : null,
          );
          break;
        default:
          return Result.error('Unsupported HTTP method: $method');
      }

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return Result.success(fromJson(data));
      } else if (response.statusCode == 401) {
        await clearAuthData();
        return const Result.error('Authentication token expired');
      } else {
        debugPrint('[CoinosService] Request failed: ${response.statusCode}');
        debugPrint('[CoinosService] Response body: ${response.body}');
        return Result.error('Request failed: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('[CoinosService] Request error: $e');
      return Result.error('Request failed: $e');
    }
  }

  Future<Result<Map<String, dynamic>>> getAccountInfo() async {
    return _makeAuthenticatedRequest(
      '/me',
      'GET',
      (json) => json,
    );
  }

  Future<Result<Map<String, dynamic>>> getBalance() async {
    return _makeAuthenticatedRequest(
      '/me',
      'GET',
      (json) => json,
    );
  }

  Future<Result<Map<String, dynamic>>> createInvoice({
    required String type,
    required int amount,
    bool fiat = false,
    String? webhook,
    String? secret,
  }) async {
    final invoiceData = {
      'type': type,
      'amount': amount,
      'fiat': fiat,
      if (webhook != null) 'webhook': webhook,
      if (secret != null) 'secret': secret,
    };

    try {
      final headersResult = await _getAuthHeaders();
      if (headersResult.isError) {
        return Result.error(headersResult.error!);
      }

      final headers = headersResult.data!;
      final uri = Uri.parse('$_baseUrl/invoice');

      debugPrint('[CoinosService] Creating invoice with data: $invoiceData');

      final response = await _httpClient.post(
        uri,
        headers: headers,
        body: jsonEncode({'invoice': invoiceData}),
      );

      debugPrint('[CoinosService] Invoice response status: ${response.statusCode}');
      debugPrint('[CoinosService] Invoice response body: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        debugPrint('[CoinosService] Parsed invoice data: $data');
        return Result.success(data);
      } else if (response.statusCode == 401) {
        await clearAuthData();
        return const Result.error('Authentication token expired');
      } else {
        debugPrint('[CoinosService] Invoice creation failed: ${response.statusCode}');
        return Result.error('Invoice creation failed: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('[CoinosService] Invoice creation error: $e');
      return Result.error('Invoice creation failed: $e');
    }
  }

  Future<Result<Map<String, dynamic>>> getInvoiceStatus(String hash) async {
    return _makeAuthenticatedRequest(
      '/invoice/$hash',
      'GET',
      (json) => json,
    );
  }

  Future<Result<Map<String, dynamic>>> payInvoice(String payreq) async {
    try {
      debugPrint('[CoinosService] Attempting to pay invoice: ${payreq.substring(0, 20)}...');

      final headersResult = await _getAuthHeaders();
      if (headersResult.isError) {
        return Result.error(headersResult.error!);
      }

      final headers = headersResult.data!;
      final uri = Uri.parse('$_baseUrl/payments');
      final body = {'payreq': payreq};

      debugPrint('[CoinosService] Paying invoice with body: $body');

      final response = await _httpClient.post(
        uri,
        headers: headers,
        body: jsonEncode(body),
      );

      debugPrint('[CoinosService] Payment response status: ${response.statusCode}');
      debugPrint('[CoinosService] Payment response body: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        debugPrint('[CoinosService] Parsed payment data: $data');

        final isSuccess = (data['success'] as bool?) ?? ((data['status'] as String?) == 'success');
        final paymentResult = Map<String, dynamic>.from(data);
        paymentResult['isSuccess'] = isSuccess;
        paymentResult['error'] = data['error'] as String?;
        debugPrint('[CoinosService] Payment result: $paymentResult');
        debugPrint('[CoinosService] Payment success: $isSuccess');

        return Result.success(paymentResult);
      } else if (response.statusCode == 401) {
        await clearAuthData();
        return const Result.error('Authentication token expired');
      } else {
        debugPrint('[CoinosService] Payment failed: ${response.statusCode}');
        return Result.error('Payment failed: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      debugPrint('[CoinosService] Payment error: $e');
      return Result.error('Payment failed: $e');
    }
  }

  Future<Result<Map<String, dynamic>>> sendInternalPayment({
    required String username,
    required int amount,
  }) async {
    return _makeAuthenticatedRequest(
      '/send',
      'POST',
      (json) {
        final jsonMap = json;
        final successValue = jsonMap['success'] as bool?;
        final statusValue = jsonMap['status'] as String?;
        final isSuccess = successValue ?? (statusValue == 'success');
        final result = Map<String, dynamic>.from(jsonMap);
        result['isSuccess'] = isSuccess;
        result['error'] = jsonMap['error'] as String?;
        return result;
      },
      body: {
        'username': username,
        'amount': amount,
      },
    );
  }

  Future<Result<Map<String, dynamic>>> sendBitcoinPayment({
    required String address,
    required int amount,
  }) async {
    return _makeAuthenticatedRequest(
      '/bitcoin/send',
      'POST',
      (json) {
        final jsonMap = json;
        final successValue = jsonMap['success'] as bool?;
        final statusValue = jsonMap['status'] as String?;
        final isSuccess = successValue ?? (statusValue == 'success');
        final result = Map<String, dynamic>.from(jsonMap);
        result['isSuccess'] = isSuccess;
        result['error'] = jsonMap['error'] as String?;
        return result;
      },
      body: {
        'address': address,
        'amount': amount,
      },
    );
  }

  Future<Result<List<Map<String, dynamic>>>> getPaymentHistory({
    int? start,
    int? end,
    int? limit,
    int? offset,
  }) async {
    final queryParams = <String, String>{};
    if (start != null) queryParams['start'] = start.toString();
    if (end != null) queryParams['end'] = end.toString();
    if (limit != null) queryParams['limit'] = limit.toString();
    if (offset != null) queryParams['offset'] = offset.toString();

    final queryString = queryParams.isNotEmpty ? '?${Uri(queryParameters: queryParams).query}' : '';
    final endpoint = '/payments$queryString';

    return _makeAuthenticatedRequest(
      endpoint,
      'GET',
      (json) {
        final jsonMap = json;
        final payments = jsonMap['payments'] as List<dynamic>?;
        if (payments != null) {
          return payments.map((p) => p as Map<String, dynamic>).toList();
        }
        if (json is List) {
          return (json as List).map((p) => p as Map<String, dynamic>).toList();
        }
        return <Map<String, dynamic>>[];
      },
    );
  }

  Future<Result<Map<String, dynamic>>> updateAccount({
    String? username,
    String? display,
    String? currency,
    String? language,
  }) async {
    final updateData = <String, dynamic>{};
    if (username != null) updateData['username'] = username;
    if (display != null) updateData['display'] = display;
    if (currency != null) updateData['currency'] = currency;
    if (language != null) updateData['language'] = language;

    return _makeAuthenticatedRequest(
      '/user',
      'POST',
      (json) => json,
      body: updateData,
    );
  }

  Future<Result<bool>> isAuthenticated() async {
    try {
      final tokenResult = await getStoredToken();
      if (tokenResult.isError || tokenResult.data == null) {
        return Result.success(false);
      }

      final accountResult = await getAccountInfo();
      return Result.success(accountResult.isSuccess);
    } catch (e) {
      return Result.success(false);
    }
  }

  Future<Result<void>> clearAuthData() async {
    try {
      await Future.wait([
        _secureStorage.delete(key: _tokenKey),
        _secureStorage.delete(key: _userKey),
        _secureStorage.delete(key: _usernameKey),
        _secureStorage.delete(key: _passwordKey),
      ]);

      _cachedToken = null;
      _cachedUser = null;

      debugPrint('[CoinosService] Auth data cleared');
      return const Result.success(null);
    } catch (e) {
      return Result.error('Failed to clear auth data: $e');
    }
  }

  void dispose() {
    _httpClient.close();
  }
}
