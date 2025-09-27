import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../theme/theme_manager.dart';
import '../providers/interactions_provider.dart';
import '../services/data_service.dart';
import '../screens/share_note.dart';
import '../screens/note_statistics_page.dart';
import '../widgets/dialogs/repost_dialog.dart';
import '../widgets/dialogs/zap_dialog.dart';
import '../models/note_model.dart';

class InteractionBar extends StatefulWidget {
  final String noteId;
  final String currentUserNpub;
  final DataService? dataService;
  final NoteModel? note;
  final bool isReactionGlowing;
  final bool isReplyGlowing;
  final bool isRepostGlowing;
  final bool isZapGlowing;

  const InteractionBar({
    super.key,
    required this.noteId,
    required this.currentUserNpub,
    this.dataService,
    this.note,
    this.isReactionGlowing = false,
    this.isReplyGlowing = false,
    this.isRepostGlowing = false,
    this.isZapGlowing = false,
  });

  @override
  State<InteractionBar> createState() => _InteractionBarState();
}

class _InteractionBarState extends State<InteractionBar> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  late final String _noteId;
  late final String _currentUserNpub;
  late final DataService? _dataService;
  late final NoteModel? _note;
  late final String _widgetKey;

  Timer? _updateTimer;
  static const Duration _updateDelay = Duration(milliseconds: 200);

  final ValueNotifier<_InteractionState> _stateNotifier = ValueNotifier(_InteractionState.initial());

  bool _isDisposed = false;
  bool _isInitialized = false;
  bool _isUpdating = false;

  @override
  void initState() {
    super.initState();
    _precomputeData();
    _initializeAsync();
  }

  void _precomputeData() {
    _noteId = widget.noteId;
    _currentUserNpub = widget.currentUserNpub;
    _dataService = widget.dataService;
    _note = widget.note;
    _widgetKey = '${_noteId}_${_currentUserNpub.hashCode}';
    _isInitialized = true;
  }

  void _initializeAsync() {
    if (_currentUserNpub.isEmpty || _dataService == null) return;

    Future.microtask(() {
      if (_isDisposed || !mounted) return;

      if (!InteractionsProvider.instance.isInitialized) {
        Timer.periodic(const Duration(milliseconds: 100), (timer) {
          if (_isDisposed || !mounted) {
            timer.cancel();
            return;
          }

          if (InteractionsProvider.instance.isInitialized) {
            timer.cancel();
            _loadInitialState();
            _setupProviderListener();
          }
        });
      } else {
        _loadInitialState();
        _setupProviderListener();
      }
    });
  }

  void _loadInitialState() {
    if (_isDisposed || !mounted) return;

    try {
      final provider = InteractionsProvider.instance;
      if (!provider.isInitialized) return;

      _stateNotifier.value = _InteractionState(
        replyCount: provider.getReplyCount(_noteId),
        repostCount: provider.getRepostCount(_noteId),
        reactionCount: provider.getReactionCount(_noteId),
        zapAmount: provider.getZapAmount(_noteId),
        hasReplied: provider.hasUserReplied(_currentUserNpub, _noteId),
        hasReposted: provider.hasUserReposted(_currentUserNpub, _noteId),
        hasReacted: provider.hasUserReacted(_currentUserNpub, _noteId),
        hasZapped: provider.hasUserZapped(_currentUserNpub, _noteId),
      );
    } catch (e) {
      debugPrint('[InteractionBar] Error loading initial state: $e');
    }
  }

  void _setupProviderListener() {
    if (_isDisposed || !mounted) return;

    try {
      InteractionsProvider.instance.addListener(_onProviderUpdate);
    } catch (e) {
      debugPrint('[InteractionBar] Error setting up provider listener: $e');
    }
  }

  void _onProviderUpdate() {
    if (!mounted || _isDisposed || _isUpdating) return;

    _updateTimer?.cancel();
    _updateTimer = Timer(_updateDelay, () {
      if (!mounted || _isDisposed) return;

      _isUpdating = true;

      try {
        final provider = InteractionsProvider.instance;
        if (!provider.isInitialized) {
          _isUpdating = false;
          return;
        }

        final currentState = _stateNotifier.value;

        final newState = _InteractionState(
          replyCount: provider.getReplyCount(_noteId),
          repostCount: provider.getRepostCount(_noteId),
          reactionCount: provider.getReactionCount(_noteId),
          zapAmount: provider.getZapAmount(_noteId),
          hasReplied: provider.hasUserReplied(_currentUserNpub, _noteId),
          hasReposted: provider.hasUserReposted(_currentUserNpub, _noteId),
          hasReacted: provider.hasUserReacted(_currentUserNpub, _noteId),
          hasZapped: provider.hasUserZapped(_currentUserNpub, _noteId),
        );

        if (currentState != newState) {
          _stateNotifier.value = newState;
        }
      } catch (e) {
        debugPrint('[InteractionBar] Error in provider update: $e');
      } finally {
        _isUpdating = false;
      }
    });
  }

  @override
  void dispose() {
    _isDisposed = true;
    _updateTimer?.cancel();

    try {
      InteractionsProvider.instance.removeListener(_onProviderUpdate);
    } catch (e) {
      debugPrint('[InteractionBar] Error removing provider listener: $e');
    }

    try {
      _stateNotifier.dispose();
    } catch (e) {
      debugPrint('[InteractionBar] Error disposing state notifier: $e');
    }

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (!_isInitialized || _currentUserNpub.isEmpty || !InteractionsProvider.instance.isInitialized || _dataService == null) {
      return const SizedBox.shrink();
    }

    return SizedBox(
      height: 32,
      child: RepaintBoundary(
        key: ValueKey(_widgetKey),
        child: ValueListenableBuilder<_InteractionState>(
          valueListenable: _stateNotifier,
          builder: (context, state, _) {
            final colors = context.colors;

            return _StaticInteractionRow(
              state: state,
              noteId: _noteId,
              currentUserNpub: _currentUserNpub,
              dataService: _dataService,
              note: _note,
              isReactionGlowing: widget.isReactionGlowing,
              isReplyGlowing: widget.isReplyGlowing,
              isRepostGlowing: widget.isRepostGlowing,
              isZapGlowing: widget.isZapGlowing,
              widgetKey: _widgetKey,
              colors: colors,
            );
          },
        ),
      ),
    );
  }
}

