import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:bounce/bounce.dart';
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

  Widget _buildAction({
    required BuildContext context,
    required String svg,
    required Color color,
    required int count,
    required VoidCallback onTap,
  }) {
    final textScaleFactor = MediaQuery.of(context).textScaleFactor;
    final colors = context.colors;

    final double iconSize = isLarge ? 16 : 14;
    final double fontSize = isLarge ? 15 : 14;
    final double spacing = isLarge ? 6 : 5;

    return Stack(
      alignment: Alignment.center,
      children: [
        const Positioned(
          top: -10,
          child: SizedBox(
            width: 40,
            height: 40,
          ),
        ),
        Bounce(
          scaleFactor: 0.95,
          onTap: onTap,
          child: Row(
            children: [
              SvgPicture.asset(
                svg,
                width: iconSize * textScaleFactor,
                height: iconSize * textScaleFactor,
                colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
              ),
              SizedBox(width: spacing),
              Opacity(
                opacity: count > 0 ? 1.0 : 0.0,
                child: Text(
                  '$count',
                  style: TextStyle(fontSize: fontSize, color: colors.secondary),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildReactionButton(BuildContext context) {
    final textScaleFactor = MediaQuery.of(context).textScaleFactor;
    final colors = context.colors;
    final double iconSize = isLarge ? 16 : 14;
    final double fontSize = isLarge ? 15 : 14;
    final double spacing = isLarge ? 6 : 5;

    return Row(
      children: [
        LikeButton(
          size: iconSize * textScaleFactor,
          isLiked: hasReacted,
          likeCount: reactionCount,
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
          countBuilder: (int? count, bool isLiked, String text) {
            return Padding(
              padding: EdgeInsets.only(left: spacing),
              child: Opacity(
                opacity: (count ?? 0) > 0 ? 1.0 : 0.0,
                child: Text(
                  text,
                  style: TextStyle(fontSize: fontSize, color: colors.secondary),
                ),
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
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final double statsIconSize = isLarge ? 22 : 19;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _buildReactionButton(context),
        _buildAction(
          context: context,
          svg: 'assets/reply_button.svg',
          color: isReplyGlowing || hasReplied ? colors.reply : colors.secondary,
          count: replyCount,
          onTap: onReplyTap,
        ),
        _buildAction(
          context: context,
          svg: 'assets/repost_button.svg',
          color: isRepostGlowing || hasReposted ? colors.repost : colors.secondary,
          count: repostCount,
          onTap: onRepostTap,
        ),
        _buildAction(
          context: context,
          svg: 'assets/zap_button.svg',
          color: isZapGlowing || hasZapped ? colors.zap : colors.secondary,
          count: zapAmount,
          onTap: onZapTap,
        ),
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
