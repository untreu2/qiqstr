import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:like_button/like_button.dart';
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

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (widget.currentUserNpub.isEmpty) {
      return const SizedBox.shrink();
    }

    final colors = context.colors;
    final double statsIconSize = 21;

    return SizedBox(
      height: 32,
      child: RepaintBoundary(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _InteractionButton(
              noteId: widget.noteId,
              currentUserNpub: widget.currentUserNpub,
              iconPath: 'assets/reply_button.svg',
              color: colors.reply,
              isGlowing: widget.isReplyGlowing,
              onTap: () {
                if (widget.dataService == null) return;
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ShareNotePage(
                      dataService: widget.dataService!,
                      replyToNoteId: widget.noteId,
                    ),
                  ),
                );
              },
              getInteractionCount: (provider) => provider.getReplyCount(widget.noteId),
              hasUserInteracted: (provider, npub, id) => provider.hasUserReplied(npub, id),
            ),
            _InteractionButton(
              noteId: widget.noteId,
              currentUserNpub: widget.currentUserNpub,
              iconPath: 'assets/repost_button.svg',
              color: colors.repost,
              isGlowing: widget.isRepostGlowing,
              onTap: () {
                if (widget.dataService == null || widget.note == null) return;
                final hasReposted = InteractionsProvider.instance.hasUserReposted(widget.currentUserNpub, widget.noteId);
                if (hasReposted) return;
                showRepostDialog(
                  context: context,
                  dataService: widget.dataService!,
                  note: widget.note!,
                );
              },
              getInteractionCount: (provider) => provider.getRepostCount(widget.noteId),
              hasUserInteracted: (provider, npub, id) => provider.hasUserReposted(npub, id),
            ),
            _InteractionButton(
              noteId: widget.noteId,
              currentUserNpub: widget.currentUserNpub,
              iconPath: 'assets/reaction_button.svg',
              color: colors.reaction,
              isGlowing: widget.isReactionGlowing,
              isLikeButton: true,
              onLikeTap: (isCurrentlyLiked) async {
                if (widget.dataService == null) return false;
                if (isCurrentlyLiked) {
                  return false;
                }
                await widget.dataService!.sendReaction(widget.noteId, '+').catchError((e) {
                  debugPrint('Error sending reaction: $e');
                });
                return true;
              },
              getInteractionCount: (provider) => provider.getReactionCount(widget.noteId),
              hasUserInteracted: (provider, npub, id) => provider.hasUserReacted(npub, id),
            ),
            _InteractionButton(
              noteId: widget.noteId,
              currentUserNpub: widget.currentUserNpub,
              iconPath: 'assets/zap_button.svg',
              color: colors.zap,
              isGlowing: widget.isZapGlowing,
              onTap: () {
                if (widget.dataService == null || widget.note == null) return;
                showZapDialog(
                  context: context,
                  dataService: widget.dataService!,
                  note: widget.note!,
                );
              },
              getInteractionCount: (provider) => provider.getZapAmount(widget.noteId),
              hasUserInteracted: (provider, npub, id) => provider.hasUserZapped(npub, id),
            ),
            RepaintBoundary(
              child: GestureDetector(
                onTap: () {
                  if (widget.dataService == null || widget.note == null) return;
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => NoteStatisticsPage(
                        note: widget.note!,
                        dataService: widget.dataService!,
                      ),
                    ),
                  );
                },
                child: Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Icon(Icons.bar_chart, size: statsIconSize, color: colors.secondary),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InteractionButton extends StatefulWidget {
  final String noteId;
  final String currentUserNpub;
  final String iconPath;
  final Color color;
  final bool isGlowing;
  final bool isLikeButton;
  final void Function()? onTap;
  final Future<bool> Function(bool)? onLikeTap;
  final int Function(InteractionsProvider provider) getInteractionCount;
  final bool Function(InteractionsProvider provider, String npub, String noteId) hasUserInteracted;

  const _InteractionButton({
    required this.noteId,
    required this.currentUserNpub,
    required this.iconPath,
    required this.color,
    this.isGlowing = false,
    this.isLikeButton = false,
    this.onTap,
    this.onLikeTap,
    required this.getInteractionCount,
    required this.hasUserInteracted,
  });

  @override
  State<_InteractionButton> createState() => _InteractionButtonState();
}

