import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../core/base/result.dart';

/// Service responsible for HTTP network operations
/// Handles REST API calls, file uploads, and network connectivity
class NetworkService {
  static final NetworkService _instance = NetworkService._internal();
  factory NetworkService() => _instance;
  NetworkService._internal();

  static NetworkService get instance => _instance;

  static const Duration _defaultTimeout = Duration(seconds: 30);
  static const int _maxRetries = 3;

  final http.Client _httpClient = http.Client();

  /// Check network connectivity
  Future<Result<bool>> checkConnectivity() async {
    try {
      final result = await InternetAddress.lookup('google.com').timeout(const Duration(seconds: 5));

      return Result.success(result.isNotEmpty && result[0].rawAddress.isNotEmpty);
    } catch (e) {
      return const Result.success(false);
    }
  }

  /// Make GET request
  Future<Result<Map<String, dynamic>>> get(
    String url, {
    Map<String, String>? headers,
    Duration timeout = _defaultTimeout,
  }) async {
    try {
      final uri = Uri.parse(url);
      final response = await _httpClient.get(uri, headers: headers).timeout(timeout);

      return _handleResponse(response);
    } catch (e) {
      return Result.error(_handleError(e));
    }
  }

  /// Make POST request
  Future<Result<Map<String, dynamic>>> post(
    String url, {
    Map<String, dynamic>? body,
    Map<String, String>? headers,
    Duration timeout = _defaultTimeout,
  }) async {
    try {
      final uri = Uri.parse(url);
      final defaultHeaders = {
        'Content-Type': 'application/json',
        ...?headers,
      };

      final response = await _httpClient
          .post(
            uri,
            headers: defaultHeaders,
            body: body != null ? jsonEncode(body) : null,
          )
          .timeout(timeout);

      return _handleResponse(response);
    } catch (e) {
      return Result.error(_handleError(e));
    }
  }

  /// Make PUT request
  Future<Result<Map<String, dynamic>>> put(
    String url, {
    Map<String, dynamic>? body,
    Map<String, String>? headers,
    Duration timeout = _defaultTimeout,
  }) async {
    try {
      final uri = Uri.parse(url);
      final defaultHeaders = {
        'Content-Type': 'application/json',
        ...?headers,
      };

      final response = await _httpClient
          .put(
            uri,
            headers: defaultHeaders,
            body: body != null ? jsonEncode(body) : null,
          )
          .timeout(timeout);

      return _handleResponse(response);
    } catch (e) {
      return Result.error(_handleError(e));
    }
  }

  /// Upload file to server
  Future<Result<String>> uploadFile(
    String url,
    File file, {
    Map<String, String>? headers,
    String fieldName = 'file',
    Duration timeout = _defaultTimeout,
  }) async {
    try {
      final uri = Uri.parse(url);
      final request = http.MultipartRequest('POST', uri);

      // Add headers
      if (headers != null) {
        request.headers.addAll(headers);
      }

      // Add file
      final fileStream = http.ByteStream(file.openRead());
      final fileLength = await file.length();
      final multipartFile = http.MultipartFile(
        fieldName,
        fileStream,
        fileLength,
        filename: file.path.split('/').last,
      );
      request.files.add(multipartFile);

      // Send request
      final streamedResponse = await request.send().timeout(timeout);
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        try {
          final responseData = jsonDecode(response.body) as Map<String, dynamic>;
          final url = responseData['url'] as String?;

          if (url != null && url.isNotEmpty) {
            return Result.success(url);
          } else {
            return const Result.error('Upload succeeded but no URL returned');
          }
        } catch (e) {
          // Response might not be JSON, try to extract URL from plain text
          final body = response.body.trim();
          if (body.startsWith('http')) {
            return Result.success(body);
          } else {
            return const Result.error('Upload succeeded but response format is invalid');
          }
        }
      } else {
        return Result.error('Upload failed with status ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      return Result.error(_handleError(e));
    }
  }

  /// Upload file with authentication
  Future<Result<String>> uploadFileWithAuth(
    String url,
    File file,
    String authHeader, {
    String fieldName = 'file',
    Duration timeout = _defaultTimeout,
  }) async {
    return uploadFile(
      url,
      file,
      headers: {'Authorization': authHeader},
      fieldName: fieldName,
      timeout: timeout,
    );
  }

  /// Make request with retry logic
  Future<Result<Map<String, dynamic>>> getWithRetry(
    String url, {
    Map<String, String>? headers,
    Duration timeout = _defaultTimeout,
    int maxRetries = _maxRetries,
  }) async {
    int attempts = 0;

    while (attempts < maxRetries) {
      final result = await get(url, headers: headers, timeout: timeout);

      if (result.isSuccess) {
        return result;
      }

      attempts++;
      if (attempts < maxRetries) {
        // Progressive delay: 1s, 2s, 4s...
        final delay = Duration(seconds: 1 << (attempts - 1));
        await Future.delayed(delay);
      }
    }

    return await get(url, headers: headers, timeout: timeout);
  }

  /// Verify NIP-05 identifier
  Future<Result<bool>> verifyNip05(String nip05, String pubkeyHex) async {
    try {
      if (!nip05.contains('@')) {
        return const Result.error('Invalid NIP-05 format');
      }

      final parts = nip05.split('@');
      if (parts.length != 2) {
        return const Result.error('Invalid NIP-05 format');
      }

      final name = parts[0];
      final domain = parts[1];

      final url = 'https://$domain/.well-known/nostr.json?name=$name';
      final response = await _httpClient.get(Uri.parse(url)).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final names = data['names'] as Map<String, dynamic>? ?? {};

        final registeredPubkey = names[name] as String?;
        return Result.success(registeredPubkey == pubkeyHex);
      } else {
        return const Result.error('NIP-05 verification server error');
      }
    } catch (e) {
      return Result.error('NIP-05 verification failed: ${_handleError(e)}');
    }
  }

