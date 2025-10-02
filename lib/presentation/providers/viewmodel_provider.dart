import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/di/app_di.dart';
import '../viewmodels/login_viewmodel.dart';
import '../viewmodels/feed_viewmodel.dart';
import '../viewmodels/profile_viewmodel.dart';
import '../viewmodels/notification_viewmodel.dart';
import '../viewmodels/thread_viewmodel.dart';
import '../viewmodels/compose_viewmodel.dart';

/// Provider for injecting ViewModels into the widget tree
/// Uses dependency injection to create ViewModels with their dependencies
class ViewModelProvider {
  /// Create a LoginViewModel provider
  static Widget login({
    required Widget Function(BuildContext context, LoginViewModel viewModel) builder,
  }) {
    return ChangeNotifierProvider<LoginViewModel>(
      create: (_) {
        final viewModel = AppDI.get<LoginViewModel>();
        return viewModel;
      },
      builder: (context, child) {
        final viewModel = Provider.of<LoginViewModel>(context, listen: false);
        return builder(context, viewModel);
      },
    );
  }

  /// Create a Consumer for LoginViewModel with automatic disposal
  static Widget loginConsumer({
    required Widget Function(BuildContext context, LoginViewModel viewModel, Widget? child) builder,
    Widget? child,
  }) {
    return ChangeNotifierProvider<LoginViewModel>(
      create: (_) {
        final viewModel = AppDI.get<LoginViewModel>();
        return viewModel;
      },
      child: Consumer<LoginViewModel>(
        builder: builder,
        child: child,
      ),
    );
  }

  /// Create a Selector for LoginViewModel with specific property listening
  static Widget loginSelector<T>({
    required T Function(LoginViewModel viewModel) selector,
    required Widget Function(BuildContext context, T value, Widget? child) builder,
    Widget? child,
  }) {
    return ChangeNotifierProvider<LoginViewModel>(
      create: (_) {
        final viewModel = AppDI.get<LoginViewModel>();
        return viewModel;
      },
      child: Selector<LoginViewModel, T>(
        selector: (context, viewModel) => selector(viewModel),
        builder: builder,
        child: child,
      ),
    );
  }

  /// Create a FeedViewModel provider
  static Widget feed({
    required Widget Function(BuildContext context, FeedViewModel viewModel) builder,
  }) {
    return ChangeNotifierProvider<FeedViewModel>(
      create: (_) {
        final viewModel = AppDI.get<FeedViewModel>();
        return viewModel;
      },
      builder: (context, child) {
        final viewModel = Provider.of<FeedViewModel>(context, listen: false);
        return builder(context, viewModel);
      },
    );
  }

  /// Create a ProfileViewModel provider
  static Widget profile({
    required Widget Function(BuildContext context, ProfileViewModel viewModel) builder,
  }) {
    return ChangeNotifierProvider<ProfileViewModel>(
      create: (_) {
        final viewModel = AppDI.get<ProfileViewModel>();
        return viewModel;
      },
      builder: (context, child) {
        final viewModel = Provider.of<ProfileViewModel>(context, listen: false);
        return builder(context, viewModel);
      },
    );
  }

  /// Create a Consumer for ProfileViewModel with automatic disposal
  static Widget profileConsumer({
    required Widget Function(BuildContext context, ProfileViewModel viewModel, Widget? child) builder,
    Widget? child,
  }) {
    return ChangeNotifierProvider<ProfileViewModel>(
      create: (_) {
        final viewModel = AppDI.get<ProfileViewModel>();
        return viewModel;
      },
      child: Consumer<ProfileViewModel>(
        builder: builder,
        child: child,
      ),
    );
  }

  /// Create a NotificationViewModel provider
  static Widget notification({
    required Widget Function(BuildContext context, NotificationViewModel viewModel) builder,
  }) {
    return ChangeNotifierProvider<NotificationViewModel>(
      create: (_) {
        final viewModel = AppDI.get<NotificationViewModel>();
        return viewModel;
      },
      builder: (context, child) {
        final viewModel = Provider.of<NotificationViewModel>(context, listen: false);
        return builder(context, viewModel);
      },
    );
  }

  /// Create a Consumer for NotificationViewModel with automatic disposal
  static Widget notificationConsumer({
    required Widget Function(BuildContext context, NotificationViewModel viewModel, Widget? child) builder,
    Widget? child,
  }) {
    return ChangeNotifierProvider<NotificationViewModel>(
      create: (_) {
        final viewModel = AppDI.get<NotificationViewModel>();
        return viewModel;
      },
      child: Consumer<NotificationViewModel>(
        builder: builder,
        child: child,
      ),
    );
  }

