import '../../../core/bloc/base/base_state.dart';

abstract class DmIndicatorState extends BaseState {
  const DmIndicatorState();
}

class DmIndicatorInitial extends DmIndicatorState {
  const DmIndicatorInitial();
}

class DmIndicatorLoaded extends DmIndicatorState {
  final bool hasNewMessages;

  const DmIndicatorLoaded({required this.hasNewMessages});

  @override
  List<Object?> get props => [hasNewMessages];
}
