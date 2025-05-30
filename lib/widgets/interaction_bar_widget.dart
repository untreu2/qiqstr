import 'package:flutter/material.dart';
import 'package:carbon_icons/carbon_icons.dart';
import 'package:like_button/like_button.dart';

class InteractionBar extends StatelessWidget {
  final int reactionCount;
  final int replyCount;
  final int repostCount;
  final int zapAmount;

  final bool isReplyGlowing;
  final bool isRepostGlowing;
  final bool isZapGlowing;

  final bool hasReacted;
  final bool hasReplied;
  final bool hasReposted;
  final bool hasZapped;

  final Future<bool> Function(bool) onReactionTap;
  final VoidCallback onReplyTap;
  final VoidCallback onRepostTap;
  final VoidCallback onZapTap;
  final VoidCallback onStatisticsTap;

  const InteractionBar({
    super.key,
    required this.reactionCount,
    required this.replyCount,
    required this.repostCount,
    required this.zapAmount,
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
  });

  Widget _buildAction({
    required Color color,
    required IconData iconData,
    required int count,
    required VoidCallback onTap,
  }) {
    return InkWell(
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      onTap: onTap,
      child: Row(
        children: [
          Icon(iconData, size: 18, color: color),
          const SizedBox(width: 4),
          Opacity(
            opacity: count > 0 ? 1.0 : 0.0,
            child: Text(
              '$count',
              style: const TextStyle(fontSize: 13, color: Colors.grey),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        LikeButton(
          isLiked: hasReacted,
          likeCount: reactionCount,
          onTap: onReactionTap,
          size: 22,
          circleColor: const CircleColor(
            start: Color(0xFFFF5722),
            end: Color(0xFFFFC107),
          ),
          bubblesColor: const BubblesColor(
            dotPrimaryColor: Color(0xFFFFC107),
            dotSecondaryColor: Color(0xFFFF5722),
          ),
          likeBuilder: (bool isLiked) {
            return Icon(
              isLiked ? CarbonIcons.favorite_filled : CarbonIcons.favorite,
              color: isLiked ? Colors.red.shade400 : Colors.grey,
              size: 18,
            );
          },
          countBuilder: (int? count, bool isLiked, String text) {
            return Opacity(
              opacity: count != null && count > 0 ? 1.0 : 0.0,
              child: Text(
                text,
                style: const TextStyle(fontSize: 13, color: Colors.grey),
              ),
            );
          },
        ),
        _buildAction(
          iconData: CarbonIcons.chat,
          color: isReplyGlowing || hasReplied ? Colors.blue.shade200 : Colors.grey,
          count: replyCount,
          onTap: onReplyTap,
        ),
        _buildAction(
          iconData: CarbonIcons.renew,
          color: isRepostGlowing || hasReposted ? Colors.green.shade400 : Colors.grey,
          count: repostCount,
          onTap: onRepostTap,
        ),
        _buildAction(
          iconData: hasZapped ? CarbonIcons.flash_filled : CarbonIcons.flash,
          color: isZapGlowing || hasZapped ? const Color(0xFFECB200) : Colors.grey,
          count: zapAmount,
          onTap: onZapTap,
        ),
        GestureDetector(
          onTap: onStatisticsTap,
          child: const Padding(
            padding: EdgeInsets.only(left: 6),
            child: Icon(Icons.bar_chart, size: 20, color: Colors.grey),
          ),
        ),
      ],
    );
  }
}
