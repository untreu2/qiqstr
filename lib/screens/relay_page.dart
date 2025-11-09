import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nostr/nostr.dart';
import '../theme/theme_manager.dart';
import '../constants/relays.dart';
import '../core/di/app_di.dart';
import '../data/repositories/auth_repository.dart';
import '../services/nostr_service.dart';
import '../services/relay_service.dart';
import '../widgets/back_button_widget.dart';
import '../widgets/common_buttons.dart';
import '../widgets/snackbar_widget.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:async';

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

  final List<WebSocket> _activeConnections = [];
  final List<StreamSubscription> _activeSubscriptions = [];

  late AuthRepository _authRepository;

  @override
  void initState() {
    super.initState();
    _initializeServices();
    _loadRelays();
  }

  @override
  void dispose() {
    _disposed = true;

    for (final subscription in _activeSubscriptions) {
      try {
        subscription.cancel();
      } catch (_) {}
    }
    _activeSubscriptions.clear();

    for (final ws in _activeConnections) {
      try {
        ws.close();
      } catch (_) {}
    }
    _activeConnections.clear();

    _addRelayController.dispose();
    super.dispose();
  }

  void _initializeServices() {
    _authRepository = AppDI.get<AuthRepository>();
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

      final event = Event.from(
        kind: 10002,
        tags: relayTags,
        content: '',
        privkey: privateKey,
      );

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
      if (kDebugMode) {
        print('Failed to send relay list event to $relayUrl: $e');
      }
      try {
        await ws?.close();
      } catch (_) {}
      return false;
    }
  }

  Future<void> _fetchUserRelays() async {
    setState(() => _isFetchingUserRelays = true);

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
      setState(() => _isFetchingUserRelays = false);
    }
  }

  Future<List<Map<String, dynamic>>> _fetchRelayListMetadata(String npub) async {
    final List<Map<String, dynamic>> relayList = [];

    try {
      final pubkeyHex = _authRepository.npubToHex(npub) ?? npub;

      for (final relayUrl in relaySetMainSockets) {
        WebSocket? ws;
        StreamSubscription? sub;
        try {
          if (_disposed) return relayList;

          ws = await WebSocket.connect(relayUrl).timeout(const Duration(seconds: 5));

          if (!_disposed) {
            _activeConnections.add(ws);
          }

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

          if (!_disposed) {
            _activeSubscriptions.add(sub);
          }

          if (!_disposed && ws.readyState == WebSocket.open) {
            ws.add(request);
          }

          final eventData = await completer.future.timeout(const Duration(seconds: 5), onTimeout: () => null);

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
        AppSnackbar.success(context, 'Now using your personal relays (${writeRelays.length} main relays)');
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

    if (targetList.contains(url)) {
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

      if (mounted) {
        Navigator.pop(context);
        AppSnackbar.success(context, 'Relay added to Main list');
      }
    } catch (e) {
      if (mounted) {
        AppSnackbar.error(context, 'Error adding relay: ${e.toString()}');
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
      AppSnackbar.success(context, 'Relay removed successfully');
    }
  }

  Future<void> _resetToDefaults() async {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.colors.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.zero,
      ),
      builder: (modalContext) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'This will reset all relays to their default values. Are you sure?',
              style: TextStyle(
                color: context.colors.textSecondary,
                fontSize: 15,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            GestureDetector(
              onTap: () async {
                Navigator.pop(modalContext);
                setState(() {
                  _relays = List.from(relaySetMainSockets);
                });
                await _saveRelays();
                if (mounted && context.mounted) {
                  AppSnackbar.success(context, 'Relays reset to defaults');
                }
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 12),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: context.colors.buttonPrimary,
                  borderRadius: BorderRadius.circular(40),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.refresh, color: context.colors.buttonText, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'Reset to Defaults',
                      style: TextStyle(
                        color: context.colors.buttonText,
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            GestureDetector(
              onTap: () => Navigator.pop(modalContext),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 12),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: context.colors.overlayLight,
                  borderRadius: BorderRadius.circular(40),
                ),
                child: Text(
                  'Cancel',
                  style: TextStyle(
                    color: context.colors.textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddRelayDialog() {
    _addRelayController.clear();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.colors.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.zero,
      ),
      builder: (modalContext) => Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(modalContext).viewInsets.bottom + 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _addRelayController,
              autofocus: true,
              style: TextStyle(
                color: context.colors.textPrimary,
                fontSize: 15,
              ),
              decoration: InputDecoration(
                hintText: 'wss://relay.example.com',
                hintStyle: TextStyle(
                  color: context.colors.textSecondary,
                  fontSize: 15,
                ),
                filled: true,
                fillColor: context.colors.inputFill,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(25),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: PrimaryButton(
                label: 'Add Relay',
                icon: Icons.add,
                onPressed: _isAddingRelay ? null : () => _addRelay(true),
                isLoading: _isAddingRelay,
                size: ButtonSize.large,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: SecondaryButton(
                label: 'Cancel',
                onPressed: () => Navigator.pop(modalContext),
                backgroundColor: context.colors.overlayLight,
                foregroundColor: context.colors.textPrimary,
                size: ButtonSize.large,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final double topPadding = MediaQuery.of(context).padding.top;

    return Padding(
      padding: EdgeInsets.fromLTRB(16, topPadding + 70, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 5,
                height: 20,
                decoration: BoxDecoration(
                  color: context.colors.accent,
                  borderRadius: BorderRadius.circular(2.5),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'Relays',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w700,
                  color: context.colors.textPrimary,
                  letterSpacing: -0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 17),
            child: Text(
              "Manage your relay connections and publish your relay list.",
              style: TextStyle(
                fontSize: 15,
                color: context.colors.textSecondary,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
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
                child: PrimaryButton(
                  label: 'Add Relay',
                  icon: Icons.add,
                  onPressed: _showAddRelayDialog,
                  size: ButtonSize.large,
                ),
              ),
              const SizedBox(width: 12),
              SecondaryButton(
                label: 'Reset',
                icon: Icons.refresh,
                onPressed: _resetToDefaults,
                backgroundColor: context.colors.overlayLight,
                foregroundColor: context.colors.textPrimary,
                size: ButtonSize.large,
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
              color: context.colors.border.withValues(alpha: 0.3),
              height: 1,
            ),
          ),
      ],
    );
  }

  Widget _buildRelayTile(String relay, bool isMainRelay) {
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
          color: isUserRelay ? context.colors.accent.withValues(alpha: 0.1) : context.colors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isUserRelay ? context.colors.accent.withValues(alpha: 0.3) : context.colors.border.withValues(alpha: 0.3),
            width: 1,
          ),
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
          fontSize: 15,
          fontWeight: FontWeight.w500,
        ),
      ),
      subtitle: isUserRelay
          ? Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: context.colors.accent.withValues(alpha: 0.1),
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
      trailing: GestureDetector(
        onTap: () => _removeRelay(relay, isMainRelay),
        child: Container(
          padding: const EdgeInsets.all(8),
          child: Icon(
            Icons.delete_outline,
            color: context.colors.textSecondary,
            size: 20,
          ),
        ),
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
              _buildHeader(context),
              _buildActionButtons(context),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      const SizedBox(height: 16),
                      _buildRelaySection('Relays', _relays, true),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const BackButtonWidget.floating(),
        ],
      ),
    );
  }
}
