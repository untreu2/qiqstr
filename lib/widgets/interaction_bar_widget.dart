import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

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
  });

  Widget _buildAction({
    required String svg,
    required Color color,
    required int count,
    required VoidCallback onTap,
  }) {
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
        InkWell(
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
          onTap: onTap,
          child: Row(
            children: [
              SvgPicture.asset(svg, width: 15, height: 15, colorFilter: ColorFilter.mode(color, BlendMode.srcIn)),
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
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _buildAction(
          svg: 'assets/reaction_button.svg',
          color: isReactionGlowing || hasReacted
              ? Colors.red.shade400
              : Colors.grey,
          count: reactionCount,
          onTap: onReactionTap,
        ),
        _buildAction(
          svg: 'assets/reply_button.svg',
          color: isReplyGlowing || hasReplied
              ? Colors.blue.shade200
              : Colors.grey,
          count: replyCount,
          onTap: onReplyTap,
        ),
        _buildAction(
          svg: 'assets/repost_button.svg',
          color: isRepostGlowing || hasReposted
              ? Colors.green.shade400
              : Colors.grey,
          count: repostCount,
          onTap: onRepostTap,
        ),
        _buildAction(
          svg: 'assets/zap_button.svg',
          color: isZapGlowing || hasZapped
              ? const Color(0xFFECB200)
              : Colors.grey,
          count: zapAmount,
          onTap: onZapTap,
        ),
        GestureDetector(
          onTap: onStatisticsTap,
          child: const Padding(
            padding: EdgeInsets.only(left: 6),
            child: Icon(Icons.bar_chart, size: 18, color: Colors.grey),
          ),
        ),
      ],
    );
  }
}
