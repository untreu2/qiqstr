import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:nostr/nostr.dart';
import '../theme/theme_manager.dart';
import '../constants/relays.dart';
import '../services/data_service.dart';
import '../services/nostr_service.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'dart:async';
import 'package:bounce/bounce.dart';

class RelayPage extends StatefulWidget {
  const RelayPage({super.key});

  @override
  State<RelayPage> createState() => _RelayPageState();
}

class _RelayPageState extends State<RelayPage> {
  final TextEditingController _addRelayController = TextEditingController();
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  List<String> _relays = [];
  List<Map<String, dynamic>> _userRelays = [];
  bool _isLoading = true;
  bool _isAddingRelay = false;
  bool _isFetchingUserRelays = false;
  bool _isPublishingRelays = false;
  bool _disposed = false;

  // Track active connections for cleanup
  final List<WebSocket> _activeConnections = [];
  final List<StreamSubscription> _activeSubscriptions = [];

  @override
  void initState() {
    super.initState();
    _loadRelays();
  }

  @override
  void dispose() {
    _disposed = true;

    // Cancel all active subscriptions
    for (final subscription in _activeSubscriptions) {
      try {
        subscription.cancel();
      } catch (_) {}
    }
    _activeSubscriptions.clear();

    // Close all active WebSocket connections
    for (final ws in _activeConnections) {
      try {
        ws.close();
      } catch (_) {}
    }
    _activeConnections.clear();

    _addRelayController.dispose();
    super.dispose();
  }

  Future<void> _loadRelays() async {
    setState(() => _isLoading = true);

    try {
      final prefs = await SharedPreferences.getInstance();

      // Check if user is using their own relays

      // Load custom main relays or use defaults
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
    } catch (e) {
      setState(() {
        _relays = List.from(relaySetMainSockets);
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading relays: ${e.toString()}')),
        );
      }
    }
  }

  Future<void> _publishRelays() async {
    if (!mounted) return;

    setState(() {
      _isPublishingRelays = true;
    });

    try {
      // Get the private key for signing
      final privateKey = await _secureStorage.read(key: 'privateKey');
      if (privateKey == null) {
        _showSnackBar('Private key not found. Please set up your profile first', isError: true);
        return;
      }

      // Get npub for DataService initialization
      final npub = await _secureStorage.read(key: 'npub');
      if (npub == null) {
        _showSnackBar('Please set up your profile first', isError: true);
        return;
      }

      // Initialize DataService for broadcasting
      final dataService = DataService(npub: npub, dataType: DataType.profile);
      await dataService.initialize();
      await dataService.initializeConnections();

      // Prepare relay list for kind 10002 event
      List<List<String>> relayTags = [];

      // Add relays (read & write by default)
      for (String relay in _relays) {
        relayTags.add(['r', relay]);
      }

      // Create and sign the kind 10002 event using NostrService
      final event = Event.from(
        kind: 10002,
        tags: relayTags,
        content: '',
        privkey: privateKey,
      );

      // Serialize the event for broadcasting
      final serializedEvent = NostrService.serializeEvent(event);

      // Broadcast the event directly to relays using WebSocket connections
      await _broadcastRelayListEvent(serializedEvent);

      // Also save to local storage for backup
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('published_relay_list', jsonEncode(NostrService.eventToJson(event)));

      _showSnackBar('Relay list published successfully (${relayTags.length} relays in list)');

      print('Relay list event published: ${event.id}');

      await dataService.closeConnections();
    } catch (e) {
      print('Error publishing relays: $e');
      _showSnackBar('Error publishing relay list: ${e.toString()}', isError: true);
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

      print('Relay list event broadcasted to $successfulBroadcasts/${_relays.length} relays');
    } catch (e) {
      print('Error during relay list broadcast: $e');
    }
  }