class _InteractionState {
  final int replyCount;
  final int repostCount;
  final int reactionCount;
  final int zapAmount;
  final bool hasReplied;
  final bool hasReposted;
  final bool hasReacted;
  final bool hasZapped;

  const _InteractionState({
    required this.replyCount,
    required this.repostCount,
    required this.reactionCount,
    required this.zapAmount,
    required this.hasReplied,
    required this.hasReposted,
    required this.hasReacted,
    required this.hasZapped,
  });

  factory _InteractionState.initial() {
    return const _InteractionState(
      replyCount: 0,
      repostCount: 0,
      reactionCount: 0,
      zapAmount: 0,
      hasReplied: false,
      hasReposted: false,
      hasReacted: false,
      hasZapped: false,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _InteractionState &&
          runtimeType == other.runtimeType &&
          replyCount == other.replyCount &&
          repostCount == other.repostCount &&
          reactionCount == other.reactionCount &&
          zapAmount == other.zapAmount &&
          hasReplied == other.hasReplied &&
          hasReposted == other.hasReposted &&
          hasReacted == other.hasReacted &&
          hasZapped == other.hasZapped;

  @override
  int get hashCode =>
      replyCount.hashCode ^
      repostCount.hashCode ^
      reactionCount.hashCode ^
      zapAmount.hashCode ^
      hasReplied.hashCode ^
      hasReposted.hashCode ^
      hasReacted.hashCode ^
      hasZapped.hashCode;
}

class _StaticInteractionRow extends StatelessWidget {
  final _InteractionState state;
  final String noteId;
  final String currentUserNpub;
  final DataService? dataService;
  final NoteModel? note;
  final bool isReactionGlowing;
  final bool isReplyGlowing;
  final bool isRepostGlowing;
  final bool isZapGlowing;
  final String widgetKey;
  final dynamic colors;

  const _StaticInteractionRow({
    required this.state,
    required this.noteId,
    required this.currentUserNpub,
    required this.dataService,
    required this.note,
    required this.isReactionGlowing,
    required this.isReplyGlowing,
    required this.isRepostGlowing,
    required this.isZapGlowing,
    required this.widgetKey,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _UltraStaticButton(
          key: ValueKey('${widgetKey}_reply'),
          iconPath: 'assets/reply_button.svg',
          count: state.replyCount,
          isActive: state.hasReplied || isReplyGlowing,
          activeColor: colors.reply,
          inactiveColor: colors.secondary,
          onTap: () => _handleReplyTap(context),
        ),
        _UltraStaticButton(
          key: ValueKey('${widgetKey}_repost'),
          iconPath: 'assets/repost_button.svg',
          count: state.repostCount,
          isActive: state.hasReposted || isRepostGlowing,
          activeColor: colors.repost,
          inactiveColor: colors.secondary,
          onTap: () => _handleRepostTap(context),
        ),
        _SmartLikeButton(
          key: ValueKey('${widgetKey}_reaction'),
          iconPath: 'assets/reaction_button.svg',
          count: state.reactionCount,
          isActive: state.hasReacted || isReactionGlowing,
          activeColor: colors.reaction,
          inactiveColor: colors.secondary,
          onTap: () => _handleReactionTap(),
        ),
        _UltraStaticButton(
          key: ValueKey('${widgetKey}_zap'),
          iconPath: 'assets/zap_button.svg',
          count: state.zapAmount,
          isActive: state.hasZapped || isZapGlowing,
          activeColor: colors.zap,
          inactiveColor: colors.secondary,
          onTap: () => _handleZapTap(context),
        ),
        _UltraStaticButton(
          key: ValueKey('${widgetKey}_stats'),
          iconPath: null,
          count: 0,
          isActive: false,
          activeColor: colors.secondary,
          inactiveColor: colors.secondary,
          onTap: () => _handleStatsTap(context),
          isStatsButton: true,
        ),
      ],
    );
  }

  void _handleReplyTap(BuildContext context) {
    if (dataService == null) {
      debugPrint('[InteractionBar] Cannot reply - dataService is null');
      return;
    }
    try {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ShareNotePage(
            dataService: dataService!,
            replyToNoteId: noteId,
          ),
        ),
      );
    } catch (e) {
      debugPrint('[InteractionBar] Error navigating to reply: $e');
    }
  }

  void _handleRepostTap(BuildContext context) {
    if (dataService == null || note == null || state.hasReposted) {
      debugPrint(
          '[InteractionBar] Cannot repost - dataService: ${dataService != null}, note: ${note != null}, hasReposted: ${state.hasReposted}');
      return;
    }
    try {
      showRepostDialog(
        context: context,
        dataService: dataService!,
        note: note!,
      );
    } catch (e) {
      debugPrint('[InteractionBar] Error showing repost dialog: $e');
    }
  }

  Future<bool> _handleReactionTap() async {
    if (dataService == null || state.hasReacted) {
      debugPrint('[InteractionBar] Cannot react - dataService: ${dataService != null}, hasReacted: ${state.hasReacted}');
      return false;
    }
    try {
      await dataService!.sendReaction(noteId, '+');
      return true;
    } catch (e) {
      debugPrint('[InteractionBar] Error sending reaction: $e');
      return false;
    }
  }

  void _handleZapTap(BuildContext context) {
    if (dataService == null || note == null) {
      debugPrint('[InteractionBar] Cannot zap - dataService: ${dataService != null}, note: ${note != null}');
      return;
    }
    try {
      showZapDialog(
        context: context,
        dataService: dataService!,
        note: note!,
      );
    } catch (e) {
      debugPrint('[InteractionBar] Error showing zap dialog: $e');
    }
  }

  void _handleStatsTap(BuildContext context) {
    if (dataService == null || note == null) {
      debugPrint('[InteractionBar] Cannot show stats - dataService: ${dataService != null}, note: ${note != null}');
      return;
    }
    try {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => NoteStatisticsPage(
            note: note!,
            dataService: dataService!,
          ),
        ),
      );
    } catch (e) {
      debugPrint('[InteractionBar] Error navigating to stats: $e');
    }
  }
}

