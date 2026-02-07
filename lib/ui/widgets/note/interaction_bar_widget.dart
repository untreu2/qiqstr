import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:carbon_icons/carbon_icons.dart';
import '../../../data/services/rust_nostr_bridge.dart';
import '../../theme/theme_manager.dart';
import '../../screens/note/share_note.dart';
import '../../../presentation/blocs/theme/theme_bloc.dart';
import '../../../presentation/blocs/interaction/interaction_bloc.dart';
import '../../../presentation/blocs/interaction/interaction_event.dart';
import '../../../presentation/blocs/interaction/interaction_state.dart';
import '../../../data/services/event_verifier.dart';
import '../../../data/repositories/feed_repository.dart';
import '../../../data/sync/sync_service.dart';
import '../../../core/di/app_di.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../dialogs/zap_dialog.dart';
import '../dialogs/delete_note_dialog.dart';
import '../common/snackbar_widget.dart';

class InteractionBar extends StatefulWidget {
  final String noteId;
  final String currentUserHex;
  final Map<String, dynamic>? note;
  final bool isBigSize;

  const InteractionBar({
    super.key,
    required this.noteId,
    required this.currentUserHex,
    this.note,
    this.isBigSize = false,
  });

  @override
  State<InteractionBar> createState() => _InteractionBarState();
}

class _InteractionBarState extends State<InteractionBar> {
  final GlobalKey _repostButtonKey = GlobalKey();
  final GlobalKey _moreButtonKey = GlobalKey();
  late final InteractionBloc _interactionBloc;

  @override
  void initState() {
    super.initState();
    _interactionBloc = InteractionBloc(
      syncService: AppDI.get<SyncService>(),
      feedRepository: AppDI.get<FeedRepository>(),
      noteId: widget.noteId,
      currentUserHex: widget.currentUserHex,
      note: widget.note,
    );
    _interactionBloc.add(InteractionInitialized(
      noteId: widget.noteId,
      currentUserHex: widget.currentUserHex,
      note: widget.note,
    ));
  }

