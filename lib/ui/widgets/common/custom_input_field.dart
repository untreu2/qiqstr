import 'package:flutter/material.dart';
import '../../theme/theme_manager.dart';

class CustomInputField extends StatelessWidget {
  final TextEditingController? controller;
  final String? hintText;
  final String? labelText;
  final TextStyle? labelStyle;
  final TextStyle? hintStyle;
  final TextStyle? style;
  final Widget? prefixIcon;
  final Widget? suffixIcon;
  final VoidCallback? onTap;
  final bool autofocus;
  final bool enabled;
  final bool readOnly;
  final int? maxLines;
  final int? maxLength;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;
  final void Function(String)? onChanged;
  final VoidCallback? onEditingComplete;
  final void Function(String)? onSubmitted;
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
    this.prefixIcon,
    this.suffixIcon,
    this.onTap,
    this.autofocus = false,
    this.enabled = true,
    this.readOnly = false,
    this.maxLines = 1,
    this.maxLength,
    this.keyboardType,
    this.validator,
    this.onChanged,
    this.onEditingComplete,
    this.onSubmitted,
    this.focusNode,
    this.fillColor,
    this.contentPadding,
    this.height = 56,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final effectiveFillColor = fillColor ?? colors.overlayLight;
    final effectiveContentPadding = contentPadding ??
        const EdgeInsets.symmetric(horizontal: 16, vertical: 14);

    final inputDecoration = InputDecoration(
      hintText: hintText,
      hintStyle: hintStyle ??
          TextStyle(
            color: colors.textSecondary,
            fontSize: 15,
          ),
      labelText: labelText,
      labelStyle: labelStyle ??
          TextStyle(
            fontWeight: FontWeight.w600,
            color: colors.textSecondary,
          ),
      prefixIcon: prefixIcon,
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: effectiveFillColor,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(24),
        borderSide: BorderSide.none,
      ),
      contentPadding: effectiveContentPadding,
      isCollapsed: false,
    );

    Widget inputWidget;

    if (validator != null) {
      inputWidget = TextFormField(
        controller: controller,
        focusNode: focusNode,
        autofocus: autofocus,
        enabled: enabled,
        readOnly: readOnly,
        maxLines: maxLines,
        maxLength: maxLength,
        keyboardType: keyboardType,
        onChanged: onChanged,
        onEditingComplete: onEditingComplete,
        onFieldSubmitted: onSubmitted,
        onTap: onTap,
        validator: validator,
        textAlignVertical: TextAlignVertical.center,
        style: style ??
            TextStyle(
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
        readOnly: readOnly,
        maxLines: maxLines,
        maxLength: maxLength,
        keyboardType: keyboardType,
        onChanged: onChanged,
        onEditingComplete: onEditingComplete,
        onSubmitted: onSubmitted,
        onTap: onTap,
        textAlignVertical: TextAlignVertical.center,
        style: style ??
            TextStyle(
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
