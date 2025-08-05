import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:like_button/like_button.dart';
import '../theme/theme_manager.dart';

class InteractionBar extends StatelessWidget {
  final int reactionCount;
  final int replyCount;
  final int repostCount;
  final int zapAmount;

  final bool isReactionGlowing;
  final bool isReplyGlowing;
  final bool isRepostGlowing;
  final bool isZapGlowing;

  final bool hasReacted;
  final bool hasReplied;
  final bool hasReposted;
  final bool hasZapped;

  final VoidCallback onReactionTap;
  final VoidCallback onReplyTap;
  final VoidCallback onRepostTap;
  final VoidCallback onZapTap;
  final VoidCallback onStatisticsTap;
  final bool isLarge;

  const InteractionBar({
    super.key,
    required this.reactionCount,
    required this.replyCount,
    required this.repostCount,
    required this.zapAmount,
    required this.isReactionGlowing,
    required this.isReplyGlowing,
    required this.isRepostGlowing,
    required this.isZapGlowing,
    required this.hasReacted,
    required this.hasReplied,
    required this.hasReposted,
    required this.hasZapped,
    required this.onReactionTap,
    required this.onReplyTap,
    required this.onRepostTap,
    required this.onZapTap,
    required this.onStatisticsTap,
    this.isLarge = false,
  });

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

  Widget _buildReactionButton(BuildContext context) {
    final textScaleFactor = MediaQuery.of(context).textScaleFactor;
    final colors = context.colors;
    final double iconSize = isLarge ? 16 : 15;
    final double fontSize = isLarge ? 15 : 14.5;
    final double spacing = isLarge ? 6 : 5.5;

    return Row(
      children: [
        LikeButton(
          size: iconSize * textScaleFactor,
          isLiked: hasReacted,
          animationDuration: const Duration(milliseconds: 1000),
          likeBuilder: (bool isLiked) {
            return SvgPicture.asset(
              'assets/reaction_button.svg',
              width: iconSize * textScaleFactor,
              height: iconSize * textScaleFactor,
              colorFilter: ColorFilter.mode(
                (isReactionGlowing || isLiked) ? colors.reaction : colors.secondary,
                BlendMode.srcIn,
              ),
            );
          },
          onTap: (bool isLiked) async {
            onReactionTap();
            return !isLiked;
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

  Widget _buildReplyButton(BuildContext context) {
    final textScaleFactor = MediaQuery.of(context).textScaleFactor;
    final colors = context.colors;
    final double iconSize = isLarge ? 16 : 15;
    final double fontSize = isLarge ? 15 : 14.5;
    final double spacing = isLarge ? 6 : 5.5;

    return Row(
      children: [
        LikeButton(
          size: iconSize * textScaleFactor,
          isLiked: hasReplied,
          animationDuration: const Duration(milliseconds: 1000),
          likeBuilder: (bool isLiked) {
            return SvgPicture.asset(
              'assets/reply_button.svg',
              width: iconSize * textScaleFactor,
              height: iconSize * textScaleFactor,
              colorFilter: ColorFilter.mode(
                (isReplyGlowing || isLiked) ? colors.reply : colors.secondary,
                BlendMode.srcIn,
              ),
            );
          },
          onTap: (bool isLiked) async {
            onReplyTap();
            return !isLiked;
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

  Widget _buildRepostButton(BuildContext context) {
    final textScaleFactor = MediaQuery.of(context).textScaleFactor;
    final colors = context.colors;
    final double iconSize = isLarge ? 16 : 15;
    final double fontSize = isLarge ? 15 : 14.5;
    final double spacing = isLarge ? 6 : 5.5;

    return Row(
      children: [
        LikeButton(
          size: iconSize * textScaleFactor,
          isLiked: hasReposted,
          animationDuration: const Duration(milliseconds: 1000),
          likeBuilder: (bool isLiked) {
            return SvgPicture.asset(
              'assets/repost_button.svg',
              width: iconSize * textScaleFactor,
              height: iconSize * textScaleFactor,
              colorFilter: ColorFilter.mode(
                (isRepostGlowing || isLiked) ? colors.repost : colors.secondary,
                BlendMode.srcIn,
              ),
            );
          },
          onTap: (bool isLiked) async {
            onRepostTap();
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

  Widget _buildZapButton(BuildContext context) {
    final textScaleFactor = MediaQuery.of(context).textScaleFactor;
    final colors = context.colors;
    final double iconSize = isLarge ? 16 : 15;
    final double fontSize = isLarge ? 15 : 14.5;
    final double spacing = isLarge ? 6 : 5.5;

    return Row(
      children: [
        LikeButton(
          size: iconSize * textScaleFactor,
          isLiked: hasZapped,
          animationDuration: const Duration(milliseconds: 1000),
          likeBuilder: (bool isLiked) {
            return SvgPicture.asset(
              'assets/zap_button.svg',
              width: iconSize * textScaleFactor,
              height: iconSize * textScaleFactor,
              colorFilter: ColorFilter.mode(
                (isZapGlowing || isLiked) ? colors.zap : colors.secondary,
                BlendMode.srcIn,
              ),
            );
          },
          onTap: (bool isLiked) async {
            onZapTap();
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
    final colors = context.colors;
    final double statsIconSize = isLarge ? 22 : 21;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _buildReactionButton(context),
        _buildReplyButton(context),
        _buildRepostButton(context),
        _buildZapButton(context),
        GestureDetector(
          onTap: onStatisticsTap,
          child: Padding(
            padding: const EdgeInsets.only(left: 6),
            child: Icon(Icons.bar_chart, size: statsIconSize, color: colors.secondary),
          ),
        ),
      ],
    );
  }
}