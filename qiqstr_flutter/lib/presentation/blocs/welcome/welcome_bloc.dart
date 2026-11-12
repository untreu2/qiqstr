import 'package:flutter_bloc/flutter_bloc.dart';

import 'welcome_event.dart';
import 'welcome_state.dart';

class WelcomeBloc extends Bloc<WelcomeEvent, WelcomeState> {
  WelcomeBloc() : super(const WelcomeState()) {
    on<WelcomeTermsChanged>((event, emit) => emit(state.copyWith(
          acceptedTerms: event.accepted,
          showTermsError: false,
        )));
    on<WelcomeTermsRequired>((event, emit) => emit(state.copyWith(
          showTermsError: !state.acceptedTerms,
        )));
  }
}
