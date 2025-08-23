import 'package:flutter/foundation.dart';
import '../services/relay_service.dart';
import '../constants/relays.dart';

class RelayProvider extends ChangeNotifier {
  static RelayProvider? _instance;
  static RelayProvider get instance => _instance ??= RelayProvider._internal();

  RelayProvider._internal();

  WebSocketManager? _socketManager;
  bool _isInitialized = false;
  bool _isConnecting = false;
  List<String> _connectedRelays = [];
  String? _errorMessage;

  bool get isInitialized => _isInitialized;
  bool get isConnecting => _isConnecting;
  bool get isConnected => _connectedRelays.isNotEmpty;
  List<String> get connectedRelays => List.unmodifiable(_connectedRelays);
  String? get errorMessage => _errorMessage;
  int get connectedRelaysCount => _connectedRelays.length;
  int get totalRelaysCount => relaySetMainSockets.length;

  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      _socketManager = WebSocketManager(relayUrls: relaySetMainSockets);
      _isInitialized = true;
      _errorMessage = null;
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to initialize relay manager: $e';
      debugPrint('[RelayProvider] Initialization error: $e');
      notifyListeners();
    }
  }

  Future<void> connectToRelays(List<String> targetNpubs) async {
    if (!_isInitialized || _socketManager == null) {
      await initialize();
    }

    if (_isConnecting) return;

    _isConnecting = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await _socketManager!.connectRelays(
        targetNpubs,
        onEvent: (event, relayUrl) => _handleRelayEvent(event, relayUrl),
        onDisconnected: (relayUrl) => _handleRelayDisconnected(relayUrl),
      );

      _updateConnectionStatus();
      _isConnecting = false;
      notifyListeners();
    } catch (e) {
      _isConnecting = false;
      _errorMessage = 'Failed to connect to relays: $e';
      debugPrint('[RelayProvider] Connection error: $e');
      notifyListeners();
    }
  }

  void _handleRelayEvent(dynamic event, String relayUrl) {
    if (!_connectedRelays.contains(relayUrl)) {
      _connectedRelays.add(relayUrl);
      notifyListeners();
    }
  }

  void _handleRelayDisconnected(String relayUrl) {
    _connectedRelays.remove(relayUrl);
    notifyListeners();
  }

  void _updateConnectionStatus() {
    if (_socketManager != null) {
      _connectedRelays = _socketManager!.activeSockets
          .map((ws) => relaySetMainSockets.firstWhere(
                (url) => _socketManager!.activeSockets.contains(ws),
                orElse: () => 'unknown',
              ))
          .where((url) => url != 'unknown')
          .toList();
    }
  }

  Future<void> broadcastMessage(String message) async {
    if (_socketManager == null) {
      throw Exception('Relay manager not initialized');
    }

    try {
      await _socketManager!.broadcast(message);
    } catch (e) {
      _errorMessage = 'Failed to broadcast message: $e';
      debugPrint('[RelayProvider] Broadcast error: $e');
      notifyListeners();
      rethrow;
    }
  }

  Future<void> immediateBroadcast(String message) async {
    if (_socketManager == null) {
      throw Exception('Relay manager not initialized');
    }

    try {
      await _socketManager!.immediateBroadcast(message);
    } catch (e) {
      _errorMessage = 'Failed to immediate broadcast: $e';
      debugPrint('[RelayProvider] Immediate broadcast error: $e');
      notifyListeners();
      rethrow;
    }
  }

  Future<void> broadcastToAllRelays(String message) async {
    if (_socketManager == null) {
      throw Exception('Relay manager not initialized');
    }

    try {
      await _socketManager!.immediateBroadcastToAll(message);
    } catch (e) {
      _errorMessage = 'Failed to broadcast to all relays: $e';
      debugPrint('[RelayProvider] Broadcast to all error: $e');
      notifyListeners();
      rethrow;
    }
  }

  void reconnectRelay(String relayUrl, List<String> targetNpubs) {
    if (_socketManager == null) return;

    _socketManager!.reconnectRelay(
      relayUrl,
      targetNpubs,
      onReconnected: (url) {
        if (!_connectedRelays.contains(url)) {
          _connectedRelays.add(url);
          notifyListeners();
        }
      },
    );
  }

  String getConnectionStatusText() {
    if (!_isInitialized) return 'Not initialized';
    if (_isConnecting) return 'Connecting...';
    if (_connectedRelays.isEmpty) return 'Disconnected';
    if (_connectedRelays.length == totalRelaysCount) return 'All relays connected';
    return '${_connectedRelays.length}/${totalRelaysCount} relays connected';
  }

  Future<void> closeConnections() async {
    if (_socketManager != null) {
      await _socketManager!.closeConnections();
      _socketManager = null;
    }

    _connectedRelays.clear();
    _isInitialized = false;
    _isConnecting = false;
    _errorMessage = null;
    notifyListeners();
  }

  @override
  void dispose() {
    closeConnections();
    super.dispose();
  }
}
