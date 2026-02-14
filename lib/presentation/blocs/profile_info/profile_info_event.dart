import '../../../core/bloc/base/base_event.dart';

abstract class ProfileInfoEvent extends BaseEvent {
  const ProfileInfoEvent();
}

class ProfileInfoInitialized extends ProfileInfoEvent {
  final String userPubkeyHex;
  final Map<String, dynamic>? user;

  const ProfileInfoInitialized({required this.userPubkeyHex, this.user});

  @override
  List<Object?> get props => [userPubkeyHex, user];
}

class ProfileInfoUserUpdated extends ProfileInfoEvent {
  final Map<String, dynamic> user;

  const ProfileInfoUserUpdated({required this.user});

  @override
  List<Object?> get props => [user];
}

class ProfileInfoFollowToggled extends ProfileInfoEvent {
  const ProfileInfoFollowToggled();
}

class ProfileInfoMuteToggled extends ProfileInfoEvent {
  const ProfileInfoMuteToggled();
}

class ProfileInfoReportSubmitted extends ProfileInfoEvent {
  final String reportType;
  final String content;

  const ProfileInfoReportSubmitted({
    required this.reportType,
    this.content = '',
  });

  @override
  List<Object?> get props => [reportType, content];
}
