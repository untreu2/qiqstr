import 'dart:io';

class RelayService {
  Future<WebSocket> connectToRelay(String relayUrl) async {
    try {
      WebSocket webSocket = await WebSocket.connect(relayUrl);
      return webSocket;
    } catch (e) {
      print("Error connecting to relay: $e");
      rethrow;
    }
  }

  Future<void> closeRelayConnection(WebSocket webSocket) async {
    try {
      await webSocket.close();
    } catch (e) {
      print("Error closing relay connection: $e");
    }
  }

  Future<void> sendEvent(WebSocket webSocket, String eventJson) async {
    webSocket.add(eventJson);
  }

  Stream<String> listenToRelay(WebSocket webSocket) {
    return webSocket.map((event) => event.toString());
  }
}
