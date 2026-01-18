import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ndk/ndk.dart';
import 'package:ndk/shared/nips/nip01/bip340.dart';
import 'package:carbon_icons/carbon_icons.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import '../../theme/theme_manager.dart';
import '../../../constants/relays.dart';
import '../../../core/di/app_di.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../data/services/nostr_service.dart';
import '../../../data/services/relay_service.dart';
import '../../widgets/common/common_buttons.dart';
import '../../widgets/common/snackbar_widget.dart';
import '../../widgets/common/title_widget.dart';
import '../../widgets/common/top_action_bar_widget.dart';
import '../../widgets/dialogs/reset_relays_dialog.dart';
import '../../widgets/dialogs/add_relay_dialog.dart';
import '../../widgets/dialogs/following_relays_dialog.dart';
import '../../widgets/dialogs/broadcast_events_dialog.dart';
import '../../../data/services/event_counts_service.dart';

class RelayInfo {
  final String? name;
  final String? description;
  final String? banner;
  final String? icon;
  final String? pubkey;
  final String? contact;
  final List<int>? supportedNips;
  final String? software;
  final String? version;
  final Map<String, dynamic>? limitation;
  final bool? paymentRequired;
  final bool? authRequired;

  RelayInfo({
    this.name,
    this.description,
    this.banner,
    this.icon,
    this.pubkey,
    this.contact,
    this.supportedNips,
    this.software,
    this.version,
    this.limitation,
    this.paymentRequired,
    this.authRequired,
  });

  factory RelayInfo.fromJson(Map<String, dynamic> json) {
    return RelayInfo(
      name: json['name'] as String?,
      description: json['description'] as String?,
      banner: json['banner'] as String?,
      icon: json['icon'] as String?,
      pubkey: json['pubkey'] as String?,
      contact: json['contact'] as String?,
      supportedNips: json['supported_nips'] != null
          ? List<int>.from(json['supported_nips'] as List)
          : null,
      software: json['software'] as String?,
      version: json['version'] as String?,
      limitation: json['limitation'] as Map<String, dynamic>?,
      paymentRequired: json['limitation']?['payment_required'] as bool?,
      authRequired: json['limitation']?['auth_required'] as bool?,
    );
  }
}

class RelayPage extends StatefulWidget {
  const RelayPage({super.key});

  @override
  State<RelayPage> createState() => _RelayPageState();
}

class _RelayPageState extends State<RelayPage> {
  final TextEditingController _addRelayController = TextEditingController();
  List<String> _relays = [];
  List<Map<String, dynamic>> _userRelays = [];
  bool _isLoading = true;
  bool _isAddingRelay = false;
  bool _isFetchingUserRelays = false;
  bool _isPublishingRelays = false;
  bool _disposed = false;
  final Map<String, RelayInfo?> _relayInfos = {};
  final Map<String, bool> _expandedRelays = {};
  final Map<String, Map<String, dynamic>> _relayStats = {};
  late ScrollController _scrollController;
  final ValueNotifier<bool> _showTitleBubble = ValueNotifier(false);

  late AuthRepository _authRepository;

  @override
  void initState() {
    super.initState();
    _initializeServices();
    _scrollController = ScrollController()..addListener(_scrollListener);
    _loadRelays();
    _loadRelayStats();
    _startStatsRefresh();
  }

