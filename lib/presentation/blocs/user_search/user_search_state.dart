import '../../../core/bloc/base/base_state.dart';

abstract class UserSearchState extends BaseState {
  const UserSearchState();
}

class UserSearchInitial extends UserSearchState {
  const UserSearchInitial();
}

class UserSearchLoading extends UserSearchState {
  const UserSearchLoading();
}

class UserSearchLoaded extends UserSearchState {
  final List<Map<String, dynamic>> filteredUsers;
  final List<Map<String, dynamic>> filteredNotes;
  final Map<String, Map<String, dynamic>> noteProfiles;
  final bool isSearching;

  const UserSearchLoaded({
    required this.filteredUsers,
    this.filteredNotes = const [],
    this.noteProfiles = const {},
    this.isSearching = false,
  });

  UserSearchLoaded copyWith({
    List<Map<String, dynamic>>? filteredUsers,
    List<Map<String, dynamic>>? filteredNotes,
    Map<String, Map<String, dynamic>>? noteProfiles,
    bool? isSearching,
  }) {
    return UserSearchLoaded(
      filteredUsers: filteredUsers ?? this.filteredUsers,
      filteredNotes: filteredNotes ?? this.filteredNotes,
      noteProfiles: noteProfiles ?? this.noteProfiles,
      isSearching: isSearching ?? this.isSearching,
    );
  }

  @override
  List<Object?> get props => [
        filteredUsers,
        filteredNotes,
        noteProfiles,
        isSearching,
      ];
}

class UserSearchError extends UserSearchState {
  final String message;

  const UserSearchError(this.message);

  @override
  List<Object?> get props => [message];
}