class _UltraStaticButton extends StatelessWidget {
  final String? iconPath;
  final int count;
  final bool isActive;
  final Color activeColor;
  final Color inactiveColor;
  final VoidCallback? onTap;
  final bool isStatsButton;

  static final Map<String, Widget> _globalCache = <String, Widget>{};

  const _UltraStaticButton({
    super.key,
    required this.iconPath,
    required this.count,
    required this.isActive,
    required this.activeColor,
    required this.inactiveColor,
    this.onTap,
    this.isStatsButton = false,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveColor = isActive ? activeColor : inactiveColor;
    final cacheKey = _generateCacheKey();

    return RepaintBoundary(
      child: GestureDetector(
        onTap: onTap,
        child: _globalCache.putIfAbsent(cacheKey, () => _buildContent(effectiveColor)),
      ),
    );
  }

  String _generateCacheKey() {
    if (isStatsButton) {
      return 'stats_${inactiveColor.value}';
    }

    final countText = count > 0 ? _formatCount(count) : '';
    return '${iconPath}_${isActive}_${activeColor.value}_${inactiveColor.value}_$countText';
  }

  Widget _buildContent(Color effectiveColor) {
    if (isStatsButton) {
      return Padding(
        padding: const EdgeInsets.only(left: 6),
        child: Icon(Icons.bar_chart, size: 21, color: effectiveColor),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SvgPicture.asset(
          iconPath!,
          width: 15.5,
          height: 15.5,
          colorFilter: ColorFilter.mode(effectiveColor, BlendMode.srcIn),
        ),
        if (count > 0) ...[
          const SizedBox(width: 6.5),
          Text(
            _formatCount(count),
            style: TextStyle(fontSize: 15, color: inactiveColor),
          ),
        ],
      ],
    );
  }

  static String _formatCount(int count) {
    if (count >= 1000) {
      final formatted = (count / 1000).toStringAsFixed(1);
      return formatted.endsWith('.0') ? '${formatted.substring(0, formatted.length - 2)}K' : '${formatted}K';
    }
    return count.toString();
  }
}

class _SmartLikeButton extends StatefulWidget {
  final String iconPath;
  final int count;
  final bool isActive;
  final Color activeColor;
  final Color inactiveColor;
  final Future<bool> Function() onTap;

