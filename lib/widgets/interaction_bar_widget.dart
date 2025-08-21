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
  final bool isLarge;

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
    this.isLarge = false,
  });

  @override
  State<InteractionBar> createState() => _InteractionBarState();
}

class _InteractionBarState extends State<InteractionBar> {
  final GlobalKey<LikeButtonState> _reactionButtonKey = GlobalKey<LikeButtonState>();
  final GlobalKey<LikeButtonState> _replyButtonKey = GlobalKey<LikeButtonState>();
  final GlobalKey<LikeButtonState> _repostButtonKey = GlobalKey<LikeButtonState>();
  final GlobalKey<LikeButtonState> _zapButtonKey = GlobalKey<LikeButtonState>();

  String _formatCount(int count) {
    if (count >= 1000) {
      final String formatted = (count / 1000).toStringAsFixed(1);
      if (formatted.endsWith('.0')) {
        return '${formatted.substring(0, formatted.length - 2)}K';
      }
      return '${formatted}K';
    }
    return count.toString();
  }

  /// Handles the reaction tap.
  /// The responsibility for optimistic updates is now entirely within DataService
  /// to ensure the UI update logic happens only once.
  Future<bool> _handleReactionTap(bool isCurrentlyLiked) async {
    if (widget.dataService == null) {
      return false;
    }

    // Currently, this function does not handle "unliking".
    if (isCurrentlyLiked) {
      return false;
    }

    try {
      // 1. Directly call the service. DataService will handle the optimistic update and the network request.
      await widget.dataService!.sendReactionInstantly(widget.noteId, '+');

      // 2. Return true to the LikeButton to let it complete its animation.
      return true;
    } catch (e) {
      print('Error sending reaction: $e');

      // 3. If the network request fails, DataService is responsible for its own state consistency.
      // The UI does not need to perform a manual rollback.
      return false;
    }
  }

