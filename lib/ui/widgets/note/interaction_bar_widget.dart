import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:carbon_icons/carbon_icons.dart';
import '../../theme/theme_manager.dart';
import '../../screens/note/share_note.dart';
import '../../screens/note/note_statistics_page.dart';
import '../../../models/note_model.dart';
import '../../../core/di/app_di.dart';
import '../../../data/repositories/note_repository.dart';
import '../dialogs/zap_dialog.dart';
import 'package:nostr_nip19/nostr_nip19.dart';
import '../dialogs/delete_note_dialog.dart';
import '../common/snackbar_widget.dart';

class _InteractionState {
  final int reactionCount;
  final int repostCount;
  final int replyCount;
  final int zapAmount;
  final bool hasReacted;
  final bool hasReposted;
  final bool hasZapped;

  const _InteractionState({
    this.reactionCount = 0,
    this.repostCount = 0,
    this.replyCount = 0,
    this.zapAmount = 0,
    this.hasReacted = false,
    this.hasReposted = false,
    this.hasZapped = false,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _InteractionState &&
          reactionCount == other.reactionCount &&
          repostCount == other.repostCount &&
          replyCount == other.replyCount &&
          zapAmount == other.zapAmount &&
          hasReacted == other.hasReacted &&
          hasReposted == other.hasReposted &&
          hasZapped == other.hasZapped;

  @override
  int get hashCode => Object.hash(
        reactionCount,
        repostCount,
        replyCount,
        zapAmount,
        hasReacted,
        hasReposted,
        hasZapped,
      );
}

class InteractionBar extends StatefulWidget {
  final String noteId;
  final String currentUserNpub;
  final NoteModel? note;
  final bool isBigSize;

  const InteractionBar({
    super.key,
    required this.noteId,
    required this.currentUserNpub,
    this.note,
    this.isBigSize = false,
  });

  @override
  State<InteractionBar> createState() => _InteractionBarState();
}

class _InteractionBarState extends State<InteractionBar> {
  late final NoteRepository _noteRepository;
  late final ValueNotifier<_InteractionState> _stateNotifier;
  StreamSubscription<List<NoteModel>>? _streamSubscription;
  DateTime? _lastUpdateTime;
  final GlobalKey _repostButtonKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _noteRepository = AppDI.get<NoteRepository>();
    _stateNotifier = ValueNotifier(_computeInitialState());
    _setupStreamListener();
  }

  @override
  void didUpdateWidget(InteractionBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.noteId != widget.noteId || oldWidget.note != widget.note) {
      _updateState();
    }
  }

  @override
  void dispose() {
    _streamSubscription?.cancel();
    _stateNotifier.dispose();
    super.dispose();
  }

  _InteractionState _computeInitialState() {
    final note = _findNote();
    if (note == null) {
      return const _InteractionState();
    }

    return _InteractionState(
      reactionCount: note.reactionCount,
      repostCount: note.repostCount,
      replyCount: note.replyCount,
      zapAmount: note.zapAmount,
      hasReacted: _noteRepository.hasUserReacted(widget.noteId, widget.currentUserNpub),
      hasReposted: _noteRepository.hasUserReposted(widget.noteId, widget.currentUserNpub),
      hasZapped: _noteRepository.hasUserZapped(widget.noteId, widget.currentUserNpub),
    );
  }

  NoteModel? _findNote() {
    if (widget.note == null) {
      final allNotes = _noteRepository.currentNotes;
      for (final n in allNotes) {
        if (n.id == widget.noteId) {
          return n;
        }
      }
      return null;
    }
    
    if (widget.note!.id == widget.noteId) {
      return widget.note;
    }
    
    if (widget.note!.isRepost && widget.note!.rootId == widget.noteId) {
      final allNotes = _noteRepository.currentNotes;
      for (final n in allNotes) {
        if (n.id == widget.noteId) {
          return n;
        }
      }
      return widget.note;
    }
    
    final allNotes = _noteRepository.currentNotes;
    for (final n in allNotes) {
      if (n.id == widget.noteId) {
        return n;
      }
    }
    
    return widget.note;
  }

