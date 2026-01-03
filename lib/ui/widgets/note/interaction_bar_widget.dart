import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:carbon_icons/carbon_icons.dart';
import '../../theme/theme_manager.dart';
import '../../screens/note/share_note.dart';
import '../../../models/note_model.dart';
import '../../../core/di/app_di.dart';
import '../../../data/repositories/note_repository.dart';
import '../../../data/services/event_verifier.dart';
import '../dialogs/zap_dialog.dart';
import 'package:provider/provider.dart';
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
  final GlobalKey _moreButtonKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _noteRepository = AppDI.get<NoteRepository>();
    _stateNotifier = ValueNotifier(_computeInitialState());
    _setupStreamListener();
    _fetchCountsIfNeeded();
  }

  void _fetchCountsIfNeeded() {
  }

  @override
  void didUpdateWidget(InteractionBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.noteId != widget.noteId || oldWidget.note != widget.note) {
      _updateState();
      _fetchCountsIfNeeded();
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
      return _InteractionState(
        reactionCount: 0,
        repostCount: 0,
        replyCount: 0,
        zapAmount: 0,
        hasReacted: _noteRepository.hasUserReacted(widget.noteId, widget.currentUserNpub),
        hasReposted: _noteRepository.hasUserReposted(widget.noteId, widget.currentUserNpub),
        hasZapped: _noteRepository.hasUserZapped(widget.noteId, widget.currentUserNpub),
      );
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
    ShareNotePage.show(
      context,
      replyToNoteId: widget.noteId,
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
    final hasReposted = _stateNotifier.value.hasReposted;

    final items = <PopupMenuItem<String>>[];

    if (hasReposted) {
      items.add(
        PopupMenuItem(
          value: 'undo_repost',
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
          enabled: widget.note != null,
        ),
      );
      items.add(
        PopupMenuItem(
          value: 'repost',
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
          enabled: widget.note != null,
        ),
      );
    } else {
      items.add(
        PopupMenuItem(
          value: 'repost',
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
          enabled: widget.note != null,
        ),
      );
    }

    items.add(
      PopupMenuItem(
        value: 'quote',
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Row(
            children: [
              Icon(Icons.format_quote, size: 17, color: context.colors.background),
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
        enabled: widget.note != null,
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
      final currentState = _stateNotifier.value;
      if (value == 'undo_repost') {
        if (widget.note == null) return;
        _performDeleteRepost(currentState);
      } else if (value == 'repost') {
        if (widget.note == null) return;
        final noteToRepost = _findNote() ?? widget.note!;
        if (hasReposted) {
          _performDeleteRepost(currentState).then((_) {
            if (mounted) {
              final updatedState = _stateNotifier.value;
              _performRepost(noteToRepost, updatedState);
            }
          });
        } else {
          _performRepost(noteToRepost, currentState);
        }
      } else if (value == 'quote') {
        _handleQuoteTap();
      }
    });
  }

  Future<void> _performDeleteRepost(_InteractionState currentState) async {
    try {
      final result = await _noteRepository.deleteRepost(widget.noteId);
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
              hasReposted: false,
              hasZapped: currentState.hasZapped,
            );
          }
        },
        (error) {
          if (mounted) {
            AppSnackbar.error(context, 'Failed to undo repost: $error');
          }
        },
      );
    } catch (e) {
      if (mounted) {
        AppSnackbar.error(context, 'Failed to undo repost');
      }
    }
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

    ShareNotePage.show(
      context,
      initialText: quoteText,
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
    final themeManager = Provider.of<ThemeManager>(context, listen: false);

    if (themeManager.oneTapZap) {
      _stateNotifier.value = _InteractionState(
        reactionCount: currentState.reactionCount,
        repostCount: currentState.repostCount,
        replyCount: currentState.replyCount,
        zapAmount: currentState.zapAmount,
        hasReacted: currentState.hasReacted,
        hasReposted: currentState.hasReposted,
        hasZapped: true,
      );

      await processZapDirectly(
        context,
        noteToZap,
        themeManager.defaultZapAmount,
      );

      if (!mounted) return;

      final updatedState = _computeInitialState();
      _stateNotifier.value = _InteractionState(
        reactionCount: updatedState.reactionCount,
        repostCount: updatedState.repostCount,
        replyCount: updatedState.replyCount,
        zapAmount: updatedState.zapAmount,
        hasReacted: updatedState.hasReacted,
        hasReposted: updatedState.hasReposted,
        hasZapped: updatedState.hasZapped,
      );
    } else {
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
  }

  void _handleZapLongPress() async {
    HapticFeedback.mediumImpact();
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
    
    final currentLocation = GoRouterState.of(context).matchedLocation;
    if (currentLocation.startsWith('/home/feed')) {
      context.push('/home/feed/note-statistics', extra: noteForStats);
    } else if (currentLocation.startsWith('/home/notifications')) {
      context.push('/home/notifications/note-statistics', extra: noteForStats);
    } else if (currentLocation.startsWith('/home/dm')) {
      context.push('/home/dm/note-statistics', extra: noteForStats);
    } else {
      context.push('/note-statistics', extra: noteForStats);
    }
  }

  Future<void> _handleVerifyTap() async {
    HapticFeedback.lightImpact();
    if (widget.note == null || !mounted) return;

    final note = _findNote() ?? widget.note!;
    if (note.rawWs == null || note.rawWs!.isEmpty) {
      if (mounted) {
        AppSnackbar.error(context, 'Event data not available for verification');
      }
      return;
    }

    try {
      final verifier = EventVerifier.instance;
      final isValid = await verifier.verifyNote(note);

      if (!mounted) return;

      if (isValid) {
        AppSnackbar.success(context, 'Event signature verified successfully');
      } else {
        AppSnackbar.error(context, 'Event signature verification failed');
      }
    } catch (e) {
      if (mounted) {
        AppSnackbar.error(context, 'Failed to verify event: $e');
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
                onLongPress: _handleZapLongPress,
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

  void _showMoreMenu() {
    final RenderBox? renderBox = _moreButtonKey.currentContext?.findRenderObject() as RenderBox?;
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
              Icon(CarbonIcons.checkmark_filled, size: 17, color: context.colors.background),
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
              Icon(CarbonIcons.chart_bar, size: 17, color: context.colors.background),
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

    if (widget.note?.author == widget.currentUserNpub) {
      items.add(
        PopupMenuItem(
          value: 'delete',
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Row(
              children: [
                Icon(CarbonIcons.delete, size: 17, color: context.colors.background),
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

  Widget _buildPopupMenu(dynamic colors) {
    return InkWell(
      key: _moreButtonKey,
      onTap: _showMoreMenu,
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
                    offset: const Offset(0, -3.2),
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
