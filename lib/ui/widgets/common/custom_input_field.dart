import 'package:flutter/material.dart';
import '../../theme/theme_manager.dart';

class CustomInputField extends StatelessWidget {
  final TextEditingController? controller;
  final String? hintText;
  final String? labelText;
  final TextStyle? labelStyle;
  final TextStyle? hintStyle;
  final TextStyle? style;
  final Widget? suffixIcon;
  final VoidCallback? onTap;
  final bool autofocus;
  final bool enabled;
  final int? maxLines;
  final int? maxLength;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;
  final void Function(String)? onChanged;
  final FocusNode? focusNode;
  final Color? fillColor;
  final EdgeInsets? contentPadding;
  final double? height;

  const CustomInputField({
    super.key,
    this.controller,
    this.hintText,
    this.labelText,
    this.labelStyle,
    this.hintStyle,
    this.style,
    this.suffixIcon,
    this.onTap,
    this.autofocus = false,
    this.enabled = true,
    this.maxLines = 1,
    this.maxLength,
    this.keyboardType,
    this.validator,
    this.onChanged,
    this.focusNode,
    this.fillColor,
    this.contentPadding,
    this.height = 56,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final effectiveFillColor = fillColor ?? colors.overlayLight;
    final effectiveContentPadding = contentPadding ?? const EdgeInsets.symmetric(horizontal: 16, vertical: 14);
    
    final inputDecoration = InputDecoration(
      hintText: hintText,
      hintStyle: hintStyle ?? TextStyle(
        color: colors.textSecondary,
        fontSize: 15,
      ),
      labelText: labelText,
      labelStyle: labelStyle ?? TextStyle(
        fontWeight: FontWeight.w600,
        color: colors.textSecondary,
      ),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: effectiveFillColor,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(28),
        borderSide: BorderSide.none,
      ),
      contentPadding: effectiveContentPadding,
      isDense: maxLines == 1,
    );

    Widget inputWidget;
    
    if (validator != null) {
      inputWidget = TextFormField(
        controller: controller,
        focusNode: focusNode,
        autofocus: autofocus,
        enabled: enabled,
        maxLines: maxLines,
        maxLength: maxLength,
        keyboardType: keyboardType,
        onChanged: onChanged,
        onTap: onTap,
        validator: validator,
        style: style ?? TextStyle(
          color: colors.textPrimary,
          fontSize: 15,
        ),
        cursorColor: colors.textPrimary,
        decoration: inputDecoration,
      );
    } else {
      inputWidget = TextField(
        controller: controller,
        focusNode: focusNode,
        autofocus: autofocus,
        enabled: enabled,
        maxLines: maxLines,
        maxLength: maxLength,
        keyboardType: keyboardType,
        onChanged: onChanged,
        onTap: onTap,
        style: style ?? TextStyle(
          color: colors.textPrimary,
          fontSize: 15,
        ),
        cursorColor: colors.textPrimary,
        decoration: inputDecoration,
      );
    }

    if (maxLines == 1 && height != null) {
      return SizedBox(
        height: height,
        child: inputWidget,
      );
    }

    return inputWidget;
  }
}

