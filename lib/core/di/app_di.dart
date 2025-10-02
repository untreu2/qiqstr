import 'package:get_it/get_it.dart';

import 'modules/services_module.dart';
import 'modules/repositories_module.dart';
import 'modules/viewmodels_module.dart';

/// Global dependency injection container
/// Provides a centralized way to manage dependencies across the application
class AppDI {
  static final GetIt _getIt = GetIt.instance;

  /// Get instance of type T from the container
  static T get<T extends Object>() => _getIt.get<T>();

  /// Get instance of type T from the container (nullable)
  static T? getOrNull<T extends Object>() {
    try {
      return _getIt.get<T>();
    } catch (e) {
      return null;
    }
  }

  /// Check if type T is registered
  static bool isRegistered<T extends Object>() => _getIt.isRegistered<T>();

  /// Register a singleton instance
  static void registerSingleton<T extends Object>(T instance) {
    _getIt.registerSingleton<T>(instance);
  }

  /// Register a lazy singleton (created on first access)
  static void registerLazySingleton<T extends Object>(T Function() factory) {
    _getIt.registerLazySingleton<T>(factory);
  }

  /// Register a factory (new instance every time)
  static void registerFactory<T extends Object>(T Function() factory) {
    _getIt.registerFactory<T>(factory);
  }

  /// Initialize all dependencies
  /// Call this in main() before runApp()
  static Future<void> initialize() async {
    // Register modules in correct order (dependencies first)
    await ServicesModule().register();
    await RepositoriesModule().register();
    await ViewModelsModule().register();

    // Mark as ready
    await _getIt.allReady();
  }

  /// Reset all dependencies (useful for testing)
  static Future<void> reset() async {
    await _getIt.reset();
  }

  /// Unregister a specific type
  static Future<void> unregister<T extends Object>() async {
    await _getIt.unregister<T>();
  }
}

/// Base class for dependency injection modules
abstract class DIModule {
  /// Register dependencies for this module
  Future<void> register();
}
