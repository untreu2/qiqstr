import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../data/services/logging_service.dart';

class AppBlocObserver extends BlocObserver {
  @override
  void onCreate(BlocBase bloc) {
    super.onCreate(bloc);
    loggingService.debug('BLoC Created: ${bloc.runtimeType}', 'BlocObserver');
  }

  @override
  void onEvent(Bloc<dynamic, dynamic> bloc, Object? event) {
    super.onEvent(bloc, event);
    loggingService.debug(
      'Event: ${event.runtimeType} in ${bloc.runtimeType}',
      'BlocObserver',
    );
  }

  @override
  void onChange(BlocBase bloc, Change change) {
    super.onChange(bloc, change);
    loggingService.debug(
      'State Change in ${bloc.runtimeType}: ${change.currentState.runtimeType} -> ${change.nextState.runtimeType}',
      'BlocObserver',
    );
  }

  @override
  void onTransition(Bloc<dynamic, dynamic> bloc, Transition transition) {
    super.onTransition(bloc, transition);
    loggingService.debug(
      'Transition in ${bloc.runtimeType}: ${transition.event.runtimeType} -> ${transition.nextState.runtimeType}',
      'BlocObserver',
    );
  }

  @override
  void onError(BlocBase bloc, Object error, StackTrace stackTrace) {
    super.onError(bloc, error, stackTrace);
    loggingService.error(
      'Error in ${bloc.runtimeType}: $error',
      'BlocObserver',
    );
    loggingService.error(
      'StackTrace: $stackTrace',
      'BlocObserver',
    );
  }

  @override
  void onClose(BlocBase bloc) {
    super.onClose(bloc);
    loggingService.debug('BLoC Closed: ${bloc.runtimeType}', 'BlocObserver');
  }
}