  Future<bool> _sendToRelay(String relayUrl, String serializedEvent) async {
    WebSocket? ws;
    try {
      ws = await WebSocket.connect(relayUrl).timeout(const Duration(seconds: 5));

      if (ws.readyState == WebSocket.open) {
        ws.add(serializedEvent);
        await ws.close();
        return true;
      }
      return false;
    } catch (e) {
      print('Failed to send relay list event to $relayUrl: $e');
      try {
        await ws?.close();
      } catch (_) {}
      return false;
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: isError ? Colors.red : null,
        ),
      );
    }
  }

  Future<void> _fetchUserRelays() async {
    setState(() => _isFetchingUserRelays = true);

    try {
      final npub = await _secureStorage.read(key: 'npub');
      if (npub == null) {
        throw Exception('User not logged in');
      }

      final dataService = DataService(npub: npub, dataType: DataType.profile);
      await dataService.initialize();

      // Fetch kind 10002 event (relay list metadata)
      final userRelayList = await _fetchRelayListMetadata(dataService, npub);

      if (userRelayList.isNotEmpty) {
        setState(() {
          _userRelays = userRelayList;
        });

        // Save user relays to preferences
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('user_relays', jsonEncode(_userRelays));

        // Automatically use the fetched relays
        await _useUserRelays();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Found and applied ${_userRelays.length} relays from your profile')),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No relay list found in your profile')),
          );
        }
      }

      await dataService.closeConnections();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error fetching user relays: ${e.toString()}')),
        );
      }
    } finally {
      setState(() => _isFetchingUserRelays = false);
    }
  }

  Future<List<Map<String, dynamic>>> _fetchRelayListMetadata(DataService dataService, String npub) async {
    final List<Map<String, dynamic>> relayList = [];

    try {
      // Create a WebSocket connection to fetch kind 10002 events
      for (final relayUrl in relaySetMainSockets) {
        WebSocket? ws;
        StreamSubscription? sub;
        try {
          // Check if disposed before creating connection
          if (_disposed) return relayList;

          ws = await WebSocket.connect(relayUrl).timeout(const Duration(seconds: 5));

          // Track the connection for cleanup
          if (!_disposed) {
            _activeConnections.add(ws);
          }

          final subscriptionId = DateTime.now().millisecondsSinceEpoch.toString();
          final request = jsonEncode([
            "REQ",
            subscriptionId,
            {
              "authors": [npub],
              "kinds": [10002],
              "limit": 1
            }
          ]);

          final completer = Completer<Map<String, dynamic>?>();

          sub = ws.listen((event) {
            try {
              if (_disposed || completer.isCompleted) return;
              final decoded = jsonDecode(event);
              if (decoded is List && decoded.length >= 2) {
                if (decoded[0] == 'EVENT' && decoded[1] == subscriptionId) {
                  completer.complete(decoded[2]);
                } else if (decoded[0] == 'EOSE' && decoded[1] == subscriptionId) {
                  completer.complete(null);
                }
              }
            } catch (e) {
              if (!completer.isCompleted) completer.complete(null);
            }
          }, onError: (error) {
            if (!completer.isCompleted) completer.complete(null);
          }, onDone: () {
            if (!completer.isCompleted) completer.complete(null);
          });

          // Track the subscription for cleanup
          if (!_disposed) {
            _activeSubscriptions.add(sub);
          }

          if (!_disposed && ws.readyState == WebSocket.open) {
            ws.add(request);
          }

          final eventData = await completer.future.timeout(const Duration(seconds: 5), onTimeout: () => null);

          // Cleanup
          try {
            await sub.cancel();
            _activeSubscriptions.remove(sub);
          } catch (_) {}

          try {
            await ws.close();
            _activeConnections.remove(ws);
          } catch (_) {}

          if (eventData != null) {
            final tags = eventData['tags'] as List<dynamic>? ?? [];

            for (final tag in tags) {
              if (tag is List && tag.isNotEmpty && tag[0] == 'r' && tag.length >= 2) {
                final relayUrl = tag[1] as String;
                String marker = '';

                if (tag.length >= 3 && tag[2] is String) {
                  marker = tag[2] as String;
                }

                // If no marker specified, it's both read and write
                if (marker.isEmpty) {
                  marker = 'read,write';
                }

                relayList.add({
                  'url': relayUrl,
                  'marker': marker,
                });
              }
            }

            // If we found relays, break out of the loop
            if (relayList.isNotEmpty) {
              break;
            }
          }
        } catch (e) {
          print('Error fetching from relay $relayUrl: $e');
          // Ensure cleanup on error
          try {
            await sub?.cancel();
            if (sub != null) _activeSubscriptions.remove(sub);
          } catch (_) {}
          try {
            await ws?.close();
            if (ws != null) _activeConnections.remove(ws);
          } catch (_) {}
        }
      }
    } catch (e) {
      print('Error in _fetchRelayListMetadata: $e');
    }

    return relayList;
  }

  Future<void> _useUserRelays() async {
    if (_userRelays.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No user relays available. Please fetch them first.')),
      );
      return;
    }

    try {
      // Extract relays that can be used for writing (main relays)
      final writeRelays = _userRelays
          .where((relay) => relay['marker'] == '' || relay['marker'].contains('write') || relay['marker'].contains('read,write'))
          .map((relay) => relay['url'] as String)
          .toList();

      setState(() {
        _relays = writeRelays.isNotEmpty ? writeRelays : _userRelays.map((relay) => relay['url'] as String).take(4).toList();
      });

      await _saveRelays();

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('using_user_relays', true);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Now using your personal relays (${writeRelays.length} main relays)')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error applying user relays: ${e.toString()}')),
        );
      }
    }
  }

  Future<void> _saveRelays() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('custom_main_relays', _relays);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Relays saved successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving relays: ${e.toString()}')),
        );
      }
    }
  }

  bool _isValidRelayUrl(String url) {
    final trimmed = url.trim();
    return trimmed.startsWith('wss://') || trimmed.startsWith('ws://');
  }

  Future<void> _addRelay(bool isMainRelay) async {
    final url = _addRelayController.text.trim();

    if (url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a relay URL')),
      );
      return;
    }

    if (!_isValidRelayUrl(url)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid WebSocket URL (wss:// or ws://)')),
      );
      return;
    }

    final targetList = _relays;

    if (targetList.contains(url)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Relay already exists in this category')),
      );
      return;
    }

    setState(() => _isAddingRelay = true);

    try {
      setState(() {
        targetList.add(url);
      });

      await _saveRelays();
      _addRelayController.clear();

      if (mounted) {
        Navigator.pop(context); // Close the dialog
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Relay added to Main list')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error adding relay: ${e.toString()}')),
        );
      }
    } finally {
      setState(() => _isAddingRelay = false);
    }
  }

  Future<void> _removeRelay(String url, bool isMainRelay) async {
    setState(() {
      _relays.remove(url);
    });

    await _saveRelays();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Relay removed successfully')),
      );
    }
  }

  Future<void> _resetToDefaults() async {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: context.colors.surface,
        title: Text('Reset to Defaults', style: TextStyle(color: context.colors.textPrimary)),
        content: Text(
          'This will reset all relays to their default values. Are you sure?',
          style: TextStyle(color: context.colors.textSecondary),
        ),
        actions: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: context.colors.surfaceTransparent,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: context.colors.borderLight),
              ),
              child: Text(
                'Cancel',
                style: TextStyle(
                  color: context.colors.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
          GestureDetector(
            onTap: () async {
              Navigator.pop(context);
              setState(() {
                _relays = List.from(relaySetMainSockets);
              });
              await _saveRelays();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Relays reset to defaults')),
                );
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: context.colors.surfaceTransparent,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: context.colors.borderLight),
              ),
              child: Text(
                'Reset',
                style: TextStyle(
                  color: context.colors.accent,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showAddRelayDialog() {
    _addRelayController.clear();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: context.colors.surface,
        title: Text('Add New Relay', style: TextStyle(color: context.colors.textPrimary)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _addRelayController,
              style: TextStyle(color: context.colors.textPrimary),
              decoration: InputDecoration(
                hintText: 'wss://relay.example.com',
                hintStyle: TextStyle(color: context.colors.textTertiary),
                filled: true,
                fillColor: context.colors.background,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: context.colors.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: context.colors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: context.colors.accent, width: 2),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
            ),
          ],
        ),
        actions: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: context.colors.surfaceTransparent,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: context.colors.borderLight),
              ),
              child: Text(
                'Cancel',
                style: TextStyle(
                  color: context.colors.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
          GestureDetector(
            onTap: _isAddingRelay ? null : () => _addRelay(true),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: _isAddingRelay ? context.colors.surface : context.colors.surfaceTransparent,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: context.colors.borderLight),
              ),
              child: Text(
                'Add Relay',
                style: TextStyle(
                  color: _isAddingRelay ? context.colors.textTertiary : context.colors.accent,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFloatingBackButton(BuildContext context) {
    final double topPadding = MediaQuery.of(context).padding.top;

    return Positioned(
      top: topPadding + 8,
      left: 16,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(25.0),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: context.colors.backgroundTransparent,
              border: Border.all(
                color: context.colors.borderLight,
                width: 1.5,
              ),
              borderRadius: BorderRadius.circular(25.0),
            ),
            child: Bounce(
              scaleFactor: 0.85,
              onTap: () => Navigator.pop(context),
              behavior: HitTestBehavior.opaque,
              child: Icon(
                Icons.arrow_back,
                color: context.colors.textSecondary,
                size: 20,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        children: [
          // Fetch and Publish buttons
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _isFetchingUserRelays ? null : _fetchUserRelays,
                  icon: _isFetchingUserRelays
                      ? SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(context.colors.textPrimary),
                          ),
                        )
                      : const Icon(Icons.download, size: 18),
                  label: Text(_isFetchingUserRelays ? 'Fetching...' : 'Fetch'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: context.colors.surface,
                    foregroundColor: context.colors.textPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: context.colors.border),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _isPublishingRelays ? null : _publishRelays,
                  icon: _isPublishingRelays
                      ? SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(context.colors.textPrimary),
                          ),
                        )
                      : const Icon(Icons.upload, size: 18),
                  label: Text(_isPublishingRelays ? 'Publishing...' : 'Publish'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: context.colors.surface,
                    foregroundColor: context.colors.textPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: context.colors.border),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Add and Reset buttons
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _showAddRelayDialog,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add Relay'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: context.colors.accent,
                    foregroundColor: context.colors.background,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: _resetToDefaults,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Reset'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: context.colors.surface,
                  foregroundColor: context.colors.textPrimary,
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: context.colors.border),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRelaySection(String title, List<String> relays, bool isMainRelay) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              Icon(
                isMainRelay ? Icons.star : Icons.cloud,
                color: context.colors.accent,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: context.colors.textPrimary,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: context.colors.accent.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${relays.length}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: context.colors.accent,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (relays.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: Text(
              'No relays in this category',
              style: TextStyle(
                color: context.colors.textTertiary,
                fontStyle: FontStyle.italic,
              ),
            ),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: relays.length,
            itemBuilder: (context, index) => _buildRelayTile(relays[index], isMainRelay),
            separatorBuilder: (_, __) => Divider(
              color: context.colors.border,
              height: 1,
            ),
          ),
      ],
    );
  }

  Widget _buildRelayTile(String relay, bool isMainRelay) {
    // Check if this relay is from user's personal relays
    final userRelay = _userRelays.firstWhere(
      (r) => r['url'] == relay,
      orElse: () => <String, dynamic>{},
    );
    final isUserRelay = userRelay.isNotEmpty;
    final marker = userRelay['marker'] as String? ?? '';

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: isUserRelay ? context.colors.accent.withOpacity(0.1) : context.colors.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: isUserRelay ? context.colors.accent.withOpacity(0.3) : context.colors.border),
        ),
        child: Icon(
          isUserRelay ? Icons.cloud_sync : Icons.router,
          color: isUserRelay ? context.colors.accent : context.colors.textSecondary,
          size: 20,
        ),
      ),
      title: Text(
        relay,
        style: TextStyle(
          color: context.colors.textPrimary,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),
      subtitle: isUserRelay
          ? Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: context.colors.accent.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'Synced',
                    style: TextStyle(
                      fontSize: 10,
                      color: context.colors.accent,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                if (marker.isNotEmpty) ...[
                  const SizedBox(width: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: context.colors.surface,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: context.colors.border),
                    ),
                    child: Text(
                      marker.replaceAll(',', ' • '),
                      style: TextStyle(
                        fontSize: 10,
                        color: context.colors.textSecondary,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ),
                ],
              ],
            )
          : null,
      trailing: IconButton(
        icon: Icon(
          Icons.delete_outline,
          color: context.colors.textSecondary,
          size: 20,
        ),
        onPressed: () => _removeRelay(relay, isMainRelay),
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

    return Scaffold(
      backgroundColor: context.colors.background,
      body: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(height: MediaQuery.of(context).padding.top + 60), // Space for floating back button
              _buildActionButtons(context),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      _buildRelaySection('Relays', _relays, true),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
            ],
          ),
          _buildFloatingBackButton(context),
        ],
      ),
    );
  }
}
