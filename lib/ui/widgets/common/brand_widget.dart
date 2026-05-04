import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/theme_manager.dart';

class BrandWidget extends StatelessWidget {
  final double iconSize;
  final double fontSize;
  final double iconTopPadding;
  final MainAxisAlignment mainAxisAlignment;
  final CrossAxisAlignment crossAxisAlignment;

  const BrandWidget({
    super.key,
    this.iconSize = 50,
    this.fontSize = 48,
    this.iconTopPadding = 24,
    this.mainAxisAlignment = MainAxisAlignment.center,
    this.crossAxisAlignment = CrossAxisAlignment.start,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: mainAxisAlignment,
      crossAxisAlignment: crossAxisAlignment,
      children: [
        Padding(
          padding: EdgeInsets.only(top: iconTopPadding),
          child: PhosphorIcon(
            PhosphorIcons.house(),
            size: iconSize,
            color: context.colors.textPrimary,
          ),
        ),
        const SizedBox(width: 12),
        Text(
          'qiqstr',
          style: GoogleFonts.poppins(
            fontSize: fontSize,
            fontWeight: FontWeight.w700,
            color: context.colors.textPrimary,
            letterSpacing: -0.5,
          ),
        ),
      ],
    );
  }
}
