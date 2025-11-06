import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:carbon_icons/carbon_icons.dart';
import '../theme/theme_manager.dart';
import '../screens/share_note.dart';
import '../screens/note_statistics_page.dart';
import '../models/note_model.dart';
import '../core/di/app_di.dart';
import '../data/repositories/note_repository.dart';
import 'dialogs/zap_dialog.dart';
import 'dialogs/repost_dialog.dart';
import 'snackbar_widget.dart';

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
  Timer? _debounceTimer;

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
    _debounceTimer?.cancel();
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
    if (widget.note?.id == widget.noteId) {
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

      _debounceTimer?.cancel();
      _debounceTimer = Timer(const Duration(milliseconds: 150), () {
        if (mounted) _updateState();
      });
    });
  }

  void _updateState() {
    if (!mounted) return;
    
    final newState = _computeInitialState();
    if (_stateNotifier.value != newState) {
      _stateNotifier.value = newState;
    }
  }

  void _handleReplyTap() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ShareNotePage(replyToNoteId: widget.noteId),
      ),
    );
  }

  void _handleRepostTap() {
    final currentState = _stateNotifier.value;
    if (currentState.hasReposted || widget.note == null) return;

    showRepostDialog(
      context: context,
      note: widget.note!,
      onRepostSuccess: () {
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
    );
  }

  Future<void> _handleReactionTap() async {
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
    final currentState = _stateNotifier.value;
    if (widget.note == null || currentState.hasZapped || !mounted) return;

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
      note: widget.note!,
    );

    if (!mounted) return;

    final zapSuccess = zapResult['success'] as bool;
    if (!zapSuccess) {
      _stateNotifier.value = currentState;
    }
  }

  void _handleStatsTap() {
    if (widget.note == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => NoteStatisticsPage(note: widget.note!),
      ),
    );
  }

  void _handleDeleteTap() {
    if (widget.note == null || !mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.colors.background,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      builder: (modalContext) => Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          bottom: MediaQuery.of(modalContext).viewInsets.bottom + 40,
          top: 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Delete this post?',
              style: TextStyle(
                color: context.colors.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => Navigator.pop(modalContext),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        color: context.colors.buttonPrimary,
                        borderRadius: BorderRadius.circular(40),
                      ),
                      child: Text(
                        'Cancel',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: context.colors.buttonText,
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      Navigator.pop(modalContext);
                      _confirmDelete();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        color: context.colors.error.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(40),
                      ),
                      child: Text(
                        'Yes',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: context.colors.error,
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
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
    return ValueListenableBuilder<_InteractionState>(
      valueListenable: _stateNotifier,
      builder: (context, state, _) {
        final colors = context.colors;
        final height = widget.isBigSize ? 36.0 : 32.0;

        return RepaintBoundary(
          child: SizedBox(
            height: height,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _InteractionButton(
                  iconPath: 'assets/reply_button_2.svg',
                  count: state.replyCount,
                  isActive: false,
                  activeColor: colors.reply,
                  inactiveColor: colors.secondary,
                  onTap: _handleReplyTap,
                  isBigSize: widget.isBigSize,
                ),
                _InteractionButton(
                  carbonIcon: CarbonIcons.renew,
                  count: state.repostCount,
                  isActive: state.hasReposted,
                  activeColor: colors.repost,
                  inactiveColor: colors.secondary,
                  onTap: _handleRepostTap,
                  isBigSize: widget.isBigSize,
                  buttonType: _ButtonType.repost,
                ),
                _InteractionButton(
                  iconPath: 'assets/reaction_button.svg',
                  count: state.reactionCount,
                  isActive: state.hasReacted,
                  activeColor: colors.reaction,
                  inactiveColor: colors.secondary,
                  onTap: _handleReactionTap,
                  activeCarbonIcon: CarbonIcons.favorite_filled,
                  isBigSize: widget.isBigSize,
                  buttonType: _ButtonType.reaction,
                ),
                _InteractionButton(
                  iconPath: 'assets/zap_button.svg',
                  count: state.zapAmount,
                  isActive: state.hasZapped,
                  activeColor: colors.zap,
                  inactiveColor: colors.secondary,
                  onTap: _handleZapTap,
                  activeCarbonIcon: CarbonIcons.flash_filled,
                  isBigSize: widget.isBigSize,
                  buttonType: _ButtonType.zap,
                ),
                _buildPopupMenu(colors),
              ],
            ),
          ),
        );
      },
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

    return InkWell(
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