  void _handleReplyTap() {
    if (widget.dataService == null) return;

    // Navigate to the reply page
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ShareNotePage(
          dataService: widget.dataService!,
          replyToNoteId: widget.noteId,
        ),
      ),
    );
  }

  void _handleRepostTap() {
    if (widget.dataService == null || widget.note == null) return;

    final hasReposted = InteractionsProvider.instance.hasUserReposted(widget.currentUserNpub, widget.noteId);
    if (hasReposted) return;

    showRepostDialog(
      context: context,
      dataService: widget.dataService!,
      note: widget.note!,
    );
  }

  void _handleZapTap() {
    if (widget.dataService == null || widget.note == null) return;

    showZapDialog(
      context: context,
      dataService: widget.dataService!,
      note: widget.note!,
    );
  }

  void _handleStatisticsTap() {
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
  }

  Widget _buildReactionButton(BuildContext context, int reactionCount, bool hasReacted) {
    final textScaleFactor = MediaQuery.of(context).textScaleFactor;
    final colors = context.colors;
    final double iconSize = widget.isLarge ? 16.5 : 15.5;
    final double fontSize = widget.isLarge ? 15.5 : 15;
    final double spacing = widget.isLarge ? 7 : 6.5;

    return Row(
      children: [
        LikeButton(
          key: _reactionButtonKey,
          size: iconSize * textScaleFactor,
          isLiked: hasReacted,
          animationDuration: const Duration(milliseconds: 1000),
          likeBuilder: (bool isLiked) {
            return SvgPicture.asset(
              'assets/reaction_button.svg',
              width: iconSize * textScaleFactor,
              height: iconSize * textScaleFactor,
              colorFilter: ColorFilter.mode(
                (widget.isReactionGlowing || isLiked) ? colors.reaction : colors.secondary,
                BlendMode.srcIn,
              ),
            );
          },
          onTap: (bool isLiked) async {
            return await _handleReactionTap(isLiked);
          },
          circleColor: CircleColor(
            start: colors.reaction.withOpacity(0.3),
            end: colors.reaction,
          ),
          bubblesColor: BubblesColor(
            dotPrimaryColor: colors.reaction,
            dotSecondaryColor: colors.reaction.withOpacity(0.7),
          ),
        ),
        SizedBox(width: spacing),
        Opacity(
          opacity: reactionCount > 0 ? 1.0 : 0.0,
          child: Text(
            _formatCount(reactionCount),
            style: TextStyle(fontSize: fontSize, color: colors.secondary),
          ),
        ),
      ],
    );
  }

  Widget _buildReplyButton(BuildContext context, int replyCount, bool hasReplied) {
    final textScaleFactor = MediaQuery.of(context).textScaleFactor;
    final colors = context.colors;
    final double iconSize = widget.isLarge ? 16 : 15;
    final double fontSize = widget.isLarge ? 15 : 14.5;
    final double spacing = widget.isLarge ? 6 : 5.5;

    return Row(
      children: [
        LikeButton(
          key: _replyButtonKey,
          size: iconSize * textScaleFactor,
          isLiked: hasReplied,
          animationDuration: const Duration(milliseconds: 1000),
          likeBuilder: (bool isLiked) {
            return SvgPicture.asset(
              'assets/reply_button.svg',
              width: iconSize * textScaleFactor,
              height: iconSize * textScaleFactor,
              colorFilter: ColorFilter.mode(
                (widget.isReplyGlowing || isLiked) ? colors.reply : colors.secondary,
                BlendMode.srcIn,
              ),
            );
          },
          onTap: (bool isLiked) async {
            _handleReplyTap();
            return false; // Reply action does not toggle the button's state.
          },
          circleColor: CircleColor(
            start: colors.reply.withOpacity(0.3),
            end: colors.reply,
          ),
          bubblesColor: BubblesColor(
            dotPrimaryColor: colors.reply,
            dotSecondaryColor: colors.reply.withOpacity(0.7),
          ),
        ),
        SizedBox(width: spacing),
        Opacity(
          opacity: replyCount > 0 ? 1.0 : 0.0,
          child: Text(
            _formatCount(replyCount),
            style: TextStyle(fontSize: fontSize, color: colors.secondary),
          ),
        ),
      ],
    );
  }

  Widget _buildRepostButton(BuildContext context, int repostCount, bool hasReposted) {
    final textScaleFactor = MediaQuery.of(context).textScaleFactor;
    final colors = context.colors;
    final double iconSize = widget.isLarge ? 16 : 15;
    final double fontSize = widget.isLarge ? 15 : 14.5;
    final double spacing = widget.isLarge ? 6 : 5.5;

    return Row(
      children: [
        LikeButton(
          key: _repostButtonKey,
          size: iconSize * textScaleFactor,
          isLiked: hasReposted,
          animationDuration: const Duration(milliseconds: 1000),
          likeBuilder: (bool isLiked) {
            return SvgPicture.asset(
              'assets/repost_button.svg',
              width: iconSize * textScaleFactor,
              height: iconSize * textScaleFactor,
              colorFilter: ColorFilter.mode(
                (widget.isRepostGlowing || isLiked) ? colors.repost : colors.secondary,
                BlendMode.srcIn,
              ),
            );
          },
          onTap: (bool isLiked) async {
            if (!isLiked) {
              _handleRepostTap();
            }
            return !isLiked;
          },
          circleColor: CircleColor(
            start: colors.repost.withOpacity(0.3),
            end: colors.repost,
          ),
          bubblesColor: BubblesColor(
            dotPrimaryColor: colors.repost,
            dotSecondaryColor: colors.repost.withOpacity(0.7),
          ),
        ),
        SizedBox(width: spacing),
        Opacity(
          opacity: repostCount > 0 ? 1.0 : 0.0,
          child: Text(
            _formatCount(repostCount),
            style: TextStyle(fontSize: fontSize, color: colors.secondary),
          ),
        ),
      ],
    );
  }

  Widget _buildZapButton(BuildContext context, int zapAmount, bool hasZapped) {
    final textScaleFactor = MediaQuery.of(context).textScaleFactor;
    final colors = context.colors;
    final double iconSize = widget.isLarge ? 16 : 15;
    final double fontSize = widget.isLarge ? 15 : 14.5;
    final double spacing = widget.isLarge ? 6 : 5.5;

    return Row(
      children: [
        LikeButton(
          key: _zapButtonKey,
          size: iconSize * textScaleFactor,
          isLiked: hasZapped,
          animationDuration: const Duration(milliseconds: 1000),
          likeBuilder: (bool isLiked) {
            return SvgPicture.asset(
              'assets/zap_button.svg',
              width: iconSize * textScaleFactor,
              height: iconSize * textScaleFactor,
              colorFilter: ColorFilter.mode(
                (widget.isZapGlowing || isLiked) ? colors.zap : colors.secondary,
                BlendMode.srcIn,
              ),
            );
          },
          onTap: (bool isLiked) async {
            _handleZapTap();
            return !isLiked;
          },
          circleColor: CircleColor(
            start: colors.zap.withOpacity(0.3),
            end: colors.zap,
          ),
          bubblesColor: BubblesColor(
            dotPrimaryColor: colors.zap,
            dotSecondaryColor: colors.zap.withOpacity(0.7),
          ),
        ),
        SizedBox(width: spacing),
        Opacity(
          opacity: zapAmount > 0 ? 1.0 : 0.0,
          child: Text(
            _formatCount(zapAmount),
            style: TextStyle(fontSize: fontSize, color: colors.secondary),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: InteractionsProvider.instance,
      builder: (context, _) {
        final colors = context.colors;
        final double statsIconSize = widget.isLarge ? 22 : 21;

        // Get real-time data from InteractionsProvider
        final reactionCount = InteractionsProvider.instance.getReactionCount(widget.noteId);
        final replyCount = InteractionsProvider.instance.getReplyCount(widget.noteId);
        final repostCount = InteractionsProvider.instance.getRepostCount(widget.noteId);
        final zapAmount = InteractionsProvider.instance.getZapAmount(widget.noteId);

        final hasReacted = InteractionsProvider.instance.hasUserReacted(widget.currentUserNpub, widget.noteId);
        final hasReplied = InteractionsProvider.instance.hasUserReplied(widget.currentUserNpub, widget.noteId);
        final hasReposted = InteractionsProvider.instance.hasUserReposted(widget.currentUserNpub, widget.noteId);
        final hasZapped = InteractionsProvider.instance.hasUserZapped(widget.currentUserNpub, widget.noteId);

        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _buildReplyButton(context, replyCount, hasReplied),
            _buildRepostButton(context, repostCount, hasReposted),
            _buildReactionButton(context, reactionCount, hasReacted),
            _buildZapButton(context, zapAmount, hasZapped),
            GestureDetector(
              onTap: _handleStatisticsTap,
              child: Padding(
                padding: const EdgeInsets.only(left: 6),
                child: Icon(Icons.bar_chart, size: statsIconSize, color: colors.secondary),
              ),
            ),
          ],
        );
      },
    );
  }
}