  /// Download file from URL
  Future<Result<List<int>>> downloadFile(
    String url, {
    Map<String, String>? headers,
    Duration timeout = _defaultTimeout,
  }) async {
    try {
      final uri = Uri.parse(url);
      final response = await _httpClient.get(uri, headers: headers).timeout(timeout);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return Result.success(response.bodyBytes);
      } else {
        return Result.error('Download failed with status ${response.statusCode}');
      }
    } catch (e) {
      return Result.error(_handleError(e));
    }
  }

  /// Handle HTTP response
  Result<Map<String, dynamic>> _handleResponse(http.Response response) {
    try {
      if (response.statusCode >= 200 && response.statusCode < 300) {
        if (response.body.isEmpty) {
          return const Result.success({});
        }

        final data = jsonDecode(response.body);
        if (data is Map<String, dynamic>) {
          return Result.success(data);
        } else {
          return Result.success({'data': data});
        }
      } else {
        return Result.error(_getHttpErrorMessage(response.statusCode, response.body));
      }
    } catch (e) {
      return Result.error('Failed to parse response: ${e.toString()}');
    }
  }

  /// Get user-friendly HTTP error message
  String _getHttpErrorMessage(int statusCode, String body) {
    switch (statusCode) {
      case 400:
        return 'Bad request - please check your input';
      case 401:
        return 'Authentication required';
      case 403:
        return 'Access forbidden';
      case 404:
        return 'Resource not found';
      case 429:
        return 'Too many requests - please try again later';
      case 500:
        return 'Server error - please try again later';
      case 502:
        return 'Bad gateway - server is temporarily unavailable';
      case 503:
        return 'Service unavailable - please try again later';
      default:
        return 'Network error (status: $statusCode)';
    }
  }

  /// Handle and convert errors to user-friendly messages
  String _handleError(dynamic error) {
    if (error is SocketException) {
      return 'No internet connection';
    } else if (error is TimeoutException) {
      return 'Request timed out';
    } else if (error is HttpException) {
      return 'HTTP error: ${error.message}';
    } else if (error is FormatException) {
      return 'Invalid response format';
    } else {
      return 'Network error: ${error.toString()}';
    }
  }

  /// Get network status information
  Future<Result<NetworkStatus>> getNetworkStatus() async {
    try {
      final connectivityResult = await checkConnectivity();

      return connectivityResult.fold(
        (isConnected) async {
          if (!isConnected) {
            return const Result.success(NetworkStatus(
              isConnected: false,
              latency: null,
              quality: NetworkQuality.none,
            ));
          }

          // Measure latency
          final stopwatch = Stopwatch()..start();
          await get('https://httpbin.org/get').timeout(const Duration(seconds: 5));
          stopwatch.stop();

          final latency = stopwatch.elapsedMilliseconds;
          final quality = _getNetworkQuality(latency);

          return Result.success(NetworkStatus(
            isConnected: true,
            latency: latency,
            quality: quality,
          ));
        },
        (error) => Result.error(error),
      );
    } catch (e) {
      return const Result.success(NetworkStatus(
        isConnected: false,
        latency: null,
        quality: NetworkQuality.none,
      ));
    }
  }

  /// Determine network quality based on latency
  NetworkQuality _getNetworkQuality(int latencyMs) {
    if (latencyMs < 100) return NetworkQuality.excellent;
    if (latencyMs < 300) return NetworkQuality.good;
    if (latencyMs < 600) return NetworkQuality.fair;
    return NetworkQuality.poor;
  }

  /// Close HTTP client and cleanup resources
  void dispose() {
    _httpClient.close();
  }
}

/// Network status information
class NetworkStatus {
  final bool isConnected;
  final int? latency; // in milliseconds
  final NetworkQuality quality;

  const NetworkStatus({
    required this.isConnected,
    this.latency,
    required this.quality,
  });

  @override
  String toString() => 'NetworkStatus(connected: $isConnected, latency: ${latency}ms, quality: $quality)';
}

/// Network quality levels
enum NetworkQuality {
  none, // No connection
  poor, // >600ms
  fair, // 300-600ms
  good, // 100-300ms
  excellent, // <100ms
}
