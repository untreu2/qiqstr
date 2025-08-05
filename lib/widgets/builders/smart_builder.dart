import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import '../../providers/user_provider.dart';
import '../../providers/interactions_provider.dart';

/// A more efficient version of ListenableBuilder that only rebuilds when specific conditions are met
class SmartBuilder<T extends Listenable> extends StatefulWidget {
  const SmartBuilder({
    Key? key,
    required this.listenable,
    required this.builder,
    this.selector,
    this.child,
  }) : super(key: key);

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
        return; // Don't rebuild if selector returns false
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

/// A builder that only rebuilds when specific user data changes
class UserBuilder extends StatelessWidget {
  const UserBuilder({
    Key? key,
    required this.userId,
    required this.builder,
    this.child,
  }) : super(key: key);

  final String userId;
  final Widget Function(BuildContext context, Widget? child) builder;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return SmartBuilder(
      listenable: UserProvider.instance,
      selector: (previous, current) {
        // Only rebuild if this specific user's data changed
        final prevUser = (previous).getUser(userId);
        final currUser = (current).getUser(userId);
        return prevUser != currUser;
      },
      builder: builder,
      child: child,
    );
  }
}

/// A builder that only rebuilds when specific note interactions change
class InteractionBuilder extends StatelessWidget {
  const InteractionBuilder({
    Key? key,
    required this.noteId,
    required this.builder,
    this.child,
  }) : super(key: key);

  final String noteId;
  final Widget Function(BuildContext context, Widget? child) builder;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return SmartBuilder(
      listenable: InteractionsProvider.instance,
      selector: (previous, current) {
        // Only rebuild if this specific note's interactions changed
        final prev = previous;
        final curr = current;
        return prev.getReactionCount(noteId) != curr.getReactionCount(noteId) ||
            prev.getReplyCount(noteId) != curr.getReplyCount(noteId) ||
            prev.getRepostCount(noteId) != curr.getRepostCount(noteId) ||
            prev.getZapAmount(noteId) != curr.getZapAmount(noteId);
      },
      builder: builder,
      child: child,
    );
  }
}

/// A builder that combines multiple smart listeners efficiently
class MultiBuilder extends StatelessWidget {
  const MultiBuilder({
    Key? key,
    required this.userId,
    required this.noteId,
    required this.builder,
    this.child,
  }) : super(key: key);

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
