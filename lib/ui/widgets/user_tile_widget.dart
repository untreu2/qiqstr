import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../theme/theme_manager.dart';
import '../../models/user_model.dart';
import '../screens/profile_page.dart';

class UserTile extends StatelessWidget {
  final UserModel user;

  const UserTile({
    super.key,
    required this.user,
  });

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ProfilePage(user: user),
              ),
            );
          },
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
            decoration: BoxDecoration(
              color: context.colors.overlayLight,
              borderRadius: BorderRadius.circular(40),
            ),
            child: Row(
              children: [
                _UserAvatar(
                  imageUrl: user.profileImage,
                  colors: context.colors,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          user.name.length > 25
                              ? '${user.name.substring(0, 25)}...'
                              : user.name,
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                            color: context.colors.textPrimary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (user.nip05.isNotEmpty && user.nip05Verified) ...[
                        const SizedBox(width: 4),
                        Icon(
                          Icons.verified,
                          size: 16,
                          color: context.colors.accent,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _UserAvatar extends StatelessWidget {
  final String imageUrl;
  final dynamic colors;

  const _UserAvatar({
    required this.imageUrl,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    if (imageUrl.isEmpty) {
      return RepaintBoundary(
        child: CircleAvatar(
          radius: 24,
          backgroundColor: Colors.grey.shade800,
          child: Icon(
            Icons.person,
            size: 26,
            color: colors.textSecondary,
          ),
        ),
      );
    }

    return RepaintBoundary(
      child: ClipOval(
        clipBehavior: Clip.antiAlias,
        child: Container(
          width: 48,
          height: 48,
          color: Colors.transparent,
          child: CachedNetworkImage(
            key: ValueKey('user_avatar_${imageUrl.hashCode}'),
            imageUrl: imageUrl,
            width: 48,
            height: 48,
            fit: BoxFit.cover,
            fadeInDuration: Duration.zero,
            fadeOutDuration: Duration.zero,
            memCacheWidth: 180,
            placeholder: (context, url) => Container(
              color: Colors.grey.shade800,
              child: Icon(
                Icons.person,
                size: 26,
                color: colors.textSecondary,
              ),
            ),
            errorWidget: (context, url, error) => Container(
              color: Colors.grey.shade800,
              child: Icon(
                Icons.person,
                size: 26,
                color: colors.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

