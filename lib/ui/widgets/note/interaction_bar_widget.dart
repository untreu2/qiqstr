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
import '../common/popup_menu_widget.dart';
import '../../../l10n/app_localizations.dart';
import '../../../data/services/encrypted_bookmark_service.dart';
import '../../../data/services/pinned_notes_service.dart';

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
  late final InteractionBloc _interactionBloc;
  bool _isBookmarked = false;

  @override
  void initState() {
    super.initState();
    _isBookmarked =
        EncryptedBookmarkService.instance.isBookmarked(widget.noteId);
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
      parentAuthor: widget.note?['pubkey'] as String?,
    );
  }

  List<AppPopupMenuItem> _buildRepostMenuItems(InteractionLoaded state) {
    final l10n = AppLocalizations.of(context)!;
    final items = <AppPopupMenuItem>[];

    if (state.hasReposted) {
      items.add(AppPopupMenuItem(
        value: 'undo_repost',
        icon: Icons.undo,
        label: l10n.undoRepost,
      ));
      items.add(AppPopupMenuItem(
        value: 'repost',
        icon: Icons.repeat,
        label: l10n.repostAgain,
      ));
    } else {
      items.add(AppPopupMenuItem(
        value: 'repost',
        icon: Icons.repeat,
        label: l10n.repost,
      ));
    }

    items.add(AppPopupMenuItem(
      value: 'quote',
      icon: Icons.format_quote,
      label: l10n.quote,
    ));

    return items;
  }

  void _handleRepostMenuSelection(String value, bool hasReposted) {
    if (widget.note == null) return;

    switch (value) {
      case 'undo_repost':
        _interactionBloc.add(const InteractionRepostDeleted());
      case 'repost':
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
      case 'quote':
        _handleQuoteTap();
    }
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
    if (widget.note == null ||
        state.hasZapped ||
        state.zapProcessing ||
        !mounted) {
      return;
    }

    final noteToZap = _interactionBloc.getNoteForActions();
    if (noteToZap == null) return;

    final themeState = context.read<ThemeBloc>().state;

    if (themeState.oneTapZap) {
      final amount = themeState.defaultZapAmount;
      _interactionBloc.add(InteractionZapStarted(amount: amount));

      final success = await processZapDirectly(context, noteToZap, amount);
      if (!mounted) return;

      if (success) {
        _interactionBloc.add(InteractionZapCompleted(amount: amount));
      } else {
        _interactionBloc.add(const InteractionZapFailed());
      }
    } else {
      await _openZapDialog(noteToZap);
    }
  }

  void _handleZapLongPress(InteractionLoaded state) async {
    HapticFeedback.mediumImpact();
    if (widget.note == null ||
        state.hasZapped ||
        state.zapProcessing ||
        !mounted) {
      return;
    }

    final noteToZap = _interactionBloc.getNoteForActions();
    if (noteToZap == null) return;

    await _openZapDialog(noteToZap);
  }

  Future<void> _openZapDialog(Map<String, dynamic> noteToZap) async {
    final zapResult = await showZapDialog(
      context: context,
      note: noteToZap,
    );

    if (!mounted) return;

    final confirmed = zapResult['confirmed'] as bool? ?? false;
    final amount = zapResult['amount'] as int? ?? 0;
    final comment = zapResult['comment'] as String? ?? '';

    if (!confirmed || amount <= 0) return;

    _interactionBloc.add(InteractionZapStarted(amount: amount));

    final success =
        await processZapWithComment(context, noteToZap, amount, comment);
    if (!mounted) return;

    if (success) {
      _interactionBloc.add(InteractionZapCompleted(amount: amount));
    } else {
      _interactionBloc.add(const InteractionZapFailed());
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
    final l10n = AppLocalizations.of(context)!;
    HapticFeedback.lightImpact();
    if (widget.note == null || !mounted) return;

    final note = _interactionBloc.getNoteForActions();
    if (note == null) return;

    try {
      final verifier = EventVerifier.instance;

      final isRepost = note['isRepost'] as bool? ?? false;
      final repostEventId = note['repostEventId'] as String?;

      bool noteValid;
      if (isRepost && repostEventId != null && repostEventId.isNotEmpty) {
        noteValid = await verifier.verifyNote({'id': repostEventId});
        if (!noteValid) {
          noteValid = await verifier.verifyNote(note);
        }
      } else {
        noteValid = await verifier.verifyNote(note);
      }
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
            context, l10n.eventAndAuthorProfileSignaturesVerified);
      } else if (noteValid && !profileValid) {
        AppSnackbar.success(context,
            l10n.eventSignatureVerified);
      } else {
        AppSnackbar.error(context, l10n.eventSignatureVerificationFailed);
      }
    } catch (e) {
      if (mounted) {
        AppSnackbar.error(context, l10n.errorWithMessage(e.toString()));
      }
    }
  }

  void _handleBookmarkTap() {
    HapticFeedback.lightImpact();
    if (!mounted) return;

    final bookmarkService = EncryptedBookmarkService.instance;

    if (_isBookmarked) {
      bookmarkService.removeBookmark(widget.noteId);
      setState(() => _isBookmarked = false);
      _publishBookmarkUpdate();
    } else {
      bookmarkService.addBookmark(widget.noteId);
      setState(() => _isBookmarked = true);
      _publishBookmarkUpdate();
    }
  }

  Future<void> _publishBookmarkUpdate() async {
    try {
      final syncService = AppDI.get<SyncService>();
      final bookmarkService = EncryptedBookmarkService.instance;
      await syncService.publishBookmark(
        bookmarkedEventIds: bookmarkService.bookmarkedEventIds,
      );
    } catch (_) {}
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

  Future<void> _handlePinTap() async {
    final l10n = AppLocalizations.of(context)!;
    HapticFeedback.lightImpact();
    if (!mounted) return;

    final pinnedService = PinnedNotesService.instance;
    final isPinned = pinnedService.isPinned(widget.noteId);

    if (isPinned) {
      pinnedService.unpinNote(widget.noteId);
    } else {
      pinnedService.pinNote(widget.noteId);
    }

    try {
      final syncService = AppDI.get<SyncService>();
      await syncService.publishPinnedNotes(
        pinnedNoteIds: pinnedService.pinnedNoteIds,
      );
      if (mounted) {
        AppSnackbar.success(
          context,
          isPinned ? l10n.noteUnpinned : l10n.notePinned,
        );
      }
    } catch (_) {
      if (isPinned) {
        pinnedService.pinNote(widget.noteId);
      } else {
        pinnedService.unpinNote(widget.noteId);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final height = widget.isBigSize ? 36.0 : 32.0;

    return BlocProvider<InteractionBloc>.value(
      value: _interactionBloc,
      child: BlocConsumer<InteractionBloc, InteractionState>(
        listenWhen: (previous, current) {
          if (current is InteractionLoaded && current.noteDeleted) {
            final prev = previous is InteractionLoaded ? previous : null;
            return prev == null || !prev.noteDeleted;
          }
          return false;
        },
        listener: (context, state) {
          if (state is InteractionLoaded && state.noteDeleted) {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            }
          }
        },
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
                  _buildRepostPopupMenu(colors, interactionState),
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
                    isProcessing: interactionState.zapProcessing,
                    activeColor: colors.zap,
                    inactiveColor: colors.secondary,
                    onTap: () => _handleZapTap(interactionState),
                    onLongPress: () => _handleZapLongPress(interactionState),
                    activeCarbonIcon: CarbonIcons.flash_filled,
                    isBigSize: widget.isBigSize,
                    buttonType: _ButtonType.zap,
                  ),
                  _InteractionButton(
                    carbonIcon: CarbonIcons.bookmark,
                    activeCarbonIcon: CarbonIcons.bookmark_filled,
                    count: 0,
                    isActive: _isBookmarked,
                    activeColor: colors.textPrimary,
                    inactiveColor: colors.secondary,
                    onTap: _handleBookmarkTap,
                    isBigSize: widget.isBigSize,
                    buttonType: _ButtonType.bookmark,
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

  List<AppPopupMenuItem> _buildMoreMenuItems() {
    final l10n = AppLocalizations.of(context)!;
    final items = <AppPopupMenuItem>[
      AppPopupMenuItem(
        value: 'verify',
        icon: CarbonIcons.checkmark_filled,
        label: l10n.verifySignature,
      ),
      AppPopupMenuItem(
        value: 'interactions',
        icon: CarbonIcons.chart_bar,
        label: l10n.interactions,
      ),
    ];

    final noteForActions = _interactionBloc.getNoteForActions();
    final noteAuthor = noteForActions?['pubkey'] as String? ??
        noteForActions?['author'] as String?;
    if (noteAuthor == widget.currentUserHex) {
      final isPinned = PinnedNotesService.instance.isPinned(widget.noteId);
      items.add(AppPopupMenuItem(
        value: 'pin',
        icon: isPinned ? CarbonIcons.pin_filled : CarbonIcons.pin,
        label: isPinned ? l10n.unpinNote : l10n.pinNote,
      ));
      items.add(AppPopupMenuItem(
        value: 'delete',
        icon: CarbonIcons.delete,
        label: l10n.delete,
      ));
    }

    return items;
  }

  void _handleMoreMenuSelection(String value) {
    switch (value) {
      case 'verify':
        _handleVerifyTap();
      case 'interactions':
        _handleStatsTap();
      case 'pin':
        _handlePinTap();
      case 'delete':
        _handleDeleteTap();
    }
  }

  Widget _buildRepostPopupMenu(dynamic colors, InteractionLoaded state) {
    final effectiveColor =
        state.hasReposted ? colors.repost as Color : colors.secondary as Color;
    final iconSize = widget.isBigSize ? 16.5 : 16.5;
    final fontSize = widget.isBigSize ? 15.0 : 14.0;
    final spacing = widget.isBigSize ? 7.0 : 6.5;

    return AppPopupMenuButton(
      items: _buildRepostMenuItems(state),
      onSelected: (value) =>
          _handleRepostMenuSelection(value, state.hasReposted),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(CarbonIcons.renew, size: iconSize, color: effectiveColor),
            if (state.repostCount > 0) ...[
              SizedBox(width: spacing),
              Transform.translate(
                offset: Offset(0, widget.isBigSize ? -2.0 : -3.2),
                child: Text(
                  _formatCount(state.repostCount),
                  style: TextStyle(
                    fontSize: fontSize,
                    color: effectiveColor,
                    fontWeight: state.hasReposted
                        ? FontWeight.w600
                        : FontWeight.normal,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _formatCount(int count) {
    if (count >= 1000000) {
      final formatted = (count / 1000000).toStringAsFixed(1);
      return formatted.endsWith('.0')
          ? '${formatted.substring(0, formatted.length - 2)}M'
          : '${formatted}M';
    } else if (count >= 1000) {
      final formatted = (count / 1000).toStringAsFixed(1);
      return formatted.endsWith('.0')
          ? '${formatted.substring(0, formatted.length - 2)}K'
          : '${formatted}K';
    }
    return count.toString();
  }

  Widget _buildPopupMenu(dynamic colors, InteractionLoaded state) {
    return AppPopupMenuButton(
      items: _buildMoreMenuItems(),
      onSelected: _handleMoreMenuSelection,
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

enum _ButtonType { reply, repost, reaction, zap, bookmark }

class _InteractionButton extends StatelessWidget {
  final String? iconPath;
  final IconData? carbonIcon;
  final IconData? activeCarbonIcon;
  final int count;
  final bool isActive;
  final bool isProcessing;
  final Color activeColor;
  final Color inactiveColor;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool isBigSize;
  final _ButtonType buttonType;

  const _InteractionButton({
    this.iconPath,
    this.carbonIcon,
    this.activeCarbonIcon,
    required this.count,
    required this.isActive,
    this.isProcessing = false,
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
          onTap: isProcessing ? null : onTap,
          onLongPress: isProcessing ? null : onLongPress,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (isProcessing)
                  SizedBox(
                    width: iconSize,
                    height: iconSize,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      color: activeColor,
                    ),
                  )
                else
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
    if (buttonType == _ButtonType.bookmark) {
      return Icon(
        isActive
            ? (activeCarbonIcon ?? CarbonIcons.bookmark_filled)
            : (carbonIcon ?? CarbonIcons.bookmark),
        size: iconSize + 2.0,
        color: effectiveColor,
      );
    }

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
    if (count >= 1000000) {
      final formatted = (count / 1000000).toStringAsFixed(1);
      return formatted.endsWith('.0')
          ? '${formatted.substring(0, formatted.length - 2)}M'
          : '${formatted}M';
    } else if (count >= 1000) {
      final formatted = (count / 1000).toStringAsFixed(1);
      return formatted.endsWith('.0')
          ? '${formatted.substring(0, formatted.length - 2)}K'
          : '${formatted}K';
    }
    return count.toString();
  }
}
