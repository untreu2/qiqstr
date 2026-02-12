import 'package:flutter/material.dart';
import 'package:carbon_icons/carbon_icons.dart';
import '../../../data/services/rust_database_service.dart';
import '../../../l10n/app_localizations.dart';
import '../../theme/theme_manager.dart';
import '../../widgets/common/title_widget.dart';
import '../../widgets/common/top_action_bar_widget.dart';
import '../../widgets/common/common_buttons.dart';
import '../../widgets/common/snackbar_widget.dart';

class DatabasePage extends StatefulWidget {
  const DatabasePage({super.key});

  @override
  State<DatabasePage> createState() => _DatabasePageState();
}

class _DatabasePageState extends State<DatabasePage> {
  bool _isLoading = false;
  bool _isCleaningUp = false;
  Map<String, dynamic> _stats = {};
  int _databaseSizeMB = 0;
  late ScrollController _scrollController;
  final ValueNotifier<bool> _showTitleBubble = ValueNotifier(false);

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController()..addListener(_scrollListener);
    _loadStats();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _showTitleBubble.dispose();
    super.dispose();
  }

  void _scrollListener() {
    if (_scrollController.hasClients) {
      final shouldShow = _scrollController.offset > 100;
      if (_showTitleBubble.value != shouldShow) {
        _showTitleBubble.value = shouldShow;
      }
    }
  }

  Future<void> _loadStats() async {
    setState(() => _isLoading = true);
    try {
      final stats = await RustDatabaseService.instance.getDatabaseStats();
      final sizeMb = await RustDatabaseService.instance.getDatabaseSizeMB();
      if (mounted) {
        setState(() {
          _stats = stats;
          _databaseSizeMB = sizeMb;
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _performCleanup() async {
    setState(() => _isCleaningUp = true);
    try {
      final deletedCount = await RustDatabaseService.instance.cleanupOldEvents(daysToKeep: 30);
      await _loadStats();
      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
        AppSnackbar.success(
          context,
          '${l10n.cleanupCompleted}: $deletedCount ${l10n.eventsDeleted}',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isCleaningUp = false);
      }
    }
  }

  String _formatNumber(int number) {
    if (number >= 1000000) {
      return '${(number / 1000000).toStringAsFixed(1)}M';
    } else if (number >= 1000) {
      return '${(number / 1000).toStringAsFixed(1)}K';
    }
    return number.toString();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    final totalEvents = _stats['totalEvents'] as int? ?? 0;
    final textNotes = _stats['textNotes'] as int? ?? 0;
    final metadata = _stats['metadata'] as int? ?? 0;
    final contacts = _stats['contacts'] as int? ?? 0;
    final reactions = _stats['reactions'] as int? ?? 0;
    final reposts = _stats['reposts'] as int? ?? 0;
    final zaps = _stats['zaps'] as int? ?? 0;
    final articles = _stats['articles'] as int? ?? 0;

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
                child: TitleWidget(
                  title: l10n.databaseCache,
                  subtitle: l10n.databaseCacheSubtitle,
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: PrimaryButton(
                    label: _isCleaningUp ? l10n.cleanupCompleted : l10n.cleanupOldEvents,
                    icon: Icons.cleaning_services,
                    onPressed: (_isLoading || _isCleaningUp) ? null : _performCleanup,
                    isLoading: _isCleaningUp,
                    size: ButtonSize.large,
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      if (index == 0) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: Row(
                            children: [
                              Icon(
                                CarbonIcons.data_base,
                                color: context.colors.textSecondary,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                _isLoading
                                    ? 'Loading...'
                                    : '$_databaseSizeMB MB • ${_formatNumber(totalEvents)} events',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                  color: context.colors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        );
                      }

                      final items = [
                        {'label': l10n.textNotes, 'count': textNotes, 'icon': CarbonIcons.document},
                        {'label': l10n.profiles, 'count': metadata, 'icon': CarbonIcons.user},
                        {'label': l10n.contactLists, 'count': contacts, 'icon': CarbonIcons.user_multiple},
                        {'label': l10n.reactions, 'count': reactions, 'icon': CarbonIcons.favorite},
                        {'label': l10n.reposts, 'count': reposts, 'icon': CarbonIcons.repeat},
                        {'label': l10n.zaps, 'count': zaps, 'icon': CarbonIcons.flash},
                        {'label': l10n.articles, 'count': articles, 'icon': CarbonIcons.document_blank},
                      ];

                      if (index - 1 >= items.length) {
                        return const SizedBox.shrink();
                      }

                      final item = items[index - 1];
                      final count = item['count'] as int;

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: context.colors.overlayLight,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                item['icon'] as IconData,
                                color: context.colors.textPrimary,
                                size: 20,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  item['label'] as String,
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: context.colors.textPrimary,
                                  ),
                                ),
                              ),
                              Text(
                                _formatNumber(count),
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: context.colors.textPrimary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                    childCount: 8,
                  ),
                ),
              ),
            ],
          ),
          TopActionBarWidget(
            onBackPressed: () => Navigator.of(context).pop(),
            centerBubble: Text(
              l10n.databaseCache,
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