class _InteractionButtonState extends State<_InteractionButton> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  static final Map<String, String> _formatCache = <String, String>{};
  static final Map<String, TextStyle> _styleCache = <String, TextStyle>{};
  static final double _globalTextScale = WidgetsBinding.instance.platformDispatcher.textScaleFactor;

  late final double _iconSize;
  late final double _fontSize;
  late final double _spacing;
  late final double _effectiveSize;

  int _initialCount = 0;
  bool _initialHasInteracted = false;
  int _localInteractionDelta = 0;
  bool _userHasInteracted = false;

  @override
  void initState() {
    super.initState();
    _iconSize = 15.5;
    _fontSize = 15;
    _spacing = 6.5;
    _effectiveSize = _iconSize * _globalTextScale;

    _loadInitialState();
    InteractionsProvider.instance.addListener(_onProviderUpdate);
  }

  @override
  void dispose() {
    InteractionsProvider.instance.removeListener(_onProviderUpdate);
    super.dispose();
  }

  void _loadInitialState() {
    final provider = InteractionsProvider.instance;
    _initialCount = widget.getInteractionCount(provider);
    _initialHasInteracted = widget.hasUserInteracted(provider, widget.currentUserNpub, widget.noteId);
    _userHasInteracted = _initialHasInteracted;
  }

  void _onProviderUpdate() {
    if (!mounted) return;

    final provider = InteractionsProvider.instance;
    final newCount = widget.getInteractionCount(provider);
    final newHasInteracted = widget.hasUserInteracted(provider, widget.currentUserNpub, widget.noteId);

    final hasChanges = newCount != _initialCount || newHasInteracted != _initialHasInteracted;

    if (hasChanges || newCount > 0) {
      setState(() {
        _initialCount = newCount;
        _initialHasInteracted = newHasInteracted;
        _userHasInteracted = newHasInteracted;

        if (newCount > 0) {
          _localInteractionDelta = 0;
        }
      });
    }
  }

  void _handleUserInteraction() {
    if (mounted) {
      setState(() {
        if (!_userHasInteracted) {
          _userHasInteracted = true;
          _localInteractionDelta = 1;
        }
      });
    }
  }

  String _formatCount(int count) {
    return _formatCache.putIfAbsent(count.toString(), () {
      if (count >= 1000) {
        final formatted = (count / 1000).toStringAsFixed(1);
        return formatted.endsWith('.0') ? '${formatted.substring(0, formatted.length - 2)}K' : '${formatted}K';
      }
      return count.toString();
    });
  }

  TextStyle _getTextStyle(Color color) {
    final key = '$_fontSize-$color';
    return _styleCache.putIfAbsent(key, () => TextStyle(fontSize: _fontSize, color: color));
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final colors = context.colors;
    final displayCount = _initialCount + _localInteractionDelta;
    final isInteracted = _userHasInteracted;

    return RepaintBoundary(
      child: Row(
        children: [
          RepaintBoundary(
            child: LikeButton(
              size: _effectiveSize,
              isLiked: isInteracted,
              animationDuration: const Duration(milliseconds: 500),
              likeBuilder: (bool isLiked) => SvgPicture.asset(
                widget.iconPath,
                width: _effectiveSize,
                height: _effectiveSize,
                colorFilter: ColorFilter.mode(
                  (widget.isGlowing || isLiked) ? widget.color : colors.secondary,
                  BlendMode.srcIn,
                ),
              ),
              onTap: widget.isLikeButton
                  ? (isCurrentlyLiked) async {
                      if (widget.onLikeTap != null) {
                        final result = await widget.onLikeTap!(isCurrentlyLiked);
                        if (result) _handleUserInteraction();
                        return result;
                      }
                      return false;
                    }
                  : (isLiked) async {
                      widget.onTap?.call();
                      _handleUserInteraction();
                      return !isLiked;
                    },
              circleColor: CircleColor(
                start: widget.color.withOpacity(0.3),
                end: widget.color,
              ),
              bubblesColor: BubblesColor(
                dotPrimaryColor: widget.color,
                dotSecondaryColor: widget.color.withOpacity(0.7),
              ),
            ),
          ),
          SizedBox(width: _spacing),
          if (displayCount > 0)
            RepaintBoundary(
              child: Text(
                _formatCount(displayCount),
                style: _getTextStyle(colors.secondary),
              ),
            ),
        ],
      ),
    );
  }
}
