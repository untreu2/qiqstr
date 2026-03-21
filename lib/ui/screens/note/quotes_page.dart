import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/di/app_di.dart';
import '../../../data/repositories/feed_repository.dart';
import '../../../data/repositories/profile_repository.dart';
import '../../../data/services/auth_service.dart';
import '../../../data/sync/sync_service.dart';
import '../../../domain/entities/feed_note.dart';
import '../../theme/theme_manager.dart';
import '../../widgets/common/top_action_bar_widget.dart';
import '../../widgets/note/note_list_widget.dart';
import '../../../l10n/app_localizations.dart';

class QuotesPage extends StatefulWidget {
  final String noteId;

  const QuotesPage({super.key, required this.noteId});

  @override
  State<QuotesPage> createState() => _QuotesPageState();
}

class _QuotesPageState extends State<QuotesPage> {
  late final FeedRepository _feedRepository;
  late final ProfileRepository _profileRepository;
  late final SyncService _syncService;
  late final String _currentUserHex;

  List<Map<String, dynamic>> _quotes = [];
  Map<String, Map<String, dynamic>> _profiles = {};
  bool _isLoading = true;
  StreamSubscription<List<FeedNote>>? _subscription;

  final ValueNotifier<List<Map<String, dynamic>>> _notesNotifier =
      ValueNotifier([]);
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _feedRepository = AppDI.get<FeedRepository>();
    _profileRepository = AppDI.get<ProfileRepository>();
    _syncService = AppDI.get<SyncService>();
    _currentUserHex = AuthService.instance.currentUserPubkeyHex ?? '';
    _loadQuotes();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _notesNotifier.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  bool _isQuote(Map<String, dynamic> note) {
    final tags = note['tags'] as List<dynamic>? ?? [];
    for (final tag in tags) {
      if (tag is! List || tag.length < 2 || tag[0] != 'e') continue;
      final refId = tag[1] as String? ?? '';
      if (refId != widget.noteId) continue;
      final marker = tag.length >= 4 ? tag[3] as String? : null;
      if (marker == 'mention') return true;
    }
    return false;
  }

  Future<void> _loadQuotes() async {
    setState(() => _isLoading = true);

    _subscription?.cancel();
    _subscription =
        _feedRepository.watchThreadReplies(widget.noteId, limit: 500).listen(
      (notes) async {
        if (!mounted) return;
        final quotes = notes
            .where((n) => _isQuote(n.toMap()))
            .map((n) => n.toMap())
            .toList();

        final pubkeys = quotes
            .map((q) => q['pubkey'] as String? ?? '')
            .where((p) => p.isNotEmpty)
            .toSet()
            .toList();

        Map<String, Map<String, dynamic>> profiles = {};
        if (pubkeys.isNotEmpty) {
          final fetched = await _profileRepository.getProfiles(pubkeys);
          for (final entry in fetched.entries) {
            profiles[entry.key] = entry.value.toMap();
          }
        }

        if (!mounted) return;
        setState(() {
          _quotes = quotes;
          _profiles = profiles;
          _isLoading = false;
        });
      },
      onError: (_) {
        if (mounted) setState(() => _isLoading = false);
      },
    );

    _syncService.syncReplies(widget.noteId).catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final topPadding = MediaQuery.of(context).padding.top + 68;

    return Scaffold(
      backgroundColor: context.colors.background,
      body: Stack(
        children: [
          if (_isLoading)
            Center(
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: context.colors.primary,
              ),
            )
          else if (_quotes.isEmpty)
            Center(
              child: Text(
                l10n.noQuotesFound,
                style: TextStyle(
                  color: context.colors.textSecondary,
                  fontSize: 16,
                ),
              ),
            )
          else
            CustomScrollView(
              controller: _scrollController,
              slivers: [
                SliverToBoxAdapter(
                  child: SizedBox(height: topPadding),
                ),
                NoteListWidget(
                  notes: _quotes,
                  currentUserHex: _currentUserHex,
                  notesNotifier: _notesNotifier,
                  profiles: _profiles,
                  scrollController: _scrollController,
                  isLoading: false,
                  canLoadMore: false,
                ),
              ],
            ),
          TopActionBarWidget(
            onBackPressed: () => context.pop(),
            showShareButton: false,
            centerBubble: Text(
              l10n.quotes,
              style: TextStyle(
                color: context.colors.background,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
