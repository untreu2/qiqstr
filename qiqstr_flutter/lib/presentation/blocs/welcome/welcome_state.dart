import '../../../core/bloc/base/base_state.dart';

class WelcomeState extends BaseState {
  final bool acceptedTerms;
  final bool showTermsError;

  const WelcomeState({this.acceptedTerms = false, this.showTermsError = false});

  WelcomeState copyWith({bool? acceptedTerms, bool? showTermsError}) =>
      WelcomeState(
        acceptedTerms: acceptedTerms ?? this.acceptedTerms,
        showTermsError: showTermsError ?? this.showTermsError,
      );

  @override
  List<Object?> get props => [acceptedTerms, showTermsError];
}
