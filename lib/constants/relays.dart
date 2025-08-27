import 'package:shared_preferences/shared_preferences.dart';

const List<String> _defaultRelaySetMainSockets = [
  'wss://relay.damus.io',
  'wss://nos.lol',
  'wss://relay.primal.net',
  'wss://vitor.nostr1.com',
];

const List<String> relaySetIndependentFetch = [
  'wss://relay.damus.io',
  'wss://nos.lol',
  'wss://relay.primal.net',
  'wss://vitor.nostr1.com',
];

const String cachingServerUrl = 'wss://cache2.primal.net/v1';

Future<List<String>> getRelaySetMainSockets() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final customRelays = prefs.getStringList('custom_main_relays');
    if (customRelays != null && customRelays.isNotEmpty) {
      return customRelays;
    }
  } catch (e) {
    print('[Relays] Error loading custom relays: $e');
  }
  return List.from(_defaultRelaySetMainSockets);
}

List<String> get relaySetMainSockets => List.from(_defaultRelaySetMainSockets);
