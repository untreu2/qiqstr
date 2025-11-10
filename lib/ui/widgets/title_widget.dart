import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/theme_manager.dart';

class TitleWidget extends StatelessWidget {
  final String title;
  final double? fontSize;
  final String? subtitle;
  final Widget? subtitleAction;
  final VoidCallback? subtitleOnTap;
  final EdgeInsets? padding;
  final bool useTopPadding;

  const TitleWidget({
    super.key,
    required this.title,
    this.fontSize,
    this.subtitle,
    this.subtitleAction,
    this.subtitleOnTap,
    this.padding,
    this.useTopPadding = false,
  });

  @override
  Widget build(BuildContext context) {
    final double topPadding = MediaQuery.of(context).padding.top;
    final EdgeInsets effectivePadding = padding ??
        (useTopPadding
            ? EdgeInsets.fromLTRB(16, topPadding + 70, 16, 8)
            : const EdgeInsets.fromLTRB(16, 60, 16, 8));

    final Widget titleRow = Row(
      children: [
        Container(
          width: 5,
          height: 20,
          decoration: BoxDecoration(
            color: context.colors.accent,
            borderRadius: BorderRadius.circular(2.5),
          ),
        ),
        const SizedBox(width: 12),
        Text(
          title,
          style: GoogleFonts.poppins(
            fontSize: fontSize ?? 28,
            fontWeight: FontWeight.w700,
            color: context.colors.textPrimary,
            letterSpacing: -0.5,
          ),
        ),
      ],
    );

    if (subtitle != null) {
      return Padding(
        padding: effectivePadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            titleRow,
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(left: 17),
              child: subtitleAction != null
                  ? Row(
                      children: [
                        Expanded(
                          child: subtitleOnTap != null
                              ? GestureDetector(
                                  onTap: subtitleOnTap,
                                  child: Text(
                                    subtitle!,
                                    style: TextStyle(
                                      fontSize: 15,
                                      color: context.colors.textSecondary,
                                      height: 1.4,
                                    ),
                                  ),
                                )
                              : Text(
                                  subtitle!,
                                  style: TextStyle(
                                    fontSize: 15,
                                    color: context.colors.textSecondary,
                                    height: 1.4,
                                  ),
                                ),
                        ),
                        const SizedBox(width: 8),
                        subtitleAction!,
                      ],
                    )
                  : subtitleOnTap != null
                      ? GestureDetector(
                          onTap: subtitleOnTap,
                          child: Text(
                            subtitle!,
                            style: TextStyle(
                              fontSize: 15,
                              color: context.colors.textSecondary,
                              height: 1.4,
                            ),
                          ),
                        )
                      : Text(
                          subtitle!,
                          style: TextStyle(
                            fontSize: 15,
                            color: context.colors.textSecondary,
                            height: 1.4,
                          ),
                        ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: effectivePadding,
      child: titleRow,
    );
  }
}