  void _setupStreamListener() {
    _streamSubscription = _noteRepository.notesStream.listen((notes) {
      if (!mounted) return;

      final hasRelevantUpdate = notes.any((note) => note.id == widget.noteId);
      if (!hasRelevantUpdate) return;

      final updateTime = DateTime.now();
      if (_lastUpdateTime != null && 
          updateTime.difference(_lastUpdateTime!).inMilliseconds < 1000) {
        return;
      }
      
      _lastUpdateTime = updateTime;
      
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted && _lastUpdateTime == updateTime) {
          _updateState();
        }
      });
    });
  }

  void _updateState() {
    if (!mounted) return;
    
    final currentState = _stateNotifier.value;
    final newState = _computeInitialState();
    
    final safeNewState = _InteractionState(
      reactionCount: newState.reactionCount >= currentState.reactionCount 
          ? newState.reactionCount 
          : currentState.reactionCount,
      repostCount: newState.repostCount >= currentState.repostCount 
          ? newState.repostCount 
          : currentState.repostCount,
      replyCount: newState.replyCount >= currentState.replyCount 
          ? newState.replyCount 
          : currentState.replyCount,
      zapAmount: newState.zapAmount >= currentState.zapAmount 
          ? newState.zapAmount 
          : currentState.zapAmount,
      hasReacted: newState.hasReacted || currentState.hasReacted,
      hasReposted: newState.hasReposted || currentState.hasReposted,
      hasZapped: newState.hasZapped || currentState.hasZapped,
    );
    
    if (currentState != safeNewState) {
      _stateNotifier.value = safeNewState;
    }
  }

  void _handleReplyTap() {
    HapticFeedback.lightImpact();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ShareNotePage(replyToNoteId: widget.noteId),
      ),
    );
  }

  void _handleRepostTap() {
    HapticFeedback.lightImpact();
    _showRepostMenu();
  }

  void _showRepostMenu() {
    final RenderBox? renderBox = _repostButtonKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final offset = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;

    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(
        offset.dx,
        offset.dy + size.height,
        offset.dx + size.width,
        offset.dy + size.height + 200,
      ),
      color: context.colors.buttonPrimary,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(40)),
      items: [
        PopupMenuItem(
          value: 'repost',
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Row(
              children: [
                Icon(Icons.repeat, size: 18, color: context.colors.buttonText),
                const SizedBox(width: 12),
                Text(
                  'Repost',
                  style: TextStyle(
                    color: context.colors.buttonText,
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          enabled: !_stateNotifier.value.hasReposted && widget.note != null,
        ),
        PopupMenuItem(
          value: 'quote',
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Row(
              children: [
                Icon(Icons.format_quote, size: 18, color: context.colors.buttonText),
                const SizedBox(width: 12),
                Text(
                  'Quote',
                  style: TextStyle(
                    color: context.colors.buttonText,
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          enabled: widget.note != null,
        ),
      ],
    ).then((value) {
      if (value == null) return;
      HapticFeedback.lightImpact();
      final currentState = _stateNotifier.value;
      if (value == 'repost') {
        if (currentState.hasReposted || widget.note == null) return;
        final noteToRepost = _findNote() ?? widget.note!;
        _performRepost(noteToRepost, currentState);
      } else if (value == 'quote') {
        _handleQuoteTap();
      }
    });
  }

  Future<void> _performRepost(NoteModel note, _InteractionState currentState) async {
    try {
      final result = await _noteRepository.repostNote(note.id);
      if (!mounted) return;

      result.fold(
        (_) {
        if (mounted) {
          _stateNotifier.value = _InteractionState(
            reactionCount: currentState.reactionCount,
            repostCount: currentState.repostCount,
            replyCount: currentState.replyCount,
            zapAmount: currentState.zapAmount,
            hasReacted: currentState.hasReacted,
            hasReposted: true,
            hasZapped: currentState.hasZapped,
          );
        }
      },
        (error) {
          if (mounted) {
            AppSnackbar.error(context, 'Failed to repost: $error');
          }
        },
      );
    } catch (e) {
      if (mounted) {
        AppSnackbar.error(context, 'Failed to repost note');
      }
    }
  }

  void _handleQuoteTap() {
    if (widget.note == null) return;
    final noteToQuote = _findNote() ?? widget.note!;
    final bech32 = encodeBasicBech32(noteToQuote.id, 'note');
    final quoteText = 'nostr:$bech32';

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ShareNotePage(
          initialText: quoteText,
        ),
      ),
    );
  }

  Future<void> _handleReactionTap() async {
    HapticFeedback.lightImpact();
    final currentState = _stateNotifier.value;
    if (currentState.hasReacted || !mounted) return;

    _stateNotifier.value = _InteractionState(
      reactionCount: currentState.reactionCount,
      repostCount: currentState.repostCount,
      replyCount: currentState.replyCount,
      zapAmount: currentState.zapAmount,
      hasReacted: true,
      hasReposted: currentState.hasReposted,
      hasZapped: currentState.hasZapped,
    );

    try {
      final result = await _noteRepository.reactToNote(widget.noteId, '+');
      if (!mounted) return;

      result.fold(
        (_) {},
        (error) {
          if (mounted) {
            _stateNotifier.value = _InteractionState(
              reactionCount: currentState.reactionCount,
              repostCount: currentState.repostCount,
              replyCount: currentState.replyCount,
              zapAmount: currentState.zapAmount,
              hasReacted: false,
              hasReposted: currentState.hasReposted,
              hasZapped: currentState.hasZapped,
            );
            AppSnackbar.error(context, 'Failed to react: $error');
          }
        },
      );
    } catch (e) {
      if (mounted) {
        _stateNotifier.value = currentState;
      }
    }
  }

  void _handleZapTap() async {
    HapticFeedback.lightImpact();
    final currentState = _stateNotifier.value;
    if (widget.note == null || currentState.hasZapped || !mounted) return;

    final noteToZap = _findNote() ?? widget.note!;

    _stateNotifier.value = _InteractionState(
      reactionCount: currentState.reactionCount,
      repostCount: currentState.repostCount,
      replyCount: currentState.replyCount,
      zapAmount: currentState.zapAmount,
      hasReacted: currentState.hasReacted,
      hasReposted: currentState.hasReposted,
      hasZapped: true,
    );

    final zapResult = await showZapDialog(
      context: context,
      note: noteToZap,
    );

    if (!mounted) return;

    final zapSuccess = zapResult['success'] as bool;
    if (!zapSuccess) {
      _stateNotifier.value = currentState;
    }
  }

  void _handleStatsTap() {
    HapticFeedback.lightImpact();
    if (widget.note == null) return;
    
    final noteForStats = _findNote() ?? widget.note!;
    
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => NoteStatisticsPage(note: noteForStats),
      ),
    );
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

    try {
      final result = await _noteRepository.deleteNote(widget.noteId);
      if (!mounted) return;

      result.fold(
        (_) {},
        (error) {
          if (mounted) {
            AppSnackbar.error(context, 'Failed to delete note: $error');
          }
        },
      );
    } catch (e) {
      if (mounted) {
        AppSnackbar.error(context, 'Failed to delete note: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final height = widget.isBigSize ? 36.0 : 32.0;
    
    return RepaintBoundary(
      key: ValueKey('interaction_${widget.noteId}'),
      child: SizedBox(
        height: height,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _SelectiveButton(
              stateNotifier: _stateNotifier,
              selector: (state) => state.replyCount,
              builder: (count, isActive) => _InteractionButton(
                iconPath: 'assets/reply_button_2.svg',
                count: count,
                isActive: false,
                activeColor: colors.reply,
                inactiveColor: colors.secondary,
                onTap: _handleReplyTap,
                isBigSize: widget.isBigSize,
              ),
            ),
            _SelectiveButton(
              stateNotifier: _stateNotifier,
              selector: (state) => state.repostCount,
              activeSelector: (state) => state.hasReposted,
              builder: (count, isActive) => _InteractionButton(
                key: _repostButtonKey,
                carbonIcon: CarbonIcons.renew,
                count: count,
                isActive: isActive,
                activeColor: colors.repost,
                inactiveColor: colors.secondary,
                onTap: _handleRepostTap,
                isBigSize: widget.isBigSize,
                buttonType: _ButtonType.repost,
              ),
            ),
            _SelectiveButton(
              stateNotifier: _stateNotifier,
              selector: (state) => state.reactionCount,
              activeSelector: (state) => state.hasReacted,
              builder: (count, isActive) => _InteractionButton(
                iconPath: 'assets/reaction_button.svg',
                count: count,
                isActive: isActive,
                activeColor: colors.reaction,
                inactiveColor: colors.secondary,
                onTap: _handleReactionTap,
                activeCarbonIcon: CarbonIcons.favorite_filled,
                isBigSize: widget.isBigSize,
                buttonType: _ButtonType.reaction,
              ),
            ),
            _SelectiveButton(
              stateNotifier: _stateNotifier,
              selector: (state) => state.zapAmount,
              activeSelector: (state) => state.hasZapped,
              builder: (count, isActive) => _InteractionButton(
                iconPath: 'assets/zap_button.svg',
                count: count,
                isActive: isActive,
                activeColor: colors.zap,
                inactiveColor: colors.secondary,
                onTap: _handleZapTap,
                activeCarbonIcon: CarbonIcons.flash_filled,
                isBigSize: widget.isBigSize,
                buttonType: _ButtonType.zap,
              ),
            ),
            _buildPopupMenu(colors),
          ],
        ),
      ),
    );
  }

  Widget _buildPopupMenu(dynamic colors) {
    return PopupMenuButton<String>(
      icon: Transform.translate(
        offset: const Offset(-4, 0),
        child: Icon(
          Icons.more_horiz,
          size: widget.isBigSize ? 20.0 : 18.0,
          color: colors.secondary,
        ),
      ),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(40)),
      color: colors.buttonPrimary,
      elevation: 0,
      onSelected: (value) {
        HapticFeedback.lightImpact();
        if (value == 'interactions') {
          _handleStatsTap();
        } else if (value == 'delete') {
          _handleDeleteTap();
        }
      },
      itemBuilder: (context) {
        final items = <PopupMenuItem<String>>[
          PopupMenuItem(
            value: 'interactions',
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Row(
                children: [
                  Icon(CarbonIcons.chart_bar, size: 18, color: colors.buttonText),
                  const SizedBox(width: 12),
                  Text(
                    'Interactions',
                    style: TextStyle(
                      color: colors.buttonText,
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ];

        if (widget.note?.author == widget.currentUserNpub) {
          items.add(
            PopupMenuItem(
              value: 'delete',
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                child: Row(
                  children: [
                    Icon(CarbonIcons.delete, size: 18, color: colors.buttonText),
                    const SizedBox(width: 12),
                    Text(
                      'Delete',
                      style: TextStyle(
                        color: colors.buttonText,
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        return items;
      },
    );
  }
}

enum _ButtonType { reply, repost, reaction, zap }

class _SelectiveButton extends StatefulWidget {
  final ValueNotifier<_InteractionState> stateNotifier;
  final int Function(_InteractionState) selector;
  final bool Function(_InteractionState)? activeSelector;
  final Widget Function(int count, bool isActive) builder;

  const _SelectiveButton({
    required this.stateNotifier,
    required this.selector,
    this.activeSelector,
    required this.builder,
  });

  @override
  State<_SelectiveButton> createState() => _SelectiveButtonState();
}

class _SelectiveButtonState extends State<_SelectiveButton> {
  late int _lastCount;
  late bool _lastActive;

  @override
  void initState() {
    super.initState();
    _lastCount = widget.selector(widget.stateNotifier.value);
    _lastActive = widget.activeSelector?.call(widget.stateNotifier.value) ?? false;
    widget.stateNotifier.addListener(_onStateChanged);
  }

  @override
  void dispose() {
    widget.stateNotifier.removeListener(_onStateChanged);
    super.dispose();
  }

  void _onStateChanged() {
    final newCount = widget.selector(widget.stateNotifier.value);
    final newActive = widget.activeSelector?.call(widget.stateNotifier.value) ?? false;
    
    if (_lastCount != newCount || _lastActive != newActive) {
      if (mounted) {
        setState(() {
          _lastCount = newCount;
          _lastActive = newActive;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.builder(_lastCount, _lastActive);
  }
}

class _InteractionButton extends StatelessWidget {
  final String? iconPath;
  final IconData? carbonIcon;
  final IconData? activeCarbonIcon;
  final int count;
  final bool isActive;
  final Color activeColor;
  final Color inactiveColor;
  final VoidCallback onTap;
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
    required this.isBigSize,
    this.buttonType = _ButtonType.reply,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveColor = isActive ? activeColor : inactiveColor;
    final iconSize = isBigSize ? 17.0 : 15.5;
    final fontSize = isBigSize ? 16.0 : 15.0;
    final spacing = isBigSize ? 7.0 : 6.5;

    return RepaintBoundary(
      child: InkWell(
        onTap: onTap,
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
                  offset: const Offset(0, -3),
                  child: Text(
                    _formatCount(count),
                    style: TextStyle(
                      fontSize: fontSize,
                      color: effectiveColor,
                      fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                ),
              ],
            ],
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
