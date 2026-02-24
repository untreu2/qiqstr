import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

const List<String> _defaultRelaySetMainSockets = [
  'wss://relay.damus.io',
  'wss://nos.lol',
  'wss://relay.primal.net',
  'wss://vitor.nostr1.com',
];

const List<String> discoveryRelays = [
  'wss://relay.damus.io',
  'wss://nos.lol',
  'wss://relay.primal.net',
  'wss://vitor.nostr1.com',
  'wss://nostr.bitcoiner.social',
  'wss://nostr.mom',
];

enum GossipMode { normal, aggressive, psycho }

const Map<GossipMode, int> gossipMaxOutboxRelays = {
  GossipMode.normal: 30,
  GossipMode.aggressive: 100,
  GossipMode.psycho: 1000,
};

const Map<GossipMode, int> gossipMinRelayFrequency = {
  GossipMode.normal: 2,
  GossipMode.aggressive: 1,
  GossipMode.psycho: 0,
};

GossipMode gossipModeFromString(String value) {
  switch (value) {
    case 'aggressive':
      return GossipMode.aggressive;
    case 'psycho':
      return GossipMode.psycho;
    default:
      return GossipMode.normal;
  }
}

Future<GossipMode> getGossipMode() async {
  final prefs = await SharedPreferences.getInstance();
  final value = prefs.getString('gossip_mode') ?? 'normal';
  return gossipModeFromString(value);
}

Future<void> setGossipMode(GossipMode mode) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('gossip_mode', mode.name);
}

const String primalCacheUrl = 'wss://cache2.primal.net/v1';

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
