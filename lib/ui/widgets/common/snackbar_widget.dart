import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../presentation/blocs/theme/theme_bloc.dart';
import '../../theme/theme_manager.dart';
import 'common_buttons.dart';

enum SnackbarType {
  success,
  error,
  info,
  warning,
}

class AppSnackbar {
  static OverlayEntry? _currentEntry;
  static Timer? _dismissTimer;
  static double _headerOffset = 0;

  static void setHeaderOffset(double offset) {
    _headerOffset = offset;
  }

  static void show(
    BuildContext context,
    String message, {
    SnackbarType type = SnackbarType.info,
    Duration duration = const Duration(seconds: 3),
    SnackBarAction? action,
  }) {
    if (!context.mounted) return;

    _dismiss();

    final overlay = Overlay.of(context, rootOverlay: true);
    final colors = _getColors(context);
    final topPadding = MediaQuery.of(context).padding.top;
    final topOffset =
        _headerOffset > 0 ? _headerOffset + 24 : topPadding + 24;

    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (context) => _TopSnackbar(
        message: message,
        colors: colors,
        topOffset: topOffset,
        action: action,
        duration: duration,
        onDismiss: () {
          _dismiss();
        },
      ),
    );

    _currentEntry = entry;
    overlay.insert(entry);

    _dismissTimer = Timer(duration + const Duration(milliseconds: 400), () {
      _dismiss();
    });
  }

  static void _dismiss() {
    _dismissTimer?.cancel();
    _dismissTimer = null;
    _currentEntry?.remove();
    _currentEntry = null;
  }

  static void success(BuildContext context, String message,
      {Duration? duration, SnackBarAction? action}) {
    show(
      context,
      message,
      type: SnackbarType.success,
      duration: duration ?? const Duration(seconds: 3),
      action: action,
    );
  }

  static void error(BuildContext context, String message,
      {Duration? duration, SnackBarAction? action}) {
    show(
      context,
      message,
      type: SnackbarType.error,
      duration: duration ?? const Duration(seconds: 4),
      action: action,
    );
  }

  static void info(BuildContext context, String message,
      {Duration? duration, SnackBarAction? action}) {
    show(
      context,
      message,
      type: SnackbarType.info,
      duration: duration ?? const Duration(seconds: 3),
      action: action,
    );
  }

  static void warning(BuildContext context, String message,
      {Duration? duration, SnackBarAction? action}) {
    show(
      context,
      message,
      type: SnackbarType.warning,
      duration: duration ?? const Duration(seconds: 3),
      action: action,
    );
  }

  static void hide(BuildContext context) {
    _dismiss();
  }

  static AppThemeColors _getColors(BuildContext context) {
    try {
      final themeState = context.read<ThemeBloc>().state;
      return themeState.colors;
    } catch (e) {
      return AppThemeColors.dark();
    }
  }
}

class _TopSnackbar extends StatefulWidget {
  final String message;
  final AppThemeColors colors;
  final double topOffset;
  final SnackBarAction? action;
  final Duration duration;
  final VoidCallback onDismiss;

  const _TopSnackbar({
    required this.message,
    required this.colors,
    required this.topOffset,
    required this.duration,
    required this.onDismiss,
    this.action,
  });

  @override
  State<_TopSnackbar> createState() => _TopSnackbarState();
}

class _TopSnackbarState extends State<_TopSnackbar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<Offset> _slideAnimation;
  late final Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _fadeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );

    _controller.forward();

    Future.delayed(widget.duration, () {
      if (mounted) {
        _controller.reverse().then((_) {
          if (mounted) widget.onDismiss();
        });
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _close() {
    if (!mounted) return;
    _controller.reverse().then((_) {
      if (mounted) widget.onDismiss();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: widget.topOffset,
      left: 16,
      right: 16,
      child: SlideTransition(
        position: _slideAnimation,
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: widget.colors.textPrimary.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(25),
              ),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: widget.colors.background,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.message,
                        style: TextStyle(
                          color: widget.colors.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (widget.action != null) ...[
                      const SizedBox(width: 8),
                      TextActionButton(
                        label: widget.action!.label,
                        onPressed: widget.action!.onPressed,
                        size: ButtonSize.small,
                        foregroundColor: widget.colors.textPrimary,
                      ),
                    ],
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: _close,
                      child: Icon(
                        Icons.close,
                        size: 16,
                        color: widget.colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
