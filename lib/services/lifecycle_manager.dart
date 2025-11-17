import 'package:flutter/widgets.dart';
import 'package:flutter/foundation.dart';

class LifecycleManager with WidgetsBindingObserver {
  static final LifecycleManager _instance = LifecycleManager._internal();
  factory LifecycleManager() => _instance;
  LifecycleManager._internal();

  final List<VoidCallback> _onResumeCallbacks = [];
  final List<VoidCallback> _onPauseCallbacks = [];
  final List<VoidCallback> _onInactiveCallbacks = [];
  final List<VoidCallback> _onDetachedCallbacks = [];

  bool _isAppInForeground = true;
  bool _isInitialized = false;

  void initialize() {
    if (_isInitialized) return;
    
    WidgetsBinding.instance.addObserver(this);
    _isInitialized = true;
    debugPrint('[LifecycleManager] Initialized');
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    debugPrint('[LifecycleManager] App lifecycle changed to: $state');
    
    switch (state) {
      case AppLifecycleState.resumed:
        _isAppInForeground = true;
        _triggerCallbacks(_onResumeCallbacks);
        break;
      case AppLifecycleState.inactive:
        _triggerCallbacks(_onInactiveCallbacks);
        break;
      case AppLifecycleState.paused:
        _isAppInForeground = false;
        _triggerCallbacks(_onPauseCallbacks);
        break;
      case AppLifecycleState.detached:
        _triggerCallbacks(_onDetachedCallbacks);
        break;
      case AppLifecycleState.hidden:
        break;
    }
  }

  void _triggerCallbacks(List<VoidCallback> callbacks) {
    for (final callback in callbacks) {
      try {
        callback();
      } catch (e) {
        debugPrint('[LifecycleManager] Error in callback: $e');
      }
    }
  }

  void addOnResumeCallback(VoidCallback callback) {
    if (!_onResumeCallbacks.contains(callback)) {
      _onResumeCallbacks.add(callback);
    }
  }

  void addOnPauseCallback(VoidCallback callback) {
    if (!_onPauseCallbacks.contains(callback)) {
      _onPauseCallbacks.add(callback);
    }
  }

  void removeOnResumeCallback(VoidCallback callback) {
    _onResumeCallbacks.remove(callback);
  }

  void removeOnPauseCallback(VoidCallback callback) {
    _onPauseCallbacks.remove(callback);
  }

  bool get isAppInForeground => _isAppInForeground;

  void dispose() {
    if (_isInitialized) {
      WidgetsBinding.instance.removeObserver(this);
      _isInitialized = false;
    }
    _onResumeCallbacks.clear();
    _onPauseCallbacks.clear();
    _onInactiveCallbacks.clear();
    _onDetachedCallbacks.clear();
  }
}

