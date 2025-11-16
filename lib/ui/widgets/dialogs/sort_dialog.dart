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
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: viewModel.sortMode == FeedSortMode.latest && viewModel.hashtag == null
                          ? context.colors.accent
                          : Colors.transparent,
                      border: Border.all(
                        color: viewModel.sortMode == FeedSortMode.latest && viewModel.hashtag == null
                            ? context.colors.accent
                            : context.colors.border,
                        width: 2,
                      ),
                    ),
                    child: viewModel.sortMode == FeedSortMode.latest && viewModel.hashtag == null
                        ? Icon(
                            Icons.check,
                            color: context.colors.background,
                            size: 16,
                          )
                        : null,
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
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: viewModel.sortMode == FeedSortMode.mostInteracted && viewModel.hashtag == null
                          ? context.colors.accent
                          : Colors.transparent,
                      border: Border.all(
                        color: viewModel.sortMode == FeedSortMode.mostInteracted && viewModel.hashtag == null
                            ? context.colors.accent
                            : context.colors.border,
                        width: 2,
                      ),
                    ),
                    child: viewModel.sortMode == FeedSortMode.mostInteracted && viewModel.hashtag == null
                        ? Icon(
                            Icons.check,
                            color: context.colors.background,
                            size: 16,
                          )
                        : null,
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
                        Icons.tag,
                        color: context.colors.buttonText,
                        size: 20,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'bitcoin',
                        style: TextStyle(
                          color: context.colors.buttonText,
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: viewModel.hashtag == 'bitcoin' ? context.colors.accent : Colors.transparent,
                      border: Border.all(
                        color: viewModel.hashtag == 'bitcoin' ? context.colors.accent : context.colors.border,
                        width: 2,
                      ),
                    ),
                    child: viewModel.hashtag == 'bitcoin'
                        ? Icon(
                            Icons.check,
                            color: context.colors.background,
                            size: 16,
                          )
                        : null,
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
                        Icons.tag,
                        color: context.colors.buttonText,
                        size: 20,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'nostr',
                        style: TextStyle(
                          color: context.colors.buttonText,
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: viewModel.hashtag == 'nostr' ? context.colors.accent : Colors.transparent,
                      border: Border.all(
                        color: viewModel.hashtag == 'nostr' ? context.colors.accent : context.colors.border,
                        width: 2,
                      ),
                    ),
                    child: viewModel.hashtag == 'nostr'
                        ? Icon(
                            Icons.check,
                            color: context.colors.background,
                            size: 16,
                          )
                        : null,
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
                        Icons.tag,
                        color: context.colors.buttonText,
                        size: 20,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'foodstr',
                        style: TextStyle(
                          color: context.colors.buttonText,
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: viewModel.hashtag == 'foodstr' ? context.colors.accent : Colors.transparent,
                      border: Border.all(
                        color: viewModel.hashtag == 'foodstr' ? context.colors.accent : context.colors.border,
                        width: 2,
                      ),
                    ),
                    child: viewModel.hashtag == 'foodstr'
                        ? Icon(
                            Icons.check,
                            color: context.colors.background,
                            size: 16,
                          )
                        : null,
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
