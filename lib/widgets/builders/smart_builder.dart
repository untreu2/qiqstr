import 'package:flutter/widgets.dart';
import '../../core/di/app_di.dart';
import '../../data/repositories/user_repository.dart';

/// Smart builder widget that efficiently rebuilds when specific data changes
class SmartBuilder<T extends Listenable> extends StatefulWidget {
  const SmartBuilder({
    super.key,
    required this.listenable,
    required this.builder,
    this.selector,
    this.child,
  });

  final T listenable;
  final Widget Function(BuildContext context, Widget? child) builder;
  final bool Function(T previous, T current)? selector;
  final Widget? child;

  @override
  State<SmartBuilder<T>> createState() => _SmartBuilderState<T>();
}

class _SmartBuilderState<T extends Listenable> extends State<SmartBuilder<T>> {
  T? _previousValue;

  @override
  void initState() {
    super.initState();
    widget.listenable.addListener(_handleChange);
    _previousValue = widget.listenable;
  }

  @override
  void didUpdateWidget(SmartBuilder<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.listenable != widget.listenable) {
      oldWidget.listenable.removeListener(_handleChange);
      widget.listenable.addListener(_handleChange);
      _previousValue = widget.listenable;
    }
  }

  @override
  void dispose() {
    widget.listenable.removeListener(_handleChange);
    super.dispose();
  }

  void _handleChange() {
    if (widget.selector != null) {
      if (_previousValue != null && !widget.selector!(_previousValue!, widget.listenable)) {
        return;
      }
    }

    _previousValue = widget.listenable;
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.builder(context, widget.child);
  }
}

/// Builder for user-related widgets
/// Uses UserRepository stream for efficient user data updates
class UserBuilder extends StatelessWidget {
  const UserBuilder({
    super.key,
    required this.userId,
    required this.builder,
    this.child,
  });

  final String userId;
  final Widget Function(BuildContext context, Widget? child) builder;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: AppDI.get<UserRepository>().currentUserStream,
      builder: (context, snapshot) {
        return builder(context, child);
      },
    );
  }
}

/// Builder for interaction-related widgets (reactions, replies, etc.)
/// Simplified for MVVM architecture - interactions are now handled in ViewModels
class InteractionBuilder extends StatelessWidget {
  const InteractionBuilder({
    super.key,
    required this.noteId,
    required this.builder,
    this.child,
  });

  final String noteId;
  final Widget Function(BuildContext context, Widget? child) builder;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    // In MVVM architecture, interactions are handled by ViewModels
    // This builder is kept for compatibility but simplified
    return builder(context, child);
  }
}

/// Multi-builder combining user and interaction data
class MultiBuilder extends StatelessWidget {
  const MultiBuilder({
    super.key,
    required this.userId,
    required this.noteId,
    required this.builder,
    this.child,
  });

  final String userId;
  final String noteId;
  final Widget Function(BuildContext context, Widget? child) builder;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return UserBuilder(
      userId: userId,
      builder: (context, child) => InteractionBuilder(
        noteId: noteId,
        builder: builder,
        child: child,
      ),
      child: child,
    );
  }
}
