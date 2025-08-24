import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:like_button/like_button.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
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
  final _secureStorage = const FlutterSecureStorage();
  String? _actualLoggedInUserNpub;

  @override
  void initState() {
    super.initState();
    _loadActualUserNpub();
  }

  Future<void> _loadActualUserNpub() async {
    try {
      final npub = await _secureStorage.read(key: 'npub');
      if (mounted) {
        setState(() {
          _actualLoggedInUserNpub = npub;
        });
      }
    } catch (e) {
      debugPrint('[InteractionBar] Error loading user npub: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_actualLoggedInUserNpub == null) {
      return const SizedBox.shrink();
    }

    final colors = context.colors;
    final double statsIconSize = widget.isLarge ? 22 : 21;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _InteractionButton(
          noteId: widget.noteId,
          currentUserNpub: _actualLoggedInUserNpub!,
          iconPath: 'assets/reply_button.svg',
          color: colors.reply,
          isGlowing: widget.isReplyGlowing,
          isLarge: widget.isLarge,
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
          currentUserNpub: _actualLoggedInUserNpub!,
          iconPath: 'assets/repost_button.svg',
          color: colors.repost,
          isGlowing: widget.isRepostGlowing,
          isLarge: widget.isLarge,
          onTap: () {
            if (widget.dataService == null || widget.note == null) return;
            final hasReposted = InteractionsProvider.instance.hasUserReposted(_actualLoggedInUserNpub!, widget.noteId);
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
          currentUserNpub: _actualLoggedInUserNpub!,
          iconPath: 'assets/reaction_button.svg',
          color: colors.reaction,
          isGlowing: widget.isReactionGlowing,
          isLarge: widget.isLarge,
          isLikeButton: true,
          onLikeTap: (isCurrentlyLiked) async {
            if (widget.dataService == null) return false;
            if (isCurrentlyLiked) {
              return false;
            }
            await widget.dataService!.sendReactionInstantly(widget.noteId, '+').catchError((e) {
              debugPrint('Error sending reaction: $e');
            });
            return true;
          },
          getInteractionCount: (provider) => provider.getReactionCount(widget.noteId),
          hasUserInteracted: (provider, npub, id) => provider.hasUserReacted(npub, id),
        ),
        _InteractionButton(
          noteId: widget.noteId,
          currentUserNpub: _actualLoggedInUserNpub!,
          iconPath: 'assets/zap_button.svg',
          color: colors.zap,
          isGlowing: widget.isZapGlowing,
          isLarge: widget.isLarge,
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
        GestureDetector(
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
      ],
    );
  }
}

class _InteractionButton extends StatelessWidget {
  final String noteId;
  final String currentUserNpub;
  final String iconPath;
  final Color color;
  final bool isGlowing;
  final bool isLarge;
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
    this.isLarge = false,
    this.isLikeButton = false,
    this.onTap,
    this.onLikeTap,
    required this.getInteractionCount,
    required this.hasUserInteracted,
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

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: InteractionsProvider.instance,
      builder: (context, child) {
        final provider = InteractionsProvider.instance;
        final count = getInteractionCount(provider);
        final hasInteracted = hasUserInteracted(provider, currentUserNpub, noteId);

        final textScaleFactor = MediaQuery.of(context).textScaleFactor;
        final colors = context.colors;
        final double iconSize = isLarge ? 16.5 : 15.5;
        final double fontSize = isLarge ? 15.5 : 15;
        final double spacing = isLarge ? 7 : 6.5;

        return Row(
          children: [
            if (isLikeButton)
              LikeButton(
                size: iconSize * textScaleFactor,
                isLiked: hasInteracted,
                animationDuration: const Duration(milliseconds: 1000),
                likeBuilder: (bool isLiked) {
                  return SvgPicture.asset(
                    iconPath,
                    width: iconSize * textScaleFactor,
                    height: iconSize * textScaleFactor,
                    colorFilter: ColorFilter.mode(
                      (isGlowing || isLiked) ? color : colors.secondary,
                      BlendMode.srcIn,
                    ),
                  );
                },
                onTap: onLikeTap,
                circleColor: CircleColor(
                  start: color.withOpacity(0.3),
                  end: color,
                ),
                bubblesColor: BubblesColor(
                  dotPrimaryColor: color,
                  dotSecondaryColor: color.withOpacity(0.7),
                ),
              )
            else
              GestureDetector(
                onTap: onTap,
                child: LikeButton(
                  size: iconSize * textScaleFactor,
                  isLiked: hasInteracted,
                  animationDuration: const Duration(milliseconds: 1000),
                  likeBuilder: (bool isLiked) {
                    return SvgPicture.asset(
                      iconPath,
                      width: iconSize * textScaleFactor,
                      height: iconSize * textScaleFactor,
                      colorFilter: ColorFilter.mode(
                        (isGlowing || isLiked) ? color : colors.secondary,
                        BlendMode.srcIn,
                      ),
                    );
                  },
                  onTap: (isLiked) async {
                    onTap?.call();
                    return false;
                  },
                  circleColor: CircleColor(
                    start: color.withOpacity(0.3),
                    end: color,
                  ),
                  bubblesColor: BubblesColor(
                    dotPrimaryColor: color,
                    dotSecondaryColor: color.withOpacity(0.7),
                  ),
                ),
              ),
            SizedBox(width: spacing),
            Opacity(
              opacity: count > 0 ? 1.0 : 0.0,
              child: Text(
                _formatCount(count),
                style: TextStyle(fontSize: fontSize, color: colors.secondary),
              ),
            ),
          ],
        );
      },
    );
  }
}