  const _SmartLikeButton({
    super.key,
    required this.iconPath,
    required this.count,
    required this.isActive,
    required this.activeColor,
    required this.inactiveColor,
    required this.onTap,
  });

  @override
  State<_SmartLikeButton> createState() => _SmartLikeButtonState();
}

class _SmartLikeButtonState extends State<_SmartLikeButton> {
  late bool _localIsActive;

  @override
  void initState() {
    super.initState();
    _localIsActive = widget.isActive;
  }

  @override
  void didUpdateWidget(_SmartLikeButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive != oldWidget.isActive) {
      _localIsActive = widget.isActive;
    }
  }

  @override
  Widget build(BuildContext context) {
    final effectiveColor = _localIsActive ? widget.activeColor : widget.inactiveColor;
    final cacheKey = '${widget.iconPath}_${_localIsActive}_${widget.activeColor.value}_${widget.inactiveColor.value}_${widget.count}';

    return RepaintBoundary(
      child: GestureDetector(
        onTap: () async {
          if (_localIsActive) return;

          final result = await widget.onTap();
          if (result && mounted) {
            setState(() {
              _localIsActive = true;
            });
          }
        },
        child: _UltraStaticButton._globalCache.putIfAbsent(cacheKey, () {
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SvgPicture.asset(
                widget.iconPath,
                width: 15.5,
                height: 15.5,
                colorFilter: ColorFilter.mode(effectiveColor, BlendMode.srcIn),
              ),
              if (widget.count > 0) ...[
                const SizedBox(width: 6.5),
                Text(
                  _UltraStaticButton._formatCount(widget.count),
                  style: TextStyle(fontSize: 15, color: widget.inactiveColor),
                ),
              ],
            ],
          );
        }),
      ),
    );
  }
}
