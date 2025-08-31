import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../theme/theme_manager.dart';

enum ProfileImageSize {
  small(12, 24, 48),
  medium(22, 44, 88),
  large(40, 80, 160),
  xlarge(21, 42, 84);

  const ProfileImageSize(this.radius, this.size, this.cacheSize);
  final double radius;
  final double size;
  final int cacheSize;
}

class ProfileImageWidget extends StatelessWidget {
  final String imageUrl;
  final String npub;
  final ProfileImageSize size;
  final Color? backgroundColor;
  final double? borderWidth;
  final Color? borderColor;
  final VoidCallback? onTap;

  const ProfileImageWidget({
    super.key,
    required this.imageUrl,
    required this.npub,
    required this.size,
    this.backgroundColor,
    this.borderWidth,
    this.borderColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    Widget imageWidget = SizedBox(
      width: size.size,
      height: size.size,
      child: imageUrl.isNotEmpty
          ? CachedNetworkImage(
              key: ValueKey('profile_image_${npub}_${imageUrl.hashCode}'),
              imageUrl: imageUrl,
              fadeInDuration: Duration.zero,
              placeholderFadeInDuration: Duration.zero,
              memCacheWidth: size.cacheSize,
              memCacheHeight: size.cacheSize,
              maxWidthDiskCache: (size.cacheSize * 2.5).round(),
              maxHeightDiskCache: (size.cacheSize * 2.5).round(),
              imageBuilder: (context, imageProvider) {
                return Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: borderWidth != null && borderColor != null ? Border.all(color: borderColor!, width: borderWidth!) : null,
                    image: DecorationImage(
                      image: imageProvider,
                      fit: BoxFit.cover,
                    ),
                  ),
                );
              },
              placeholder: (context, url) => _buildPlaceholder(context, colors),
              errorWidget: (context, url, error) => _buildPlaceholder(context, colors),
            )
          : _buildPlaceholder(context, colors),
    );

    if (onTap != null) {
      return GestureDetector(
        onTap: onTap,
        child: imageWidget,
      );
    }

    return imageWidget;
  }

  Widget _buildPlaceholder(BuildContext context, dynamic colors) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: backgroundColor ?? colors.surfaceTransparent,
        border: borderWidth != null && borderColor != null ? Border.all(color: borderColor!, width: borderWidth!) : null,
      ),
      child: Icon(
        Icons.person,
        size: size.radius,
        color: colors.textSecondary,
      ),
    );
  }
}

extension ProfileImageHelper on ProfileImageWidget {
  static Widget small({
    required String imageUrl,
    required String npub,
    Color? backgroundColor,
    VoidCallback? onTap,
  }) {
    return ProfileImageWidget(
      imageUrl: imageUrl,
      npub: npub,
      size: ProfileImageSize.small,
      backgroundColor: backgroundColor,
      onTap: onTap,
    );
  }

  static Widget medium({
    required String imageUrl,
    required String npub,
    Color? backgroundColor,
    VoidCallback? onTap,
  }) {
    return ProfileImageWidget(
      imageUrl: imageUrl,
      npub: npub,
      size: ProfileImageSize.medium,
      backgroundColor: backgroundColor,
      onTap: onTap,
    );
  }

  static Widget large({
    required String imageUrl,
    required String npub,
    Color? backgroundColor,
    double? borderWidth,
    Color? borderColor,
    VoidCallback? onTap,
  }) {
    return ProfileImageWidget(
      imageUrl: imageUrl,
      npub: npub,
      size: ProfileImageSize.large,
      backgroundColor: backgroundColor,
      borderWidth: borderWidth,
      borderColor: borderColor,
      onTap: onTap,
    );
  }

  static Widget xlarge({
    required String imageUrl,
    required String npub,
    Color? backgroundColor,
    VoidCallback? onTap,
  }) {
    return ProfileImageWidget(
      imageUrl: imageUrl,
      npub: npub,
      size: ProfileImageSize.xlarge,
      backgroundColor: backgroundColor,
      onTap: onTap,
    );
  }
}
