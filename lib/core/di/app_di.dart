import 'package:get_it/get_it.dart';

import 'modules/services_module.dart';
import 'modules/repositories_module.dart';
import 'modules/viewmodels_module.dart';

class AppDI {
  static final GetIt _getIt = GetIt.instance;

  static T get<T extends Object>() => _getIt.get<T>();

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
}

abstract class DIModule {
  Future<void> register();
}
