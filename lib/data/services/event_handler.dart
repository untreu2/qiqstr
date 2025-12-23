class EventHandler {
  static void route(
    List<dynamic> decoded,
    String relayUrl, {
    Map<String, Map<String, Function(List<dynamic>, String)>>? subscriptionHandlers,
    void Function(Map<String, dynamic> event, String relayUrl)? onEvent,
    void Function(List<dynamic> countMsg, String relayUrl)? onCount,
    void Function(List<dynamic> closedMsg, String relayUrl)? onClosed,
    void Function(List<dynamic> eoseMsg, String relayUrl)? onEose,
  }) {
    if (decoded.isEmpty) return;
    final messageType = decoded[0];

    if ((messageType == 'EVENT' || messageType == 'EOSE' || messageType == 'CLOSED') && decoded.length >= 2 && subscriptionHandlers != null) {
      final subscriptionId = decoded[1] as String;
      final subs = subscriptionHandlers[relayUrl];
      final handler = subs != null ? subs[subscriptionId] : null;
      if (handler != null) {
        try {
          handler(decoded, relayUrl);
        } catch (_) {}
      }
    }

    if (messageType == 'EVENT' && decoded.length >= 3 && onEvent != null) {
      final event = decoded[2] as Map<String, dynamic>;
      onEvent(event, relayUrl);
    } else if (messageType == 'COUNT' && onCount != null) {
      onCount(decoded, relayUrl);
    } else if (messageType == 'CLOSED' && onClosed != null) {
      onClosed(decoded, relayUrl);
    } else if (messageType == 'EOSE' && onEose != null) {
      onEose(decoded, relayUrl);
    }
  }
}