  /// Create a ThreadViewModel provider
  static Widget thread({
    required Widget Function(BuildContext context, ThreadViewModel viewModel) builder,
  }) {
    return ChangeNotifierProvider<ThreadViewModel>(
      create: (_) {
        final viewModel = AppDI.get<ThreadViewModel>();
        return viewModel;
      },
      builder: (context, child) {
        final viewModel = Provider.of<ThreadViewModel>(context, listen: false);
        return builder(context, viewModel);
      },
    );
  }

  /// Create a Consumer for ThreadViewModel with automatic disposal
  static Widget threadConsumer({
    required Widget Function(BuildContext context, ThreadViewModel viewModel, Widget? child) builder,
    Widget? child,
  }) {
    return ChangeNotifierProvider<ThreadViewModel>(
      create: (_) {
        final viewModel = AppDI.get<ThreadViewModel>();
        return viewModel;
      },
      child: Consumer<ThreadViewModel>(
        builder: builder,
        child: child,
      ),
    );
  }

  /// Create a ComposeViewModel provider
  static Widget compose({
    required Widget Function(BuildContext context, ComposeViewModel viewModel) builder,
  }) {
    return ChangeNotifierProvider<ComposeViewModel>(
      create: (_) {
        final viewModel = AppDI.get<ComposeViewModel>();
        return viewModel;
      },
      builder: (context, child) {
        final viewModel = Provider.of<ComposeViewModel>(context, listen: false);
        return builder(context, viewModel);
      },
    );
  }

  /// Create a Consumer for ComposeViewModel with automatic disposal
  static Widget composeConsumer({
    required Widget Function(BuildContext context, ComposeViewModel viewModel, Widget? child) builder,
    Widget? child,
  }) {
    return ChangeNotifierProvider<ComposeViewModel>(
      create: (_) {
        final viewModel = AppDI.get<ComposeViewModel>();
        return viewModel;
      },
      child: Consumer<ComposeViewModel>(
        builder: builder,
        child: child,
      ),
    );
  }

  // Future ViewModels can be added here:
  // static Widget search({...}) { ... }
}

/// Base provider widget for any ViewModel
class BaseViewModelProvider<T extends ChangeNotifier> extends StatefulWidget {
  final T Function() create;
  final Widget Function(BuildContext context, T viewModel) builder;

  const BaseViewModelProvider({
    super.key,
    required this.create,
    required this.builder,
  });

  @override
  State<BaseViewModelProvider<T>> createState() => _BaseViewModelProviderState<T>();
}

class _BaseViewModelProviderState<T extends ChangeNotifier> extends State<BaseViewModelProvider<T>> {
  late T _viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel = widget.create();
  }

  @override
  void dispose() {
    _viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<T>.value(
      value: _viewModel,
      child: Consumer<T>(
        builder: (context, viewModel, child) => widget.builder(context, viewModel),
      ),
    );
  }
}

/// Convenient extension for getting ViewModels from context
extension ViewModelExtensions on BuildContext {
  /// Get ViewModel instance (listen = false)
  T viewModel<T extends ChangeNotifier>() => Provider.of<T>(this, listen: false);

  /// Watch ViewModel for changes (listen = true)
  T watchViewModel<T extends ChangeNotifier>() => Provider.of<T>(this, listen: true);
}

/// Mixin for automatic ViewModel disposal in StatefulWidgets
mixin ViewModelMixin<T extends StatefulWidget, VM extends ChangeNotifier> on State<T> {
  VM? _viewModel;

  /// Get or create ViewModel instance
  VM get viewModel {
    _viewModel ??= createViewModel();
    return _viewModel!;
  }

  /// Override this method to create the ViewModel
  VM createViewModel();

  @override
  void dispose() {
    _viewModel?.dispose();
    super.dispose();
  }
}

/// Widget builder that provides automatic ViewModel management
class ViewModelBuilder<T extends ChangeNotifier> extends StatefulWidget {
  final T Function() create;
  final Widget Function(BuildContext context, T viewModel) builder;
  final void Function(T viewModel)? onModelReady;

  const ViewModelBuilder({
    super.key,
    required this.create,
    required this.builder,
    this.onModelReady,
  });

  @override
  State<ViewModelBuilder<T>> createState() => _ViewModelBuilderState<T>();
}

class _ViewModelBuilderState<T extends ChangeNotifier> extends State<ViewModelBuilder<T>> {
  late T _viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel = widget.create();
    widget.onModelReady?.call(_viewModel);
  }

  @override
  void dispose() {
    _viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<T>.value(
      value: _viewModel,
      child: Consumer<T>(
        builder: (context, viewModel, child) => widget.builder(context, viewModel),
      ),
    );
  }
}
