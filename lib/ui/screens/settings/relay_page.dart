import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../src/rust/api/events.dart' as rust_events;
import 'package:carbon_icons/carbon_icons.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import '../../theme/theme_manager.dart';
import '../../../constants/relays.dart';
import '../../../data/services/auth_service.dart';
import '../../../data/services/nostr_service.dart';
import '../../../data/services/relay_service.dart';
import '../../widgets/common/common_buttons.dart';
import '../../widgets/common/snackbar_widget.dart';
import '../../widgets/common/title_widget.dart';
import '../../widgets/common/top_action_bar_widget.dart';
import '../../widgets/dialogs/reset_relays_dialog.dart';
import '../../widgets/dialogs/add_relay_dialog.dart';
import '../../../l10n/app_localizations.dart';
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
  Map<String, Map<String, bool>> _relayFlags = {};
  List<Map<String, dynamic>> _userRelays = [];
  bool _isLoading = true;
  bool _isAddingRelay = false;
  bool _isFetchingUserRelays = false;
  bool _isPublishingRelays = false;
  bool _disposed = false;
  bool _gossipModelEnabled = false;
  final Map<String, RelayInfo?> _relayInfos = {};
  final Map<String, bool> _expandedRelays = {};
  final Map<String, Map<String, dynamic>> _relayStats = {};
  late ScrollController _scrollController;
  final ValueNotifier<bool> _showTitleBubble = ValueNotifier(false);

  final AuthService _authService = AuthService.instance;

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

  void _initializeServices() {}

  void _startStatsRefresh() {
    Timer.periodic(const Duration(seconds: 2), (timer) {
      if (_disposed) {
        timer.cancel();
        return;
      }
      _loadRelayStats();
    });
  }

  void _loadRelayStats() async {
    if (_disposed) return;
    try {
      final status = await RustRelayService.instance.getRelayStatus();
      if (_disposed || !mounted) return;
      final relays = status['relays'] as List<dynamic>? ?? [];
      final newStats = <String, Map<String, dynamic>>{};
      for (final relay in relays) {
        final r = relay as Map<String, dynamic>;
        final url = r['url'] as String? ?? '';
        if (url.isNotEmpty) {
          newStats[url] = r;
        }
      }
      setState(() {
        _relayStats.clear();
        _relayStats.addAll(newStats);
      });
    } catch (_) {}
  }

  Future<void> _loadRelays() async {
    setState(() => _isLoading = true);

    try {
      final prefs = await SharedPreferences.getInstance();

      final customMainRelays = prefs.getStringList('custom_main_relays');
      final userRelaysJson = prefs.getString('user_relays');
      final flagsJson = prefs.getString('relay_flags');
      _gossipModelEnabled = prefs.getBool('gossip_model_enabled') ?? false;

      if (userRelaysJson != null) {
        final List<dynamic> decoded = jsonDecode(userRelaysJson);
        _userRelays = decoded.cast<Map<String, dynamic>>();
      }

      Map<String, Map<String, bool>> loadedFlags = {};
      if (flagsJson != null) {
        final decoded = jsonDecode(flagsJson) as Map<String, dynamic>;
        for (final entry in decoded.entries) {
          final flags = entry.value as Map<String, dynamic>;
          loadedFlags[entry.key] = {
            'read': flags['read'] as bool? ?? true,
            'write': flags['write'] as bool? ?? true,
          };
        }
      }

      final relays = customMainRelays ?? List.from(relaySetMainSockets);

      for (final relay in relays) {
        loadedFlags.putIfAbsent(relay, () => {'read': true, 'write': true});
      }

      setState(() {
        _relays = relays;
        _relayFlags = loadedFlags;
        _isLoading = false;
      });

      for (final relay in _relays) {
        _fetchRelayInfo(relay);
      }
    } catch (e) {
      setState(() {
        _relays = List.from(relaySetMainSockets);
        _relayFlags = {};
        for (final relay in _relays) {
          _relayFlags[relay] = {'read': true, 'write': true};
        }
        _isLoading = false;
      });
      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
        AppSnackbar.error(context, '${l10n.errorLoadingRelays}: ${e.toString()}');
      }
    }
  }

  Future<void> _fetchRelayInfo(String relayUrl) async {
    if (_relayInfos.containsKey(relayUrl)) return;

    try {
      final uri = Uri.parse(relayUrl).replace(scheme: 'https');
      final response = await http.get(uri, headers: {
        'Accept': 'application/nostr+json'
      }).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final decoded =
            jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
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
      final privateKeyResult = await _authService.getCurrentUserPrivateKey();
      if (privateKeyResult.isError || privateKeyResult.data == null) {
        if (mounted) {
          final l10n = AppLocalizations.of(context)!;
          AppSnackbar.error(
              context, l10n.privateKeyNotFound);
        }
        return;
      }

      final npubResult = await _authService.getCurrentUserNpub();
      if (npubResult.isError || npubResult.data == null) {
        if (mounted) {
          final l10n = AppLocalizations.of(context)!;
          AppSnackbar.error(context, l10n.pleaseSetUpYourProfileFirst);
        }
        return;
      }

      final privateKey = privateKeyResult.data!;

      List<String> relayConfigs = [];
      for (String relay in _relays) {
        final flags = _relayFlags[relay] ?? {'read': true, 'write': true};
        final isRead = flags['read'] ?? true;
        final isWrite = flags['write'] ?? true;

        if (isRead && isWrite) {
          relayConfigs.add(relay);
        } else if (isRead) {
          relayConfigs.add('$relay|read');
        } else if (isWrite) {
          relayConfigs.add('$relay|write');
        }
      }

      final eventJsonStr = rust_events.createRelayListEventWithMarkers(
        relayConfigs: relayConfigs,
        privateKeyHex: privateKey,
      );
      final event = jsonDecode(eventJsonStr) as Map<String, dynamic>;

      final serializedEvent = NostrService.serializeEvent(event);

      await _broadcastRelayListEvent(serializedEvent);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('published_relay_list', jsonEncode(event));

      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
        AppSnackbar.success(context,
            '${l10n.relayListPublishedSuccessfully} (${relayConfigs.length} relays in list)');
      }

      if (kDebugMode) {
        print('Relay list event published: ${event['id']}');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error publishing relays: $e');
      }
      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
        AppSnackbar.error(
            context, '${l10n.errorPublishingRelayList}: ${e.toString()}');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isPublishingRelays = false;
        });
      }
    }
  }

  Future<void> _broadcastRelayListEvent(String serializedEvent) async {
    try {
      final decoded = jsonDecode(serializedEvent) as List<dynamic>;
      if (decoded.isNotEmpty && decoded[0] == 'EVENT' && decoded.length >= 2) {
        final eventData = decoded[1] as Map<String, dynamic>;
        final eventJson = jsonEncode(eventData);
        await RustRelayService.instance.sendEvent(eventJson);
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error during relay list broadcast: $e');
      }
    }
  }

  Future<void> _fetchUserRelays() async {
    setState(() {
      _isFetchingUserRelays = true;
    });

    try {
      final npubResult = await _authService.getCurrentUserNpub();
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
          final l10n = AppLocalizations.of(context)!;
          AppSnackbar.success(context,
              '${l10n.relayListFetchedSuccessfully} (${_userRelays.length} relays)');
        }
      } else {
        if (mounted) {
          final l10n = AppLocalizations.of(context)!;
          AppSnackbar.info(context, l10n.noRelayListFoundInYourProfile);
        }
      }
    } catch (e) {
      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
        AppSnackbar.error(
            context, '${l10n.errorFetchingRelayList}: ${e.toString()}');
      }
    } finally {
      setState(() {
        _isFetchingUserRelays = false;
      });
    }
  }

  Future<List<Map<String, dynamic>>> _fetchRelayListMetadata(
      String npub) async {
    final List<Map<String, dynamic>> relayList = [];

    try {
      final pubkeyHex = _authService.npubToHex(npub) ?? npub;

      final filter = {
        'authors': [pubkeyHex],
        'kinds': [10002],
        'limit': 1,
      };

      final events = await RustRelayService.instance.fetchEvents(filter, timeoutSecs: 10);

      if (events.isNotEmpty) {
        final eventData = events.first;
        final tags = eventData['tags'] as List<dynamic>? ?? [];

        for (final tag in tags) {
          if (tag is List &&
              tag.isNotEmpty &&
              tag[0] == 'r' &&
              tag.length >= 2) {
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
      final l10n = AppLocalizations.of(context)!;
      AppSnackbar.info(
          context, l10n.noRelayListFoundInYourProfile);
      return;
    }

    try {
      final previousRelays = Set<String>.from(_relays.map(_normalizeRelayUrl));

      final newRelays = _userRelays
          .map((relay) => relay['url'] as String)
          .toList();

      final newFlags = <String, Map<String, bool>>{};
      for (final relay in _userRelays) {
        final url = relay['url'] as String;
        final marker = relay['marker'] as String? ?? '';

        if (marker == 'read') {
          newFlags[url] = {'read': true, 'write': false};
        } else if (marker == 'write') {
          newFlags[url] = {'read': false, 'write': true};
        } else {
          newFlags[url] = {'read': true, 'write': true};
        }
      }

      setState(() {
        _relays = newRelays;
        _relayFlags = newFlags;
      });

      await _saveRelays();

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('using_user_relays', true);

      if (mounted) {
        AppSnackbar.success(context,
            'Now using your personal relays (${newRelays.length} main relays)');

        final newRelayUrls = newRelays
            .where(
                (relay) => !previousRelays.contains(_normalizeRelayUrl(relay)))
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
        final l10n = AppLocalizations.of(context)!;
        AppSnackbar.error(
            context, '${l10n.errorSavingRelays}: ${e.toString()}');
      }
    }
  }

  Future<void> _saveRelays() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('custom_main_relays', _relays);
      await prefs.setString('relay_flags', jsonEncode(_relayFlags));

      await RustRelayService.instance.reloadCustomRelays();

      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
        AppSnackbar.success(context, l10n.relaysSavedSuccessfully);
      }
    } catch (e) {
      if (kDebugMode) {
        print('[RelayPage] Error saving relays: $e');
      }
      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
        AppSnackbar.error(context, '${l10n.errorSavingRelays}: ${e.toString()}');
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
      final l10n = AppLocalizations.of(context)!;
      AppSnackbar.error(context, l10n.pleaseEnterRelayUrl);
      return;
    }

    if (!_isValidRelayUrl(url)) {
      final l10n = AppLocalizations.of(context)!;
      AppSnackbar.error(
          context, l10n.invalidRelayUrl);
      return;
    }

    final targetList = _relays;
    final normalizedUrl = _normalizeRelayUrl(url);

    if (targetList
        .any((existingUrl) => _isRelayUrlEqual(existingUrl, normalizedUrl))) {
      final l10n = AppLocalizations.of(context)!;
      AppSnackbar.error(context, l10n.relayAlreadyExistsInCategory);
      return;
    }

    setState(() => _isAddingRelay = true);

    try {
      setState(() {
        targetList.add(url);
        _relayFlags[url] = {'read': true, 'write': true};
      });

      await _saveRelays();
      _addRelayController.clear();
      _fetchRelayInfo(url);

      if (mounted) {
        context.pop();
        final l10n = AppLocalizations.of(context)!;
        AppSnackbar.success(context, l10n.relayAddedToMainList);

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
        final l10n = AppLocalizations.of(context)!;
        AppSnackbar.error(context, '${l10n.errorAddingRelay}: ${e.toString()}');
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

    final l10n = AppLocalizations.of(context)!;
    AppSnackbar.info(context, l10n.fetchingYourEvents);

    try {
      final result =
          await EventCountsService.instance.fetchAllEventsForUser(null);

      if (!mounted) return;

      if (result == null || result.allEvents.isEmpty) {
        AppSnackbar.info(context, l10n.noEventsFoundToBroadcast);
        return;
      }

      AppSnackbar.info(
          context, l10n.broadcastingEvents(result.allEvents.length, relayUrls.length));

      final success = await EventCountsService.instance.rebroadcastEvents(
        result.allEvents,
        relayUrls: relayUrls,
      );

      if (!mounted) return;

      if (success) {
        AppSnackbar.success(
          context,
          l10n.eventsSuccessfullyBroadcast(result.allEvents.length, relayUrls.length),
        );
      } else {
        AppSnackbar.error(context, l10n.errorBroadcastingEvents);
      }
    } catch (e) {
      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
        AppSnackbar.error(
            context, '${l10n.errorBroadcastingEvents}: ${e.toString()}');
      }
    }
  }

  Future<void> _removeRelay(String url, bool isMainRelay) async {
    setState(() {
      _relays.remove(url);
      _relayFlags.remove(url);
      _relayInfos.remove(url);
      _expandedRelays.remove(url);
    });

    await _saveRelays();

    if (mounted) {
      final l10n = AppLocalizations.of(context)!;
      AppSnackbar.success(context, l10n.relayRemovedSuccessfully);
    }
  }

  Future<void> _resetToDefaults() async {
    await showResetRelaysDialog(
      context: context,
      onConfirm: () async {
        final previousRelays =
            Set<String>.from(_relays.map(_normalizeRelayUrl));

        final defaultFlags = <String, Map<String, bool>>{};
        for (final relay in relaySetMainSockets) {
          defaultFlags[relay] = {'read': true, 'write': true};
        }

        setState(() {
          _relays = List.from(relaySetMainSockets);
          _relayFlags = defaultFlags;
        });
        await _saveRelays();

        if (mounted && context.mounted) {
          final l10n = AppLocalizations.of(context)!;
          AppSnackbar.success(context, l10n.relaysResetToDefaults);

          final newRelayUrls = _relays
              .where((relay) =>
                  !previousRelays.contains(_normalizeRelayUrl(relay)))
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

  Widget _buildHeader(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return TitleWidget(
      title: l10n.relays,
      fontSize: 32,
      subtitle: l10n.manageYourRelayConnections,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
    );
  }

  Widget _buildGossipModelToggle(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: context.colors.overlayLight,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.gossipMode,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: context.colors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        l10n.gossipModeDescription,
                        style: TextStyle(
                          fontSize: 13,
                          color: context.colors.textSecondary,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Switch.adaptive(
                  value: _gossipModelEnabled,
                  onChanged: (value) async {
                    setState(() {
                      _gossipModelEnabled = value;
                    });
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setBool('gossip_model_enabled', value);
                    if (context.mounted) {
                      final l10n = AppLocalizations.of(context)!;
                      AppSnackbar.success(
                        context,
                        value
                            ? l10n.gossipModelEnabledRestartApp
                            : l10n.gossipModelDisabledRestartApp,
                      );
                    }
                  },
                  activeTrackColor: context.colors.accent,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context, AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: SecondaryButton(
                  label: _isFetchingUserRelays ? l10n.fetching : l10n.fetch,
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
                  label: _isPublishingRelays ? l10n.publishing : l10n.publish,
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
                  label: l10n.addRelay,
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
                  label: l10n.reset,
                  icon: Icons.refresh,
                  onPressed: _resetToDefaults,
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

  Widget _buildRelayTile(String relay, bool isMainRelay, AppLocalizations l10n) {
    final stats = _relayStats[relay];
    final relayStatus = stats?['status'] as String? ?? 'disconnected';
    final isConnected = relayStatus == 'connected';
    final isConnecting = relayStatus == 'connecting' || relayStatus == 'pending';
    final info = _relayInfos[relay];
    final isExpanded = _expandedRelays[relay] ?? false;

    return RepaintBoundary(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Container(
          decoration: BoxDecoration(
            color: context.colors.overlayLight,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isConnected
                  ? Colors.green.withValues(alpha: 0.3)
                  : context.colors.divider.withValues(alpha: 0.1),
              width: 1,
            ),
          ),
          child: Column(
            children: [
              InkWell(
                onTap: () {
                  setState(() {
                    _expandedRelays[relay] = !isExpanded;
                  });
                },
                borderRadius: BorderRadius.circular(20),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isConnected
                              ? Colors.green
                              : isConnecting
                                  ? Colors.orange
                                  : Colors.red.withValues(alpha: 0.5),
                          boxShadow: isConnected
                              ? [
                                  BoxShadow(
                                    color: Colors.green.withValues(alpha: 0.4),
                                    blurRadius: 6,
                                    spreadRadius: 1,
                                  ),
                                ]
                              : null,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              info?.name ?? relay.replaceAll('wss://', '').replaceAll('ws://', '').split('/').first,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: context.colors.textPrimary,
                              ),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                            const SizedBox(height: 4),
                            _buildRelayFlagChips(relay, l10n),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () => _removeRelay(relay, isMainRelay),
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: context.colors.error.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            CarbonIcons.trash_can,
                            size: 16,
                            color: context.colors.error,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Icon(
                        isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                        color: context.colors.textSecondary.withValues(alpha: 0.6),
                        size: 20,
                      ),
                    ],
                  ),
                ),
              ),
              if (isExpanded)
                Container(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                  decoration: BoxDecoration(
                    border: Border(
                      top: BorderSide(
                        color: context.colors.divider.withValues(alpha: 0.1),
                        width: 1,
                      ),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 12),
                      _buildInfoRow('URL', relay, context),
                      if (info != null) ...[
                        if (info.description != null) ...[
                          const SizedBox(height: 10),
                          _buildInfoRow(l10n.description, info.description!, context),
                        ],
                        if (info.software != null) ...[
                          const SizedBox(height: 10),
                          _buildInfoRow(l10n.software, info.software!, context),
                        ],
                        if (info.version != null) ...[
                          const SizedBox(height: 10),
                          _buildInfoRow(l10n.version, info.version!, context),
                        ],
                        if (info.supportedNips != null && info.supportedNips!.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Text(
                            l10n.supportedNIPs,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: context.colors.textSecondary,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 4,
                            runSpacing: 4,
                            children: info.supportedNips!.take(15).map((nip) {
                              return Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: context.colors.background,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: context.colors.divider.withValues(alpha: 0.2),
                                  ),
                                ),
                                child: Text(
                                  'NIP-$nip',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: context.colors.textSecondary,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ],
                      ],
                      if (stats != null) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: context.colors.background,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                l10n.connectionStatistics,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: context.colors.textSecondary,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              const SizedBox(height: 8),
                              _buildStatRow(l10n.status, stats['status'] ?? l10n.unknown),
                              _buildStatRow(l10n.attempts, '${stats['attempts'] ?? 0}'),
                              _buildStatRow(l10n.successful, '${stats['success'] ?? 0}'),
                            ],
                          ),
                        ),
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

  Widget _buildInfoRow(String label, String value, BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: context.colors.textSecondary,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 12,
              color: context.colors.textPrimary,
              height: 1.3,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRelayFlagChips(String relay, AppLocalizations l10n) {
    final flags = _relayFlags[relay] ?? {'read': true, 'write': true};
    final isRead = flags['read'] ?? true;
    final isWrite = flags['write'] ?? true;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildFlagChip(
          label: l10n.read,
          active: isRead,
          activeColor: const Color(0xFF4CAF50),
          onTap: () {
            final newRead = !isRead;
            if (!newRead && !isWrite) return;
            setState(() {
              _relayFlags[relay] = {
                'read': newRead,
                'write': isWrite,
              };
            });
            _saveRelays();
          },
        ),
        const SizedBox(width: 6),
        _buildFlagChip(
          label: l10n.write,
          active: isWrite,
          activeColor: const Color(0xFF2196F3),
          onTap: () {
            final newWrite = !isWrite;
            if (!isRead && !newWrite) return;
            setState(() {
              _relayFlags[relay] = {
                'read': isRead,
                'write': newWrite,
              };
            });
            _saveRelays();
          },
        ),
        if (_relayInfos[relay]?.paymentRequired == true) ...[
          const SizedBox(width: 6),
          _buildInfoChip(l10n.paid, const Color(0xFFFFA726)),
        ],
        if (_relayInfos[relay]?.authRequired == true) ...[
          const SizedBox(width: 6),
          _buildInfoChip(l10n.auth, const Color(0xFFAB47BC)),
        ],
      ],
    );
  }

  Widget _buildFlagChip({
    required String label,
    required bool active,
    required Color activeColor,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: active ? activeColor.withValues(alpha: 0.15) : context.colors.background,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: active ? activeColor.withValues(alpha: 0.5) : context.colors.divider.withValues(alpha: 0.3),
            width: 1.5,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: active ? activeColor : context.colors.textSecondary,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3,
          ),
        ),
      ),
    );
  }

  Widget _buildInfoChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: color.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          color: color,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  Widget _buildStatRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: context.colors.textSecondary,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 11,
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
    final l10n = AppLocalizations.of(context)!;
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
      relayWidgets.add(_buildRelayTile(_relays[i], true, l10n));
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
                child:
                    SizedBox(height: MediaQuery.of(context).padding.top + 60),
              ),
              SliverToBoxAdapter(
                child: _buildHeader(context),
              ),
              SliverToBoxAdapter(
                child: _buildActionButtons(context, l10n),
              ),
              SliverToBoxAdapter(
                child: _buildGossipModelToggle(context),
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
