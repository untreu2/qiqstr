import 'package:flutter/foundation.dart';
import '../services/network_service.dart';
import '../constants/relays.dart';

class NetworkProvider extends ChangeNotifier {
  static NetworkProvider? _instance;
  static NetworkProvider get instance => _instance ??= NetworkProvider._internal();

  NetworkProvider._internal();

  NetworkService? _networkService;
  bool _isInitialized = false;
  bool _isConnecting = false;
  String? _errorMessage;

  bool _isOnline = true;

  final List<Map<String, dynamic>> _pendingRequests = [];
  bool _isProcessingQueue = false;

  bool get isInitialized => _isInitialized;
  bool get isConnecting => _isConnecting;
  bool get isOnline => _isOnline;
  bool get isConnected => (_networkService?.connectedRelaysCount ?? 0) > 0;
  int get connectedRelaysCount => _networkService?.connectedRelaysCount ?? 0;
  String? get errorMessage => _errorMessage;
  List<Map<String, dynamic>> get pendingRequests => List.unmodifiable(_pendingRequests);
  bool get hasPendingRequests => _pendingRequests.isNotEmpty;

  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      _networkService = NetworkService.instance;
      _isInitialized = true;
      _errorMessage = null;
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to initialize network service: $e';
      debugPrint('[NetworkProvider] Initialization error: $e');
      notifyListeners();
    }
  }

  Future<void> connectToNetwork(List<String> targetNpubs) async {
    if (!_isInitialized || _networkService == null) {
      await initialize();
    }

    if (_isConnecting) return;

    _isConnecting = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await _networkService!.initializeConnections(targetNpubs);
      _isOnline = true;
      _isConnecting = false;

      if (_pendingRequests.isNotEmpty) {
        _processPendingRequests();
      }

      notifyListeners();
    } catch (e) {
      _isConnecting = false;
      _isOnline = false;
      _errorMessage = 'Failed to connect to network: $e';
      debugPrint('[NetworkProvider] Connection error: $e');
      notifyListeners();
    }
  }

  Future<void> broadcastMessage(String message, {bool immediate = false}) async {
    if (_networkService == null) {
      _queueRequest('broadcast', {'message': message, 'immediate': immediate});
      return;
    }

    try {
      if (immediate) {
        await _networkService!.immediateBroadcast(message);
      } else {
        await _networkService!.broadcastRequest(message);
      }
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to broadcast message: $e';
      _queueRequest('broadcast', {'message': message, 'immediate': immediate});
      debugPrint('[NetworkProvider] Broadcast error: $e');
      notifyListeners();
      rethrow;
    }
  }

  Future<void> broadcastUserReaction(String targetEventId, String reactionContent) async {
    if (_networkService == null) {
      _queueRequest('reaction', {
        'targetEventId': targetEventId,
        'reactionContent': reactionContent,
      });
      return;
    }

    try {
      await _networkService!.broadcastUserReaction(targetEventId, reactionContent);
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to send reaction: $e';
      _queueRequest('reaction', {
        'targetEventId': targetEventId,
        'reactionContent': reactionContent,
      });
      debugPrint('[NetworkProvider] Reaction error: $e');
      notifyListeners();
      rethrow;
    }
  }

  Future<void> broadcastUserReply(String parentEventId, String replyContent, String parentAuthor) async {
    if (_networkService == null) {
      _queueRequest('reply', {
        'parentEventId': parentEventId,
        'replyContent': replyContent,
        'parentAuthor': parentAuthor,
      });
      return;
    }

    try {
      await _networkService!.broadcastUserReply(parentEventId, replyContent, parentAuthor);
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to send reply: $e';
      _queueRequest('reply', {
        'parentEventId': parentEventId,
        'replyContent': replyContent,
        'parentAuthor': parentAuthor,
      });
      debugPrint('[NetworkProvider] Reply error: $e');
      notifyListeners();
      rethrow;
    }
  }

  Future<void> broadcastUserRepost(String noteId, String noteAuthor, String? rawContent) async {
    if (_networkService == null) {
      _queueRequest('repost', {
        'noteId': noteId,
        'noteAuthor': noteAuthor,
        'rawContent': rawContent,
      });
      return;
    }

    try {
      await _networkService!.broadcastUserRepost(noteId, noteAuthor, rawContent);
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to send repost: $e';
      _queueRequest('repost', {
        'noteId': noteId,
        'noteAuthor': noteAuthor,
        'rawContent': rawContent,
      });
      debugPrint('[NetworkProvider] Repost error: $e');
      notifyListeners();
      rethrow;
    }
  }

  Future<void> broadcastUserNote(String noteContent) async {
    if (_networkService == null) {
      _queueRequest('note', {'noteContent': noteContent});
      return;
    }

    try {
      await _networkService!.broadcastUserNote(noteContent);
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to send note: $e';
      _queueRequest('note', {'noteContent': noteContent});
      debugPrint('[NetworkProvider] Note error: $e');
      notifyListeners();
      rethrow;
    }
  }

  Future<String> sendZap({
    required String recipientPubkey,
    required String lud16,
    required int amountSats,
    String? noteId,
    String content = '',
  }) async {
    if (_networkService == null) {
      throw Exception('Network service not initialized');
    }

    try {
      final invoice = await _networkService!.sendZap(
        recipientPubkey: recipientPubkey,
        lud16: lud16,
        amountSats: amountSats,
        noteId: noteId,
        content: content,
      );
      notifyListeners();
      return invoice;
    } catch (e) {
      _errorMessage = 'Failed to send zap: $e';
      debugPrint('[NetworkProvider] Zap error: $e');
      notifyListeners();
      rethrow;
    }
  }

  Future<String> uploadMedia(String filePath, String blossomUrl) async {
    if (_networkService == null) {
      throw Exception('Network service not initialized');
    }

    try {
      final url = await _networkService!.uploadMedia(filePath, blossomUrl);
      notifyListeners();
      return url;
    } catch (e) {
      _errorMessage = 'Failed to upload media: $e';
      debugPrint('[NetworkProvider] Media upload error: $e');
      notifyListeners();
      rethrow;
    }
  }

  void _queueRequest(String type, Map<String, dynamic> params) {
    _pendingRequests.add({
      'type': type,
      'params': params,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });

    if (_pendingRequests.length > 100) {
      _pendingRequests.removeAt(0);
    }

    notifyListeners();
  }

  Future<void> _processPendingRequests() async {
    if (_isProcessingQueue || _pendingRequests.isEmpty || _networkService == null) {
      return;
    }

    _isProcessingQueue = true;
    final requestsToProcess = List<Map<String, dynamic>>.from(_pendingRequests);
    _pendingRequests.clear();

    for (final request in requestsToProcess) {
      try {
        final type = request['type'] as String;
        final params = request['params'] as Map<String, dynamic>;

        switch (type) {
          case 'broadcast':
            if (params['immediate'] == true) {
              await _networkService!.immediateBroadcast(params['message']);
            } else {
              await _networkService!.broadcastRequest(params['message']);
            }
            break;
          case 'reaction':
            await _networkService!.broadcastUserReaction(
              params['targetEventId'],
              params['reactionContent'],
            );
            break;
          case 'reply':
            await _networkService!.broadcastUserReply(
              params['parentEventId'],
              params['replyContent'],
              params['parentAuthor'],
            );
            break;
          case 'repost':
            await _networkService!.broadcastUserRepost(
              params['noteId'],
              params['noteAuthor'],
              params['rawContent'],
            );
            break;
          case 'note':
            await _networkService!.broadcastUserNote(params['noteContent']);
            break;
        }

        await Future.delayed(const Duration(milliseconds: 100));
      } catch (e) {
        debugPrint('[NetworkProvider] Failed to process queued request: $e');

        _pendingRequests.add(request);
      }
    }

    _isProcessingQueue = false;
    notifyListeners();
  }

  void clearPendingRequests() {
    _pendingRequests.clear();
    notifyListeners();
  }

  void retryPendingRequests() {
    if (_networkService != null && _pendingRequests.isNotEmpty) {
      _processPendingRequests();
    }
  }

  Future<void> checkConnectionHealth() async {
    if (_networkService != null) {
      final connectedCount = _networkService!.connectedRelaysCount;
      _isOnline = connectedCount > 0;
      notifyListeners();
    }
  }

  String getConnectionStatusText() {
    if (!_isInitialized) return 'Not initialized';
    if (_isConnecting) return 'Connecting...';
    if (!_isOnline) return 'Offline';
    if (connectedRelaysCount == 0) return 'Disconnected';
    return '$connectedRelaysCount relays connected';
  }

  Future<void> closeConnections() async {
    if (_networkService != null) {
      await _networkService!.closeConnections();
      _networkService = null;
    }

    _isInitialized = false;
    _isConnecting = false;
    _isOnline = false;
    _errorMessage = null;
    notifyListeners();
  }

  @override
  void dispose() {
    closeConnections();
    super.dispose();
  }
}
