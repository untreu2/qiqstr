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
  StreamSubscription<List<NoteModel>>? _notesStreamSubscription;
  NoteModel? _actualNote;
  bool _hasReacted = false;
  bool _hasReposted = false;
  bool _hasZapped = false;

  @override
  void initState() {
    super.initState();
    _noteRepository = AppDI.get<NoteRepository>();
    _updateActualNote();
    _setupNotesStreamSubscription();
    _updateLocalState();
  }

  @override
  void didUpdateWidget(InteractionBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    final noteIdChanged = oldWidget.note?.id != widget.note?.id || 
                         oldWidget.noteId != widget.noteId;
    if (noteIdChanged) {
      _updateActualNote();
      _updateLocalState();
    } else if (oldWidget.note != widget.note) {
      _updateActualNote();
    }
  }

  @override
  void dispose() {
    _notesStreamSubscription?.cancel();
    super.dispose();
  }

  void _setupNotesStreamSubscription() {
    _notesStreamSubscription = _noteRepository.notesStream.listen((notes) {
      if (!mounted || notes.isEmpty) return;
      
      // widget.noteId is already the rootId for reposts (from NoteWidget._getInteractionNoteId)
      // Find the actual note by widget.noteId
      final targetNoteId = widget.noteId;
      NoteModel? foundNote;
      
      for (final note in notes) {
        if (note.id == targetNoteId) {
          foundNote = note;
          break;
        }
      }
      
      // Update actual note if found and counts changed
      if (foundNote != null) {
        final currentCounts = _actualNote != null 
            ? '${_actualNote!.reactionCount}_${_actualNote!.repostCount}_${_actualNote!.replyCount}_${_actualNote!.zapAmount}'
            : '';
        final newCounts = '${foundNote.reactionCount}_${foundNote.repostCount}_${foundNote.replyCount}_${foundNote.zapAmount}';
        
        if (_actualNote == null || currentCounts != newCounts) {
          setState(() {
            _actualNote = foundNote;
          });
        }
      }
    });
  }

  void _updateActualNote() {
    final note = widget.note;
    
    // widget.noteId is already the rootId for reposts (from NoteWidget._getInteractionNoteId)
    // So we should find the note by widget.noteId, not widget.note.id
    final targetNoteId = widget.noteId;
    
    // Try to find the actual note from repository by noteId (which is rootId for reposts)
    final allNotes = _noteRepository.currentNotes;
    for (final n in allNotes) {
      if (n.id == targetNoteId) {
        _actualNote = n;
        return;
      }
    }
    
    // If not found in repository, use widget.note as fallback
    // For reposts, this will be the wrapper note with 0 counts, but stream will update it
    if (note != null) {
      _actualNote = note;
    } else {
      _actualNote = null;
    }
  }

  void _updateLocalState() {
    final note = _actualNote ?? widget.note;
    if (note == null) {
      if (_hasReacted || _hasReposted || _hasZapped) {
        setState(() {
          _hasReacted = false;
          _hasReposted = false;
          _hasZapped = false;
        });
      }
      return;
    }

    final userHasReacted = _noteRepository.hasUserReacted(widget.noteId, widget.currentUserNpub);
    final userHasReposted = _noteRepository.hasUserReposted(widget.noteId, widget.currentUserNpub);
    final userHasZapped = _noteRepository.hasUserZapped(widget.noteId, widget.currentUserNpub);

    if (userHasReacted != _hasReacted || userHasReposted != _hasReposted || userHasZapped != _hasZapped) {
      setState(() {
        _hasReacted = userHasReacted;
        _hasReposted = userHasReposted;
        _hasZapped = userHasZapped;
      });
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
          });
        }
      },
    );
  }

  Future<void> _handleReactionTap() async {
    if (_hasReacted || !mounted) return;

    final prevHasReacted = _hasReacted;

    setState(() {
      _hasReacted = true;
    });

    try {
      final result = await _noteRepository.reactToNote(widget.noteId, '+');
      if (!mounted) return;
      
      result.fold(
        (_) {},
        (error) {
          if (mounted) {
            setState(() {
              _hasReacted = prevHasReacted;
            });
            AppSnackbar.error(context, 'Failed to react: $error');
          }
        },
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _hasReacted = prevHasReacted;
        });
      }
    }
  }

  void _handleZapTap() async {
    if (widget.note == null || _hasZapped || !mounted) return;

    final originalHasZapped = _hasZapped;

    setState(() {
      _hasZapped = true;
    });

    final zapResult = await showZapDialog(
      context: context,
      note: widget.note!,
    );

    if (!mounted) return;

    final zapSuccess = zapResult['success'] as bool;

    if (!zapSuccess) {
      setState(() {
        _hasZapped = originalHasZapped;
      });
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
    IconData? activeCarbonIcon,
    String buttonType = '',
  }) {
    final effectiveColor = isActive ? activeColor : inactiveColor;
    final iconSize = widget.isBigSize ? 17.0 : 15.5;
    final statsIconSize = widget.isBigSize ? 23.0 : 21.0;
    final fontSize = widget.isBigSize ? 16.0 : 15.0;
    final spacing = widget.isBigSize ? 7.0 : 6.5;

    Widget buildIcon() {
      if (isStatsButton) {
        return Icon(Icons.bar_chart, size: statsIconSize, color: effectiveColor);
      } else if (carbonIcon != null && buttonType == 'repost') {
        return Icon(carbonIcon, size: iconSize + 2.0, color: effectiveColor);
      } else if (activeCarbonIcon != null && buttonType != 'repost') {
        if (isActive) {
          return Icon(
            activeCarbonIcon,
            size: buttonType == 'reaction' 
                ? iconSize + 4.0 
                : buttonType == 'zap' 
                    ? iconSize + 3.0 
                    : iconSize + 1.0,
            color: activeColor,
          );
        } else {
          return SvgPicture.asset(
            iconPath!,
            width: iconSize,
            height: iconSize,
            colorFilter: ColorFilter.mode(inactiveColor, BlendMode.srcIn),
          );
        }
      } else if (iconPath != null) {
        return SvgPicture.asset(
          iconPath,
          width: iconSize,
          height: iconSize,
          colorFilter: ColorFilter.mode(effectiveColor, BlendMode.srcIn),
        );
      }
      return const SizedBox.shrink();
    }

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            buildIcon(),
            if (count > 0 && !isStatsButton) ...[
              SizedBox(width: spacing),
              Transform.translate(
                offset: const Offset(0, -3),
                child: Text(
                  _formatCount(count),
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
    final note = _actualNote ?? widget.note;
    if (note == null) {
      return const SizedBox(height: 32);
    }

    final colors = context.colors;
    final height = widget.isBigSize ? 36.0 : 32.0;
    // For reposts, use the actual note's counts (which should be fetched by rootId)
    final reactionCount = note.reactionCount;
    final repostCount = note.repostCount;
    final replyCount = note.replyCount;
    final zapAmount = note.zapAmount;

    return RepaintBoundary(
      child: SizedBox(
        height: height,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _buildButton(
              iconPath: 'assets/reply_button_2.svg',
              count: replyCount,
              isActive: false,
              activeColor: colors.reply,
              inactiveColor: colors.secondary,
              onTap: _handleReplyTap,
              buttonType: 'reply',
            ),
            _buildButton(
              iconPath: null,
              carbonIcon: CarbonIcons.renew,
              count: repostCount,
              isActive: _hasReposted,
              activeColor: colors.repost,
              inactiveColor: colors.secondary,
              onTap: _handleRepostTap,
              buttonType: 'repost',
            ),
            _buildButton(
              iconPath: 'assets/reaction_button.svg',
              count: reactionCount,
              isActive: _hasReacted,
              activeColor: colors.reaction,
              inactiveColor: colors.secondary,
              onTap: _handleReactionTap,
              activeCarbonIcon: CarbonIcons.favorite_filled,
              buttonType: 'reaction',
            ),
            _buildButton(
              iconPath: 'assets/zap_button.svg',
              count: zapAmount,
              isActive: _hasZapped,
              activeColor: colors.zap,
              inactiveColor: colors.secondary,
              onTap: _handleZapTap,
              activeCarbonIcon: CarbonIcons.flash_filled,
              buttonType: 'zap',
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
      ),
    );
  }
}
