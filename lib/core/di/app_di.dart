import 'package:get_it/get_it.dart';

import 'modules/services_module.dart';
import 'modules/repositories_module.dart';
import 'modules/viewmodels_module.dart';

class AppDI {
  static final GetIt _getIt = GetIt.instance;

  static T get<T extends Object>() => _getIt.get<T>();

  static T? getOrNull<T extends Object>() {
    try {
      return _getIt.get<T>();
    } catch (e) {
      return null;
    }
  }

  static bool isRegistered<T extends Object>() => _getIt.isRegistered<T>();

  static void registerSingleton<T extends Object>(T instance) {
    _getIt.registerSingleton<T>(instance);
  }

  static void registerLazySingleton<T extends Object>(T Function() factory) {
    _getIt.registerLazySingleton<T>(factory);
  }

  static void registerFactory<T extends Object>(T Function() factory) {
    _getIt.registerFactory<T>(factory);
  }

  static Future<void> initialize() async {
    await ServicesModule().register();
    await RepositoriesModule().register();
    await ViewModelsModule().register();

    await _getIt.allReady();
  }

  static Future<void> reset() async {
    await _getIt.reset();
  }

  static Future<void> unregister<T extends Object>() async {
    await _getIt.unregister<T>();
  }
}

abstract class DIModule {
  Future<void> register();
}
