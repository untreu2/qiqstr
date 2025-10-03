import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../theme/theme_manager.dart';
import '../screens/share_note.dart';
import '../screens/note_statistics_page.dart';
import '../models/note_model.dart';
import '../core/di/app_di.dart';
import '../data/repositories/note_repository.dart';
import 'dialogs/zap_dialog.dart';

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

  // Local state for optimistic updates
  bool _hasReacted = false;
  bool _hasReposted = false;
  bool _hasZapped = false; // Optimistic zap state for button color only
  int _reactionCount = 0;
  int _repostCount = 0;
  int _replyCount = 0;
  int _zapAmount = 0;

  @override
  void initState() {
    super.initState();
    _noteRepository = AppDI.get<NoteRepository>();
    _loadInteractionCounts();
    _subscribeToNoteUpdates();
  }

  @override
  void didUpdateWidget(InteractionBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Reload counts if note changed
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
    // Listen to real-time note updates to refresh interaction counts automatically
    _notesStreamSubscription = _noteRepository.notesStream.listen((notes) {
      if (!mounted) return;

      // Find our note in the updated list
      final updatedNote = notes.where((note) => note.id == widget.noteId).firstOrNull;
      if (updatedNote != null) {
        final newReactionCount = updatedNote.reactionCount;
        final newRepostCount = updatedNote.repostCount;
        final newReplyCount = updatedNote.replyCount;
        final newZapAmount = updatedNote.zapAmount;

        // ENHANCED LOGIC: Accept stream updates more intelligently
        // This allows proper synchronization from thread view calculations
        bool shouldUpdate = false;
        int finalReactionCount = _reactionCount;
        int finalRepostCount = _repostCount;
        int finalReplyCount = _replyCount;
        int finalZapAmount = _zapAmount;

        // Accept updates if counts have genuinely changed and are meaningful
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

        if (shouldUpdate) {
          setState(() {
            _reactionCount = finalReactionCount;
            _repostCount = finalRepostCount;
            _replyCount = finalReplyCount;
            _zapAmount = finalZapAmount;
          });

          debugPrint(
              '[InteractionBar] Updated counts from stream for ${widget.noteId}: reactions=$_reactionCount, reposts=$_repostCount, replies=$_replyCount, zaps=$_zapAmount');
        } else {
          debugPrint('[InteractionBar] No stream updates for ${widget.noteId}');
          debugPrint('  Current: reactions=$_reactionCount, reposts=$_repostCount, replies=$_replyCount, zaps=$_zapAmount');
          debugPrint('  Stream:  reactions=$newReactionCount, reposts=$newRepostCount, replies=$newReplyCount, zaps=$newZapAmount');
        }
      }
    });
  }

  void _loadInteractionCounts() async {
    // Load actual interaction counts from note parameter with enhanced real-time updates
    if (widget.note != null) {
      final newReactionCount = widget.note!.reactionCount;
      final newRepostCount = widget.note!.repostCount;
      final newReplyCount = widget.note!.replyCount;
      final newZapAmount = widget.note!.zapAmount;

      // ENHANCED LOGIC: Always trust the note's counts if they come from repository updates
      // This ensures calculated thread counts are properly synchronized to the feed
      bool shouldUpdate = false;
      int finalReactionCount = _reactionCount;
      int finalRepostCount = _repostCount;
      int finalReplyCount = _replyCount;
      int finalZapAmount = _zapAmount;

      // Accept updates if:
      // 1. New counts are higher (normal case)
      // 2. Current counts are zero (initial load)
      // 3. Note has been updated recently (repository sync from thread view)
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

      // SPECIAL CASE: If this is a fresh widget mount, always use note's counts
      if (_reactionCount == 0 && _repostCount == 0 && _replyCount == 0 && _zapAmount == 0) {
        finalReactionCount = newReactionCount;
        finalRepostCount = newRepostCount;
        finalReplyCount = newReplyCount;
        finalZapAmount = newZapAmount;
        shouldUpdate = true;
        debugPrint('[InteractionBar] 🆕 Fresh mount - using note counts for ${widget.noteId}');
      }

      if (shouldUpdate) {
        setState(() {
          _reactionCount = finalReactionCount;
          _repostCount = finalRepostCount;
          _replyCount = finalReplyCount;
          _zapAmount = finalZapAmount;
          _hasReacted = false;
          _hasReposted = false;
          _hasZapped = false;
        });

        debugPrint(
            '[InteractionBar] Updated counts for ${widget.noteId}: reactions=$_reactionCount, reposts=$_repostCount, replies=$_replyCount, zaps=$_zapAmount');
      } else {
        debugPrint('[InteractionBar] No count changes for ${widget.noteId}');
        debugPrint('  Current: reactions=$_reactionCount, reposts=$_repostCount, replies=$_replyCount, zaps=$_zapAmount');
        debugPrint('  Widget:  reactions=$newReactionCount, reposts=$newRepostCount, replies=$newReplyCount, zaps=$newZapAmount');
      }
    } else {
      // Only set to zero if current counts are also zero (initial state)
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

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Share Note'),
        content: const Text('How would you like to share this note?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await _performRepost();
            },
            child: const Text('Repost'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _openQuoteDialog();
            },
            child: const Text('Quote'),
          ),
        ],
      ),
    );
  }

  void _openQuoteDialog() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ShareNotePage(
          initialText: 'nostr:${widget.noteId}', // This will trigger quote mode in ShareNotePage
        ),
      ),
    );
  }

  Future<void> _performRepost() async {
    try {
      setState(() {
        _hasReposted = true;
        _repostCount++;
      });

      final result = await _noteRepository.repostNote(widget.noteId);
      result.fold(
        (success) => debugPrint('Repost successful'),
        (error) {
          // Revert optimistic update on error
          setState(() {
            _hasReposted = false;
            _repostCount--;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to repost: $error')),
          );
        },
      );
    } catch (e) {
      setState(() {
        _hasReposted = false;
        _repostCount--;
      });
    }
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
          // Revert optimistic update on error
          setState(() {
            _hasReacted = false;
            _reactionCount--;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to react: $error')),
          );
        },
      );
    } catch (e) {
      setState(() {
        _hasReacted = false;
        _reactionCount--;
      });
    }
  }

  void _handleZapTap() {
    if (widget.note == null || _hasZapped) return;

    // Optimistic update for button color only
    setState(() {
      _hasZapped = true;
    });

    showZapDialog(
      context: context,
      note: widget.note!,
    ).then((_) {
      // Reset optimistic state after dialog closes
      // Real zap amount updates will come from stream
      if (mounted) {
        setState(() {
          _hasZapped = false;
        });
      }
    });
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
        children: [
          if (isStatsButton)
            Icon(Icons.bar_chart, size: statsIconSize, color: effectiveColor)
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

    return SizedBox(
      height: widget.isBigSize ? 36 : 32,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _buildButton(
            iconPath: 'assets/reply_button.svg',
            count: _replyCount,
            isActive: false,
            activeColor: colors.reply,
            inactiveColor: colors.secondary,
            onTap: _handleReplyTap,
          ),
          _buildButton(
            iconPath: 'assets/repost_button.svg',
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
            isActive: _hasZapped, // Optimistic color change
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