  @override
  void didUpdateWidget(InteractionBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.noteId != widget.noteId || oldWidget.note != widget.note) {
      _interactionBloc.add(InteractionNoteUpdated(widget.note));
    }
  }

  @override
  void dispose() {
    _interactionBloc.close();
    super.dispose();
  }

  void _handleReplyTap() {
    HapticFeedback.lightImpact();
    ShareNotePage.show(
      context,
      replyToNoteId: widget.noteId,
    );
  }

  void _handleRepostTap(InteractionLoaded state) {
    HapticFeedback.lightImpact();
    _showRepostMenu(state);
  }

  void _showRepostMenu(InteractionLoaded state) {
    final RenderBox? renderBox =
        _repostButtonKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final offset = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;
    final hasReposted = state.hasReposted;

    final items = <PopupMenuItem<String>>[];

    if (hasReposted) {
      items.add(
        PopupMenuItem(
          value: 'undo_repost',
          enabled: widget.note != null,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Row(
              children: [
                Icon(Icons.undo, size: 17, color: context.colors.background),
                const SizedBox(width: 12),
                Text(
                  'Undo repost',
                  style: TextStyle(
                    color: context.colors.background,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      items.add(
        PopupMenuItem(
          value: 'repost',
          enabled: widget.note != null,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Row(
              children: [
                Icon(Icons.repeat, size: 17, color: context.colors.background),
                const SizedBox(width: 12),
                Text(
                  'Repost again',
                  style: TextStyle(
                    color: context.colors.background,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } else {
      items.add(
        PopupMenuItem(
          value: 'repost',
          enabled: widget.note != null,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Row(
              children: [
                Icon(Icons.repeat, size: 17, color: context.colors.background),
                const SizedBox(width: 12),
                Text(
                  'Repost',
                  style: TextStyle(
                    color: context.colors.background,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    items.add(
      PopupMenuItem(
        value: 'quote',
        enabled: widget.note != null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Row(
            children: [
              Icon(Icons.format_quote,
                  size: 17, color: context.colors.background),
              const SizedBox(width: 12),
              Text(
                'Quote',
                style: TextStyle(
                  color: context.colors.background,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(
        offset.dx,
        offset.dy + size.height,
        offset.dx + size.width,
        offset.dy + size.height + 200,
      ),
      color: context.colors.textPrimary,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(40)),
      items: items,
    ).then((value) {
      if (value == null) return;
      HapticFeedback.lightImpact();
      if (value == 'undo_repost') {
        if (widget.note == null) return;
        _interactionBloc.add(const InteractionRepostDeleted());
      } else if (value == 'repost') {
        if (widget.note == null) return;
        if (hasReposted) {
          _interactionBloc.add(const InteractionRepostDeleted());
          Future.delayed(const Duration(milliseconds: 100), () {
            if (mounted) {
              _interactionBloc.add(const InteractionRepostRequested());
            }
          });
        } else {
          _interactionBloc.add(const InteractionRepostRequested());
        }
      } else if (value == 'quote') {
        _handleQuoteTap();
      }
    });
  }

  void _handleQuoteTap() {
    if (widget.note == null) return;
    final noteToQuote = _interactionBloc.getNoteForActions();
    if (noteToQuote == null) return;
    final noteId = noteToQuote['id'] as String? ?? '';
    final bech32 = encodeBasicBech32(noteId, 'note');
    final quoteText = 'nostr:$bech32';

    ShareNotePage.show(
      context,
      initialText: quoteText,
    );
  }

  Future<void> _handleReactionTap() async {
    HapticFeedback.lightImpact();
    if (!mounted) return;
    _interactionBloc.add(const InteractionReactRequested());
  }

  void _handleZapTap(InteractionLoaded state) async {
    HapticFeedback.lightImpact();
    if (widget.note == null || state.hasZapped || !mounted) return;

    final noteToZap = _interactionBloc.getNoteForActions();
    if (noteToZap == null) return;

    final themeState = context.read<ThemeBloc>().state;

    if (themeState.oneTapZap) {
      await processZapDirectly(
        context,
        noteToZap,
        themeState.defaultZapAmount,
      );

      if (!mounted) return;
      _interactionBloc.add(const InteractionStateRefreshed());
    } else {
      final zapResult = await showZapDialog(
        context: context,
        note: noteToZap,
      );

      if (!mounted) return;

      final zapSuccess = zapResult['success'] as bool;
      if (!zapSuccess) {
        _interactionBloc.add(const InteractionStateRefreshed());
      }
    }
  }

  void _handleZapLongPress(InteractionLoaded state) async {
    HapticFeedback.mediumImpact();
    if (widget.note == null || state.hasZapped || !mounted) return;

    final noteToZap = _interactionBloc.getNoteForActions();
    if (noteToZap == null) return;

    final zapResult = await showZapDialog(
      context: context,
      note: noteToZap,
    );

    if (!mounted) return;

    final zapSuccess = zapResult['success'] as bool;
    if (!zapSuccess) {
      _interactionBloc.add(const InteractionStateRefreshed());
    }
  }

  void _handleStatsTap() {
    HapticFeedback.lightImpact();
    if (widget.note == null) return;

    final noteForStats = _interactionBloc.getNoteForActions();
    if (noteForStats == null) return;

    final currentLocation = GoRouterState.of(context).matchedLocation;
    if (currentLocation.startsWith('/home/feed')) {
      context.push('/home/feed/note-statistics', extra: noteForStats);
    } else if (currentLocation.startsWith('/home/notifications')) {
      context.push('/home/notifications/note-statistics', extra: noteForStats);
    } else {
      context.push('/note-statistics', extra: noteForStats);
    }
  }

  Future<void> _handleVerifyTap() async {
    HapticFeedback.lightImpact();
    if (widget.note == null || !mounted) return;

    final note = _interactionBloc.getNoteForActions();
    if (note == null) return;

    try {
      final verifier = EventVerifier.instance;

      final noteValid = await verifier.verifyNote(note);
      if (!mounted) return;

      final authorHex =
          note['pubkey'] as String? ?? note['author'] as String? ?? '';
      bool profileValid = false;
      if (authorHex.isNotEmpty) {
        profileValid = await verifier.verifyProfile(authorHex);
      }

      if (!mounted) return;

      if (noteValid && profileValid) {
        AppSnackbar.success(
            context, 'Event and author profile signatures verified');
      } else if (noteValid && !profileValid) {
        AppSnackbar.success(context,
            'Event signature verified, profile not available for verification');
      } else {
        AppSnackbar.error(context, 'Event signature verification failed');
      }
    } catch (e) {
      if (mounted) {
        AppSnackbar.error(context, 'Verification failed: $e');
      }
    }
  }

  void _handleDeleteTap() {
    HapticFeedback.lightImpact();
    if (widget.note == null || !mounted) return;

    showDeleteNoteDialog(
      context: context,
      onConfirm: _confirmDelete,
    );
  }

  Future<void> _confirmDelete() async {
    if (!mounted) return;
    _interactionBloc.add(const InteractionNoteDeleted());
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final height = widget.isBigSize ? 36.0 : 32.0;

    return BlocProvider<InteractionBloc>.value(
      value: _interactionBloc,
      child: BlocBuilder<InteractionBloc, InteractionState>(
        builder: (context, state) {
          final interactionState =
              state is InteractionLoaded ? state : const InteractionLoaded();

          return RepaintBoundary(
            key: ValueKey('interaction_${widget.noteId}'),
            child: SizedBox(
              height: height,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _InteractionButton(
                    iconPath: 'assets/reply_button_2.svg',
                    count: interactionState.replyCount,
                    isActive: false,
                    activeColor: colors.reply,
                    inactiveColor: colors.secondary,
                    onTap: _handleReplyTap,
                    isBigSize: widget.isBigSize,
                  ),
                  _InteractionButton(
                    key: _repostButtonKey,
                    carbonIcon: CarbonIcons.renew,
                    count: interactionState.repostCount,
                    isActive: interactionState.hasReposted,
                    activeColor: colors.repost,
                    inactiveColor: colors.secondary,
                    onTap: () => _handleRepostTap(interactionState),
                    isBigSize: widget.isBigSize,
                    buttonType: _ButtonType.repost,
                  ),
                  _InteractionButton(
                    iconPath: 'assets/reaction_button.svg',
                    count: interactionState.reactionCount,
                    isActive: interactionState.hasReacted,
                    activeColor: colors.reaction,
                    inactiveColor: colors.secondary,
                    onTap: _handleReactionTap,
                    activeCarbonIcon: CarbonIcons.favorite_filled,
                    isBigSize: widget.isBigSize,
                    buttonType: _ButtonType.reaction,
                  ),
                  _InteractionButton(
                    iconPath: 'assets/zap_button.svg',
                    count: interactionState.zapAmount,
                    isActive: interactionState.hasZapped,
                    activeColor: colors.zap,
                    inactiveColor: colors.secondary,
                    onTap: () => _handleZapTap(interactionState),
                    onLongPress: () => _handleZapLongPress(interactionState),
                    activeCarbonIcon: CarbonIcons.flash_filled,
                    isBigSize: widget.isBigSize,
                    buttonType: _ButtonType.zap,
                  ),
                  _buildPopupMenu(colors, interactionState),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _showMoreMenu(InteractionLoaded state) {
    final RenderBox? renderBox =
        _moreButtonKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final offset = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;

    final items = <PopupMenuItem<String>>[
      PopupMenuItem(
        value: 'verify',
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Row(
            children: [
              Icon(CarbonIcons.checkmark_filled,
                  size: 17, color: context.colors.background),
              const SizedBox(width: 12),
              Text(
                'Verify signature',
                style: TextStyle(
                  color: context.colors.background,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
      PopupMenuItem(
        value: 'interactions',
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Row(
            children: [
              Icon(CarbonIcons.chart_bar,
                  size: 17, color: context.colors.background),
              const SizedBox(width: 12),
              Text(
                'Interactions',
                style: TextStyle(
                  color: context.colors.background,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    ];

    final noteForActions = _interactionBloc.getNoteForActions();
    final noteAuthor = noteForActions?['author'] as String?;
    if (noteAuthor == widget.currentUserHex) {
      items.add(
        PopupMenuItem(
          value: 'delete',
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Row(
              children: [
                Icon(CarbonIcons.delete,
                    size: 17, color: context.colors.background),
                const SizedBox(width: 12),
                Text(
                  'Delete',
                  style: TextStyle(
                    color: context.colors.background,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(
        offset.dx,
        offset.dy + size.height,
        offset.dx + size.width,
        offset.dy + size.height + 200,
      ),
      color: context.colors.textPrimary,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(40)),
      items: items,
    ).then((value) {
      if (value == null) return;
      HapticFeedback.lightImpact();
      if (value == 'verify') {
        _handleVerifyTap();
      } else if (value == 'interactions') {
        _handleStatsTap();
      } else if (value == 'delete') {
        _handleDeleteTap();
      }
    });
  }

  Widget _buildPopupMenu(dynamic colors, InteractionLoaded state) {
    return InkWell(
      key: _moreButtonKey,
      onTap: () => _showMoreMenu(state),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Transform.translate(
          offset: const Offset(-4, 0),
          child: Icon(
            Icons.more_horiz,
            size: widget.isBigSize ? 19.0 : 17.0,
            color: colors.secondary,
          ),
        ),
      ),
    );
  }
}

enum _ButtonType { reply, repost, reaction, zap }

class _InteractionButton extends StatelessWidget {
  final String? iconPath;
  final IconData? carbonIcon;
  final IconData? activeCarbonIcon;
  final int count;
  final bool isActive;
  final Color activeColor;
  final Color inactiveColor;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool isBigSize;
  final _ButtonType buttonType;

  const _InteractionButton({
    super.key,
    this.iconPath,
    this.carbonIcon,
    this.activeCarbonIcon,
    required this.count,
    required this.isActive,
    required this.activeColor,
    required this.inactiveColor,
    required this.onTap,
    this.onLongPress,
    required this.isBigSize,
    this.buttonType = _ButtonType.reply,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveColor = isActive ? activeColor : inactiveColor;
    final iconSize = isBigSize ? 16.0 : 14.5;
    final fontSize = isBigSize ? 15.0 : 14.0;
    final spacing = isBigSize ? 7.0 : 6.5;

    return RepaintBoundary(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _buildIcon(iconSize, effectiveColor),
                if (count > 0) ...[
                  SizedBox(width: spacing),
                  Transform.translate(
                    offset: Offset(0, isBigSize ? -2.0 : -3.2),
                    child: Text(
                      _formatCount(count),
                      style: TextStyle(
                        fontSize: fontSize,
                        color: effectiveColor,
                        fontWeight:
                            isActive ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildIcon(double iconSize, Color effectiveColor) {
    if (buttonType == _ButtonType.repost && carbonIcon != null) {
      return Icon(carbonIcon, size: iconSize + 2.0, color: effectiveColor);
    }

    if (activeCarbonIcon != null && isActive) {
      final sizeAdjustment = buttonType == _ButtonType.reaction
          ? 4.0
          : buttonType == _ButtonType.zap
              ? 3.0
              : 1.0;
      return Icon(
        activeCarbonIcon,
        size: iconSize + sizeAdjustment,
        color: activeColor,
      );
    }

    if (iconPath != null) {
      return SvgPicture.asset(
        iconPath!,
        width: iconSize,
        height: iconSize,
        colorFilter: ColorFilter.mode(effectiveColor, BlendMode.srcIn),
        allowDrawingOutsideViewBox: false,
        placeholderBuilder: (_) => SizedBox(width: iconSize, height: iconSize),
      );
    }

    return const SizedBox.shrink();
  }

  String _formatCount(int count) {
    if (count >= 1000) {
      final formatted = (count / 1000).toStringAsFixed(1);
      return formatted.endsWith('.0')
          ? '${formatted.substring(0, formatted.length - 2)}K'
          : '${formatted}K';
    }
    return count.toString();
  }
}
