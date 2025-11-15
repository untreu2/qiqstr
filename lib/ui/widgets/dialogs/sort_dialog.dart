import 'package:flutter/material.dart';
import '../../theme/theme_manager.dart';
import '../../../presentation/viewmodels/feed_viewmodel.dart';

Future<void> showSortDialog({
  required BuildContext context,
  required FeedViewModel viewModel,
}) async {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.colors.background,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (modalContext) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: () {
              Navigator.pop(modalContext);
              viewModel.setHashtag(null);
              viewModel.setSortMode(FeedSortMode.latest);
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: viewModel.sortMode == FeedSortMode.latest && viewModel.hashtag == null
                    ? context.colors.accentBright
                    : context.colors.overlayLight,
                borderRadius: BorderRadius.circular(40),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.access_time,
                    color: viewModel.sortMode == FeedSortMode.latest && viewModel.hashtag == null
                        ? context.colors.background
                        : context.colors.textPrimary,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Latest',
                    style: TextStyle(
                      color: viewModel.sortMode == FeedSortMode.latest && viewModel.hashtag == null
                          ? context.colors.background
                          : context.colors.textPrimary,
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: () {
              Navigator.pop(modalContext);
              viewModel.setHashtag(null);
              viewModel.setSortMode(FeedSortMode.mostInteracted);
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: viewModel.sortMode == FeedSortMode.mostInteracted && viewModel.hashtag == null
                    ? context.colors.accentBright
                    : context.colors.overlayLight,
                borderRadius: BorderRadius.circular(40),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.trending_up,
                    color: viewModel.sortMode == FeedSortMode.mostInteracted && viewModel.hashtag == null
                        ? context.colors.background
                        : context.colors.textPrimary,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Popular',
                    style: TextStyle(
                      color: viewModel.sortMode == FeedSortMode.mostInteracted && viewModel.hashtag == null
                          ? context.colors.background
                          : context.colors.textPrimary,
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: () {
              Navigator.pop(modalContext);
              viewModel.setHashtag('bitcoin');
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: viewModel.hashtag == 'bitcoin'
                    ? context.colors.accentBright
                    : context.colors.overlayLight,
                borderRadius: BorderRadius.circular(40),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.tag,
                    color: viewModel.hashtag == 'bitcoin'
                        ? context.colors.background
                        : context.colors.textPrimary,
                    size: 20,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'bitcoin',
                    style: TextStyle(
                      color: viewModel.hashtag == 'bitcoin'
                          ? context.colors.background
                          : context.colors.textPrimary,
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: () {
              Navigator.pop(modalContext);
              viewModel.setHashtag('nostr');
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: viewModel.hashtag == 'nostr'
                    ? context.colors.accentBright
                    : context.colors.overlayLight,
                borderRadius: BorderRadius.circular(40),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.tag,
                    color: viewModel.hashtag == 'nostr'
                        ? context.colors.background
                        : context.colors.textPrimary,
                    size: 20,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'nostr',
                    style: TextStyle(
                      color: viewModel.hashtag == 'nostr'
                          ? context.colors.background
                          : context.colors.textPrimary,
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: () {
              Navigator.pop(modalContext);
              viewModel.setHashtag('foodstr');
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: viewModel.hashtag == 'foodstr'
                    ? context.colors.accentBright
                    : context.colors.overlayLight,
                borderRadius: BorderRadius.circular(40),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.tag,
                    color: viewModel.hashtag == 'foodstr'
                        ? context.colors.background
                        : context.colors.textPrimary,
                    size: 20,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'foodstr',
                    style: TextStyle(
                      color: viewModel.hashtag == 'foodstr'
                          ? context.colors.background
                          : context.colors.textPrimary,
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

