import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

const List<String> _defaultRelaySetMainSockets = [
  'wss://relay.damus.io',
  'wss://nos.lol',
  'wss://relay.primal.net',
  'wss://vitor.nostr1.com',
];

const String countRelayUrl = 'wss://relay.nostr.band/';

Future<List<String>> getRelaySetMainSockets() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final customRelays = prefs.getStringList('custom_main_relays');
    if (customRelays != null && customRelays.isNotEmpty) {
      return customRelays;
    }
  } catch (e) {
    if (kDebugMode) {
      print('[Relays] Error loading custom relays: $e');
    }
  }
  return List.from(_defaultRelaySetMainSockets);
}

List<String> get relaySetMainSockets => List.from(_defaultRelaySetMainSockets);
