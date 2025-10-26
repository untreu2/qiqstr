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
import 'toast_widget.dart';

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
  StreamSubscription? _notesStreamSubscription;

  bool _hasReacted = false;
  bool _hasReposted = false;
  bool _hasZapped = false;
  int _reactionCount = 0;
  int _repostCount = 0;
  int _replyCount = 0;
  int _zapAmount = 0;

  @override
  void initState() {
    super.initState();
    _noteRepository = AppDI.get<NoteRepository>();
    _hasReacted = false;
    _hasReposted = false;
    _hasZapped = false;
    _loadInteractionCounts();
    _subscribeToNoteUpdates();
  }

  @override
  void didUpdateWidget(InteractionBar oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.note?.id != widget.note?.id) {
      setState(() {
        _hasReacted = false;
        _hasReposted = false;
        _hasZapped = false;
      });

      _loadInteractionCounts();
    }

    if (oldWidget.note?.id != widget.note?.id ||
        oldWidget.note?.reactionCount != widget.note?.reactionCount ||
        oldWidget.note?.repostCount != widget.note?.repostCount ||
        oldWidget.note?.replyCount != widget.note?.replyCount ||
        oldWidget.note?.zapAmount != widget.note?.zapAmount) {
      _loadInteractionCounts();
    }
  }

  @override
  void dispose() {
    _notesStreamSubscription?.cancel();
    super.dispose();
  }

  void _subscribeToNoteUpdates() {
    _notesStreamSubscription = _noteRepository.notesStream.listen((notes) {
      if (!mounted) return;

      final updatedNote = notes.where((note) => note.id == widget.noteId).firstOrNull;
      if (updatedNote != null) {
        final newReactionCount = updatedNote.reactionCount;
        final newRepostCount = updatedNote.repostCount;
        final newReplyCount = updatedNote.replyCount;
        final newZapAmount = updatedNote.zapAmount;

        final userHasReacted = _noteRepository.hasUserReacted(widget.noteId, widget.currentUserNpub);
        final userHasReposted = _noteRepository.hasUserReposted(widget.noteId, widget.currentUserNpub);
        final userHasZapped = _noteRepository.hasUserZapped(widget.noteId, widget.currentUserNpub);

        bool shouldUpdate = false;
        int finalReactionCount = _reactionCount;
        int finalRepostCount = _repostCount;
        int finalReplyCount = _replyCount;
        int finalZapAmount = _zapAmount;
        bool finalHasReacted = _hasReacted;
        bool finalHasReposted = _hasReposted;
        bool finalHasZapped = _hasZapped;

        if (newReactionCount != _reactionCount && newReactionCount >= _reactionCount) {
          finalReactionCount = newReactionCount;
          shouldUpdate = true;
        }
        if (newRepostCount != _repostCount && newRepostCount >= _repostCount) {
          finalRepostCount = newRepostCount;
          shouldUpdate = true;
        }
        if (newReplyCount != _replyCount && newReplyCount >= _replyCount) {
          finalReplyCount = newReplyCount;
          shouldUpdate = true;
        }
        if (newZapAmount != _zapAmount && newZapAmount >= _zapAmount) {
          finalZapAmount = newZapAmount;
          shouldUpdate = true;
        }

        if (userHasReacted != _hasReacted) {
          finalHasReacted = userHasReacted;
          shouldUpdate = true;
        }
        if (userHasReposted != _hasReposted) {
          finalHasReposted = userHasReposted;
          shouldUpdate = true;
        }
        if (userHasZapped != _hasZapped) {
          finalHasZapped = userHasZapped;
          shouldUpdate = true;
        }

        if (shouldUpdate) {
          setState(() {
            _reactionCount = finalReactionCount;
            _repostCount = finalRepostCount;
            _replyCount = finalReplyCount;
            _zapAmount = finalZapAmount;
            _hasReacted = finalHasReacted;
            _hasReposted = finalHasReposted;
            _hasZapped = finalHasZapped;
          });
        } else {
          debugPrint('[InteractionBar] No stream updates for ${widget.noteId}');
          debugPrint('  Current: reactions=$_reactionCount, reposts=$_repostCount, replies=$_replyCount, zaps=$_zapAmount');
          debugPrint('  Stream:  reactions=$newReactionCount, reposts=$newRepostCount, replies=$newReplyCount, zaps=$newZapAmount');
        }
      }
    });
  }

  void _loadInteractionCounts() async {
    if (widget.note != null) {
      final newReactionCount = widget.note!.reactionCount;
      final newRepostCount = widget.note!.repostCount;
      final newReplyCount = widget.note!.replyCount;
      final newZapAmount = widget.note!.zapAmount;

      final userHasReacted = _noteRepository.hasUserReacted(widget.noteId, widget.currentUserNpub);
      final userHasReposted = _noteRepository.hasUserReposted(widget.noteId, widget.currentUserNpub);
      final userHasZapped = _noteRepository.hasUserZapped(widget.noteId, widget.currentUserNpub);

      bool shouldUpdate = false;
      int finalReactionCount = _reactionCount;
      int finalRepostCount = _repostCount;
      int finalReplyCount = _replyCount;
      int finalZapAmount = _zapAmount;
      bool finalHasReacted = _hasReacted;
      bool finalHasReposted = _hasReposted;
      bool finalHasZapped = _hasZapped;

      if (newReactionCount != _reactionCount && (newReactionCount > _reactionCount || _reactionCount == 0)) {
        finalReactionCount = newReactionCount;
        shouldUpdate = true;
      }
      if (newRepostCount != _repostCount && (newRepostCount > _repostCount || _repostCount == 0)) {
        finalRepostCount = newRepostCount;
        shouldUpdate = true;
      }
      if (newReplyCount != _replyCount && (newReplyCount > _replyCount || _replyCount == 0)) {
        finalReplyCount = newReplyCount;
        shouldUpdate = true;
      }
      if (newZapAmount != _zapAmount && (newZapAmount > _zapAmount || _zapAmount == 0)) {
        finalZapAmount = newZapAmount;
        shouldUpdate = true;
      }

      if (userHasReacted != _hasReacted) {
        finalHasReacted = userHasReacted;
        shouldUpdate = true;
      }
      if (userHasReposted != _hasReposted) {
        finalHasReposted = userHasReposted;
        shouldUpdate = true;
      }
      if (userHasZapped != _hasZapped) {
        finalHasZapped = userHasZapped;
        shouldUpdate = true;
      }

      if (_reactionCount == 0 && _repostCount == 0 && _replyCount == 0 && _zapAmount == 0) {
        finalReactionCount = newReactionCount;
        finalRepostCount = newRepostCount;
        finalReplyCount = newReplyCount;
        finalZapAmount = newZapAmount;
        finalHasReacted = userHasReacted;
        finalHasReposted = userHasReposted;
        finalHasZapped = userHasZapped;
        shouldUpdate = true;
      }

      if (shouldUpdate) {
        setState(() {
          _reactionCount = finalReactionCount;
          _repostCount = finalRepostCount;
          _replyCount = finalReplyCount;
          _zapAmount = finalZapAmount;
          _hasReacted = finalHasReacted;
          _hasReposted = finalHasReposted;
          _hasZapped = finalHasZapped;
        });
      } else {
        debugPrint('[InteractionBar] No count changes for ${widget.noteId}');
        debugPrint('  Current: reactions=$_reactionCount, reposts=$_repostCount, replies=$_replyCount, zaps=$_zapAmount');
        debugPrint('  Widget:  reactions=$newReactionCount, reposts=$newRepostCount, replies=$newReplyCount, zaps=$newZapAmount');
      }
    } else {
      if (_reactionCount == 0 && _repostCount == 0 && _replyCount == 0 && _zapAmount == 0) {
        setState(() {
          _reactionCount = 0;
          _repostCount = 0;
          _replyCount = 0;
          _zapAmount = 0;
          _hasReacted = false;
          _hasReposted = false;
          _hasZapped = false;
        });

        debugPrint('[InteractionBar] No note provided, using default counts');
      } else {
        debugPrint('[InteractionBar]  No note provided but keeping existing counts to prevent disappearing');
      }
    }
  }

  void _handleReplyTap() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ShareNotePage(
          replyToNoteId: widget.noteId,
        ),
      ),
    );
  }

  void _handleRepostTap() {
    if (_hasReposted || widget.note == null) return;

    showRepostDialog(
      context: context,
      note: widget.note!,
      onRepostSuccess: () {
        if (mounted) {
          setState(() {
            _hasReposted = true;
            _repostCount++;
          });
        }
      },
    );
  }

  Future<void> _handleReactionTap() async {
    if (_hasReacted) return;

    try {
      setState(() {
        _hasReacted = true;
        _reactionCount++;
      });

      final result = await _noteRepository.reactToNote(widget.noteId, '+');
      result.fold(
        (success) => debugPrint('Reaction successful'),
        (error) {
          setState(() {
            _hasReacted = false;
            _reactionCount--;
          });
          AppToast.error(context, 'Failed to react: $error');
        },
      );
    } catch (e) {
      setState(() {
        _hasReacted = false;
        _reactionCount--;
      });
    }
  }

  void _handleZapTap() async {
    if (widget.note == null || _hasZapped) return;

    debugPrint('[InteractionBar] Starting zap for note: ${widget.noteId}');

    final zapResult = await showZapDialog(
      context: context,
      note: widget.note!,
    );

    final zapSuccess = zapResult['success'] as bool;
    final zapAmount = zapResult['amount'] as int;

    debugPrint('[InteractionBar] Zap result: ${zapSuccess ? 'SUCCESS' : 'FAILED'}, amount: $zapAmount');

    if (mounted && zapSuccess) {
      setState(() {
        _hasZapped = true;
        _zapAmount += zapAmount;
      });
      debugPrint('[InteractionBar] Updated UI - hasZapped: $_hasZapped, zapAmount: $_zapAmount');
    }
  }

  void _handleStatsTap() {
    if (widget.note == null) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => NoteStatisticsPage(
          note: widget.note!,
        ),
      ),
    );
  }

  Widget _buildButton({
    required String? iconPath,
    required int count,
    required bool isActive,
    required Color activeColor,
    required Color inactiveColor,
    required VoidCallback onTap,
    bool isStatsButton = false,
    IconData? carbonIcon,
  }) {
    final effectiveColor = isActive ? activeColor : inactiveColor;
    final iconSize = widget.isBigSize ? 17.0 : 15.5;
    final statsIconSize = widget.isBigSize ? 23.0 : 21.0;
    final fontSize = widget.isBigSize ? 16.0 : 15.0;
    final spacing = widget.isBigSize ? 7.0 : 6.5;

    return GestureDetector(
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (isStatsButton)
            Icon(Icons.bar_chart, size: statsIconSize, color: effectiveColor)
          else if (carbonIcon != null)
            Icon(carbonIcon, size: carbonIcon == CarbonIcons.renew ? iconSize + 2.0 : iconSize, color: effectiveColor)
          else if (iconPath != null)
            SvgPicture.asset(
              iconPath,
              width: iconSize,
              height: iconSize,
              colorFilter: ColorFilter.mode(effectiveColor, BlendMode.srcIn),
            ),
          if (count > 0 && !isStatsButton) ...[
            SizedBox(width: spacing),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: Text(
                _formatCount(count),
                key: ValueKey('count_$count'),
                style: TextStyle(
                  fontSize: fontSize,
                  color: isActive ? activeColor : inactiveColor,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _formatCount(int count) {
    if (count >= 1000) {
      final formatted = (count / 1000).toStringAsFixed(1);
      return formatted.endsWith('.0') ? '${formatted.substring(0, formatted.length - 2)}K' : '${formatted}K';
    }
    return count.toString();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final height = widget.isBigSize ? 36.0 : 32.0;

    return SizedBox(
      height: height,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _buildButton(
            iconPath: 'assets/reply_button_2.svg',
            count: _replyCount,
            isActive: false,
            activeColor: colors.reply,
            inactiveColor: colors.secondary,
            onTap: _handleReplyTap,
          ),
          _buildButton(
            iconPath: null,
            carbonIcon: CarbonIcons.renew,
            count: _repostCount,
            isActive: _hasReposted,
            activeColor: colors.repost,
            inactiveColor: colors.secondary,
            onTap: _handleRepostTap,
          ),
          _buildButton(
            iconPath: 'assets/reaction_button.svg',
            count: _reactionCount,
            isActive: _hasReacted,
            activeColor: colors.reaction,
            inactiveColor: colors.secondary,
            onTap: _handleReactionTap,
          ),
          _buildButton(
            iconPath: 'assets/zap_button.svg',
            count: _zapAmount,
            isActive: _hasZapped,
            activeColor: colors.zap,
            inactiveColor: colors.secondary,
            onTap: _handleZapTap,
          ),
          _buildButton(
            iconPath: null,
            count: 0,
            isActive: false,
            activeColor: colors.secondary,
            inactiveColor: colors.secondary,
            onTap: _handleStatsTap,
            isStatsButton: true,
          ),
        ],
      ),
    );
  }
}
