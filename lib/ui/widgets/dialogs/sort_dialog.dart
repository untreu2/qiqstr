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
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: context.colors.buttonPrimary,
                borderRadius: BorderRadius.circular(40),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.access_time,
                        color: context.colors.buttonText,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Latest',
                        style: TextStyle(
                          color: context.colors.buttonText,
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  if (viewModel.sortMode == FeedSortMode.latest && viewModel.hashtag == null)
                    Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: context.colors.accent,
                        border: Border.all(
                          color: context.colors.accent,
                          width: 2,
                        ),
                      ),
                      child: Icon(
                        Icons.check,
                        color: context.colors.background,
                        size: 16,
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
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: context.colors.buttonPrimary,
                borderRadius: BorderRadius.circular(40),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.trending_up,
                        color: context.colors.buttonText,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Popular',
                        style: TextStyle(
                          color: context.colors.buttonText,
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  if (viewModel.sortMode == FeedSortMode.mostInteracted && viewModel.hashtag == null)
                    Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: context.colors.accent,
                        border: Border.all(
                          color: context.colors.accent,
                          width: 2,
                        ),
                      ),
                      child: Icon(
                        Icons.check,
                        color: context.colors.background,
                        size: 16,
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