  void _scrollListener() {
    if (_scrollController.hasClients) {
      final shouldShow = _scrollController.offset > 100;
      if (_showTitleBubble.value != shouldShow) {
        _showTitleBubble.value = shouldShow;
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _scrollController.dispose();
    _showTitleBubble.dispose();
    _addRelayController.dispose();
    super.dispose();
  }

  void _initializeServices() {
    _authRepository = AppDI.get<AuthRepository>();
  }

  void _startStatsRefresh() {
    Timer.periodic(const Duration(seconds: 2), (timer) {
      if (_disposed) {
        timer.cancel();
        return;
      }
      _loadRelayStats();
    });
  }

  void _loadRelayStats() {
    if (_disposed) return;
    final manager = WebSocketManager.instance;
    final stats = manager.getConnectionStats();
    setState(() {
      _relayStats.clear();
      if (stats['relayStats'] != null) {
        _relayStats.addAll(Map<String, Map<String, dynamic>>.from(stats['relayStats'] as Map));
      }
    });
  }

  Future<void> _loadRelays() async {
    setState(() => _isLoading = true);

    try {
      final prefs = await SharedPreferences.getInstance();

      final customMainRelays = prefs.getStringList('custom_main_relays');
      final userRelaysJson = prefs.getString('user_relays');

      if (userRelaysJson != null) {
        final List<dynamic> decoded = jsonDecode(userRelaysJson);
        _userRelays = decoded.cast<Map<String, dynamic>>();
      }

      setState(() {
        _relays = customMainRelays ?? List.from(relaySetMainSockets);
        _isLoading = false;
      });

      for (final relay in _relays) {
        _fetchRelayInfo(relay);
      }
    } catch (e) {
      setState(() {
        _relays = List.from(relaySetMainSockets);
        _isLoading = false;
      });
      if (mounted) {
        AppSnackbar.error(context, 'Error loading relays: ${e.toString()}');
      }
    }
  }

  Future<void> _fetchRelayInfo(String relayUrl) async {
    if (_relayInfos.containsKey(relayUrl)) return;

    try {
      final uri = Uri.parse(relayUrl).replace(scheme: 'https');
      final response = await http
          .get(uri, headers: {'Accept': 'application/nostr+json'})
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final decoded = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
        if (mounted && !_disposed) {
          setState(() {
            _relayInfos[relayUrl] = RelayInfo.fromJson(decoded);
          });
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error fetching relay info for $relayUrl: $e');
      }
      if (mounted && !_disposed) {
        setState(() {
          _relayInfos[relayUrl] = null;
        });
      }
    }
  }


  Future<void> _publishRelays() async {
    if (!mounted) return;

    setState(() {
      _isPublishingRelays = true;
    });

    try {
      final privateKeyResult = await _authRepository.getCurrentUserPrivateKey();
      if (privateKeyResult.isError || privateKeyResult.data == null) {
        AppSnackbar.error(context, 'Private key not found. Please set up your profile first');
        return;
      }

      final npubResult = await _authRepository.getCurrentUserNpub();
      if (npubResult.isError || npubResult.data == null) {
        AppSnackbar.error(context, 'Please set up your profile first');
        return;
      }

      final privateKey = privateKeyResult.data!;

      List<List<String>> relayTags = [];
      for (String relay in _relays) {
        relayTags.add(['r', relay]);
      }

      final publicKey = Bip340.getPublicKey(privateKey);
      final event = Nip01Event(
        pubKey: publicKey,
        kind: 10002,
        tags: relayTags,
        content: '',
      );
      event.sig = Bip340.sign(event.id, privateKey);

      final serializedEvent = NostrService.serializeEvent(event);

      await _broadcastRelayListEvent(serializedEvent);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('published_relay_list', jsonEncode(NostrService.eventToJson(event)));

      AppSnackbar.success(context, 'Relay list published successfully (${relayTags.length} relays in list)');

      if (kDebugMode) {
        print('Relay list event published: ${event.id}');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error publishing relays: $e');
      }
      AppSnackbar.error(context, 'Error publishing relay list: ${e.toString()}');
    } finally {
      if (mounted) {
        setState(() {
          _isPublishingRelays = false;
        });
      }
    }
  }

  Future<void> _broadcastRelayListEvent(String serializedEvent) async {
    final List<Future<bool>> broadcastFutures = [];

    for (final relayUrl in _relays) {
      broadcastFutures.add(_sendToRelay(relayUrl, serializedEvent));
    }

    try {
      final results = await Future.wait(broadcastFutures, eagerError: false);
      final successfulBroadcasts = results.where((success) => success).length;

      if (kDebugMode) {
        print('Relay list event broadcasted to $successfulBroadcasts/${_relays.length} relays');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error during relay list broadcast: $e');
      }
    }
  }

  Future<bool> _sendToRelay(String relayUrl, String serializedEvent) async {
    try {
      final manager = WebSocketManager.instance;
      final sent = await manager.sendMessage(relayUrl, serializedEvent);
      return sent;
    } catch (e) {
      if (kDebugMode) {
        print('Failed to send relay list event to $relayUrl: $e');
      }
      return false;
    }
  }

  Future<void> _fetchUserRelays() async {
    setState(() {
      _isFetchingUserRelays = true;
    });

    try {
      final npubResult = await _authRepository.getCurrentUserNpub();
      if (npubResult.isError || npubResult.data == null) {
        throw Exception('User not logged in');
      }

      final npub = npubResult.data!;
      final userRelayList = await _fetchRelayListMetadata(npub);

      if (userRelayList.isNotEmpty) {
        setState(() {
          _userRelays = userRelayList;
        });

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('user_relays', jsonEncode(_userRelays));

        await _useUserRelays();

        if (mounted) {
          AppSnackbar.success(context, 'Found and applied ${_userRelays.length} relays from your profile');
        }
      } else {
        if (mounted) {
          AppSnackbar.info(context, 'No relay list found in your profile');
        }
      }
    } catch (e) {
      if (mounted) {
        AppSnackbar.error(context, 'Error fetching user relays: ${e.toString()}');
      }
    } finally {
      setState(() {
        _isFetchingUserRelays = false;
      });
    }
  }

  Future<List<Map<String, dynamic>>> _fetchRelayListMetadata(String npub) async {
    final List<Map<String, dynamic>> relayList = [];

    try {
      final pubkeyHex = _authRepository.npubToHex(npub) ?? npub;

      final manager = WebSocketManager.instance;

      for (final relayUrl in relaySetMainSockets) {
        try {
          if (_disposed) return relayList;

          final subscriptionId = DateTime.now().millisecondsSinceEpoch.toString();
          final request = jsonEncode([
            "REQ",
            subscriptionId,
            {
              "authors": [pubkeyHex],
              "kinds": [10002],
              "limit": 1
            }
          ]);

          Map<String, dynamic>? eventData;

          final completer = await manager.sendQuery(
            relayUrl,
            request,
            subscriptionId,
            timeout: const Duration(seconds: 5),
            onEvent: (data, url) {
              if (!_disposed) {
                eventData = data;
              }
            },
          );

          await completer.future.timeout(const Duration(seconds: 5), onTimeout: () {});

          if (eventData != null) {
            final tags = eventData!['tags'] as List<dynamic>? ?? [];

            for (final tag in tags) {
              if (tag is List && tag.isNotEmpty && tag[0] == 'r' && tag.length >= 2) {
                final relayUrl = tag[1] as String;
                String marker = '';

                if (tag.length >= 3 && tag[2] is String) {
                  marker = tag[2] as String;
                }

                if (marker.isEmpty) {
                  marker = 'read,write';
                }

                relayList.add({
                  'url': relayUrl,
                  'marker': marker,
                });
              }
            }

            if (relayList.isNotEmpty) {
              break;
            }
          }
        } catch (e) {
          if (kDebugMode) {
            print('Error fetching from relay $relayUrl: $e');
          }
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error in _fetchRelayListMetadata: $e');
      }
    }

    return relayList;
  }

  Future<void> _useUserRelays() async {
    if (_userRelays.isEmpty) {
      AppSnackbar.info(context, 'No user relays available. Please fetch them first.');
      return;
    }

    try {
      final previousRelays = Set<String>.from(_relays.map(_normalizeRelayUrl));
      
      final writeRelays = _userRelays
          .where((relay) => relay['marker'] == '' || relay['marker'].contains('write') || relay['marker'].contains('read,write'))
          .map((relay) => relay['url'] as String)
          .toList();

      final newRelays = writeRelays.isNotEmpty ? writeRelays : _userRelays.map((relay) => relay['url'] as String).take(4).toList();

      setState(() {
        _relays = newRelays;
      });

      await _saveRelays();

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('using_user_relays', true);

      if (mounted) {
        AppSnackbar.success(context, 'Now using your personal relays (${newRelays.length} main relays)');
        
        final newRelayUrls = newRelays
            .where((relay) => !previousRelays.contains(_normalizeRelayUrl(relay)))
            .toList();
        
        if (newRelayUrls.isNotEmpty && mounted) {
          final shouldBroadcast = await showBroadcastEventsDialog(
            context: context,
            relayUrls: newRelayUrls,
            relayCount: newRelayUrls.length,
          );

          if (shouldBroadcast && mounted) {
            await _broadcastEventsToRelays(newRelayUrls);
          }
        }
      }
    } catch (e) {
      if (mounted) {
        AppSnackbar.error(context, 'Error applying user relays: ${e.toString()}');
      }
    }
  }

  Future<void> _saveRelays() async {
    try {
      if (kDebugMode) {
        print('[RelayPage] Saving ${_relays.length} relays: $_relays');
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('custom_main_relays', _relays);

      if (kDebugMode) {
        final saved = prefs.getStringList('custom_main_relays');
        print('[RelayPage] Saved to SharedPreferences: $saved');
      }

      if (kDebugMode) {
        print('[RelayPage] Calling reloadCustomRelays...');
      }
      await WebSocketManager.instance.reloadCustomRelays();

      if (mounted) {
        AppSnackbar.success(context, 'Relays saved successfully');
      }
    } catch (e) {
      if (kDebugMode) {
        print('[RelayPage] Error saving relays: $e');
      }
      if (mounted) {
        AppSnackbar.error(context, 'Error saving relays: ${e.toString()}');
      }
    }
  }

  bool _isValidRelayUrl(String url) {
    final trimmed = url.trim();
    return trimmed.startsWith('wss://') || trimmed.startsWith('ws://');
  }

  String _normalizeRelayUrl(String url) {
    final trimmed = url.trim();
    if (trimmed.endsWith('/') && !trimmed.endsWith('://')) {
      return trimmed.substring(0, trimmed.length - 1);
    }
    return trimmed;
  }

  bool _isRelayUrlEqual(String url1, String url2) {
    return _normalizeRelayUrl(url1) == _normalizeRelayUrl(url2);
  }

  Future<void> _addRelay(bool isMainRelay) async {
    final url = _addRelayController.text.trim();

    if (url.isEmpty) {
      AppSnackbar.error(context, 'Please enter a relay URL');
      return;
    }

    if (!_isValidRelayUrl(url)) {
      AppSnackbar.error(context, 'Please enter a valid WebSocket URL (wss:// or ws://)');
      return;
    }

    final targetList = _relays;
    final normalizedUrl = _normalizeRelayUrl(url);

    if (targetList.any((existingUrl) => _isRelayUrlEqual(existingUrl, normalizedUrl))) {
      AppSnackbar.error(context, 'Relay already exists in this category');
      return;
    }

    setState(() => _isAddingRelay = true);

    try {
      setState(() {
        targetList.add(url);
      });

      await _saveRelays();
      _addRelayController.clear();
      _fetchRelayInfo(url);

      if (mounted) {
        context.pop();
        AppSnackbar.success(context, 'Relay added to Main list');
        
        final shouldBroadcast = await showBroadcastEventsDialog(
          context: context,
          relayUrl: normalizedUrl,
        );

        if (shouldBroadcast && mounted) {
          await _broadcastEventsToRelay(normalizedUrl);
        }
      }
    } catch (e) {
      if (mounted) {
        AppSnackbar.error(context, 'Error adding relay: ${e.toString()}');
      }
    } finally {
      setState(() => _isAddingRelay = false);
    }
  }

  Future<void> _broadcastEventsToRelay(String relayUrl) async {
    await _broadcastEventsToRelays([relayUrl]);
  }

  Future<void> _broadcastEventsToRelays(List<String> relayUrls) async {
    if (!mounted || relayUrls.isEmpty) return;

    AppSnackbar.info(context, 'Fetching your events...');

    try {
      final result = await EventCountsService.instance.fetchAllEventsForUser(null);
      
      if (!mounted) return;

      if (result == null || result.allEvents.isEmpty) {
        AppSnackbar.info(context, 'No events found to broadcast');
        return;
      }

      AppSnackbar.info(context, 'Broadcasting ${result.allEvents.length} events...');

      final success = await EventCountsService.instance.rebroadcastEvents(
        result.allEvents,
        relayUrls: relayUrls,
      );

      if (!mounted) return;

      if (success) {
        final relayText = relayUrls.length == 1 ? 'the new relay' : '${relayUrls.length} new relays';
        AppSnackbar.success(
          context,
          'Broadcasted ${result.allEvents.length} events to $relayText',
        );
      } else {
        AppSnackbar.error(context, 'Error broadcasting events');
      }
    } catch (e) {
      if (mounted) {
        AppSnackbar.error(context, 'Error broadcasting events: ${e.toString()}');
      }
    }
  }

  Future<void> _removeRelay(String url, bool isMainRelay) async {
    setState(() {
      _relays.remove(url);
      _relayInfos.remove(url);
      _expandedRelays.remove(url);
    });

    await _saveRelays();

    if (mounted) {
      AppSnackbar.success(context, 'Relay removed successfully');
    }
  }

  Future<void> _resetToDefaults() async {
    await showResetRelaysDialog(
      context: context,
      onConfirm: () async {
        final previousRelays = Set<String>.from(_relays.map(_normalizeRelayUrl));
        
        setState(() {
          _relays = List.from(relaySetMainSockets);
        });
        await _saveRelays();
        
        if (mounted && context.mounted) {
          AppSnackbar.success(context, 'Relays reset to defaults');
          
          final newRelayUrls = _relays
              .where((relay) => !previousRelays.contains(_normalizeRelayUrl(relay)))
              .toList();
          
          if (newRelayUrls.isNotEmpty && mounted) {
            final shouldBroadcast = await showBroadcastEventsDialog(
              context: context,
              relayUrls: newRelayUrls,
              relayCount: newRelayUrls.length,
            );

            if (shouldBroadcast && mounted) {
              await _broadcastEventsToRelays(newRelayUrls);
            }
          }
        }
      },
    );
  }

  void _showAddRelayDialog() {
    showAddRelayDialog(
      context: context,
      controller: _addRelayController,
      isLoading: _isAddingRelay,
      onAdd: () => _addRelay(true),
    );
  }

  void _showFollowingRelaysDialog() {
    showFollowingRelaysDialog(
      context: context,
      currentRelays: _relays,
      onAddRelay: (relayUrl) async {
        final normalizedUrl = _normalizeRelayUrl(relayUrl);
        if (!_relays.any((existingUrl) => _isRelayUrlEqual(existingUrl, normalizedUrl))) {
          setState(() {
            _relays.add(normalizedUrl);
          });
          await _saveRelays();
          _fetchRelayInfo(normalizedUrl);
          AppSnackbar.success(context, 'Relay added from following list');
          
          if (mounted) {
            final shouldBroadcast = await showBroadcastEventsDialog(
              context: context,
              relayUrl: normalizedUrl,
            );

            if (shouldBroadcast && mounted) {
              await _broadcastEventsToRelay(normalizedUrl);
            }
          }
        } else {
          AppSnackbar.info(context, 'Relay already exists in your list');
        }
      },
    );
  }

  Widget _buildHeader(BuildContext context) {
    return const TitleWidget(
      title: 'Relays',
      fontSize: 32,
      subtitle: "Manage your relay connections and publish your relay list.",
      padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
    );
  }

  Widget _buildActionButtons(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: SecondaryButton(
                  label: _isFetchingUserRelays ? 'Fetching...' : 'Fetch',
                  icon: Icons.download,
                  onPressed: _isFetchingUserRelays ? null : _fetchUserRelays,
                  isLoading: _isFetchingUserRelays,
                  backgroundColor: context.colors.overlayLight,
                  foregroundColor: context.colors.textPrimary,
                  size: ButtonSize.large,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SecondaryButton(
                  label: _isPublishingRelays ? 'Publishing...' : 'Publish',
                  icon: Icons.upload,
                  onPressed: _isPublishingRelays ? null : _publishRelays,
                  isLoading: _isPublishingRelays,
                  backgroundColor: context.colors.overlayLight,
                  foregroundColor: context.colors.textPrimary,
                  size: ButtonSize.large,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: SecondaryButton(
                  label: 'Add Relay',
                  icon: Icons.add,
                  onPressed: _showAddRelayDialog,
                  backgroundColor: context.colors.overlayLight,
                  foregroundColor: context.colors.textPrimary,
                  size: ButtonSize.large,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SecondaryButton(
                  label: 'Reset',
                  icon: Icons.refresh,
                  onPressed: _resetToDefaults,
                  backgroundColor: context.colors.overlayLight,
                  foregroundColor: context.colors.textPrimary,
                  size: ButtonSize.large,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: SecondaryButton(
                  label: 'Explore Relays',
                  icon: Icons.people,
                  onPressed: _showFollowingRelaysDialog,
                  backgroundColor: context.colors.overlayLight,
                  foregroundColor: context.colors.textPrimary,
                  size: ButtonSize.large,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }


  Widget _buildRelayTile(String relay, bool isMainRelay) {
    final manager = WebSocketManager.instance;
    final isConnected = manager.isRelayConnected(relay);
    final isConnecting = manager.isRelayConnecting(relay);
    final stats = _relayStats[relay];
    final info = _relayInfos[relay];
    final isExpanded = _expandedRelays[relay] ?? false;

    return RepaintBoundary(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: context.colors.overlayLight,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              InkWell(
                onTap: () {
                  setState(() {
                    _expandedRelays[relay] = !isExpanded;
                  });
                },
                borderRadius: BorderRadius.circular(16),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isConnected
                              ? Colors.green
                              : isConnecting
                                  ? Colors.orange
                                  : Colors.red,
                        ),
                      ),
                      const SizedBox(width: 12),
              Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              info?.name ?? relay,
                  style: TextStyle(
                                fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: context.colors.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                if (info?.paymentRequired == true) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: Colors.amber.withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      'Paid',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.amber,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ],
                                if (info?.authRequired == true) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: Colors.blue.withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      'Auth',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.blue,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Icon(
                        isExpanded ? Icons.expand_less : Icons.expand_more,
                        color: context.colors.textSecondary,
                        size: 20,
              ),
              const SizedBox(width: 12),
              GestureDetector(
                onTap: () => _removeRelay(relay, isMainRelay),
                child: Container(
                          width: 36,
                          height: 36,
                  decoration: BoxDecoration(
                            color: context.colors.background,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    CarbonIcons.delete,
                            size: 18,
                            color: context.colors.textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (isExpanded)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'URL',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: context.colors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        relay,
                        style: TextStyle(
                          fontSize: 13,
                          color: context.colors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (info != null) ...[
                        if (info.description != null) ...[
                          Text(
                            'Description',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: context.colors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            info.description!,
                            style: TextStyle(
                              fontSize: 13,
                              color: context.colors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                        if (info.supportedNips != null && info.supportedNips!.isNotEmpty) ...[
                          Text(
                            'Supported NIPs',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: context.colors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: info.supportedNips!.take(20).map((nip) {
                              return Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: context.colors.background,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  'NIP-$nip',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: context.colors.textSecondary,
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 16),
                        ],
                        if (info.software != null) ...[
                          Text(
                            'Software',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: context.colors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            info.software!,
                            style: TextStyle(
                              fontSize: 13,
                              color: context.colors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                        if (info.version != null) ...[
                          Text(
                            'Version',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: context.colors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            info.version!,
                            style: TextStyle(
                              fontSize: 13,
                              color: context.colors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                      ],
                      if (stats != null) ...[
                        Text(
                          'Connection Statistics',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: context.colors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        _buildStatRow('Success Rate', stats['successRate'] ?? 'N/A'),
                        _buildStatRow('Connections', '${stats['successfulConnections'] ?? 0}'),
                        _buildStatRow('Messages Sent', '${stats['messagesSent'] ?? 0}'),
                        _buildStatRow('Messages Received', '${stats['messagesReceived'] ?? 0}'),
                        _buildStatRow('Disconnections', '${stats['disconnections'] ?? 0}'),
                      ],
                    ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: context.colors.textSecondary,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: context.colors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: context.colors.background,
        body: Center(
          child: CircularProgressIndicator(color: context.colors.textPrimary),
        ),
      );
    }

    final relayWidgets = <Widget>[];
    for (int i = 0; i < _relays.length; i++) {
      relayWidgets.add(_buildRelayTile(_relays[i], true));
      if (i < _relays.length - 1) {
        relayWidgets.add(const SizedBox(height: 8));
      }
    }

    return Scaffold(
      backgroundColor: context.colors.background,
      body: Stack(
        children: [
          CustomScrollView(
            controller: _scrollController,
            slivers: [
              SliverToBoxAdapter(
                child: SizedBox(height: MediaQuery.of(context).padding.top + 60),
              ),
              SliverToBoxAdapter(
                child: _buildHeader(context),
              ),
              SliverToBoxAdapter(
                child: _buildActionButtons(context),
              ),
              if (_relays.isEmpty)
                SliverToBoxAdapter(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 32),
                      child: Text(
                        'No relays in this category',
                        style: TextStyle(color: context.colors.textTertiary),
                      ),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) => relayWidgets[index],
                      childCount: relayWidgets.length,
                      addAutomaticKeepAlives: true,
                      addRepaintBoundaries: false,
                    ),
                  ),
                ),
            ],
          ),
          TopActionBarWidget(
            onBackPressed: () => context.pop(),
            centerBubble: Text(
              'Relays',
              style: TextStyle(
                color: context.colors.background,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            centerBubbleVisibility: _showTitleBubble,
            onCenterBubbleTap: () {
              _scrollController.animateTo(
                0,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut,
              );
            },
            showShareButton: false,
          ),
        ],
      ),
    );
  }
}
