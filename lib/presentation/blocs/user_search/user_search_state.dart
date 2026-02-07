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
  final List<Map<String, dynamic>> randomUsers;
  final bool isSearching;
  final bool isLoadingRandom;

  const UserSearchLoaded({
    required this.filteredUsers,
    this.filteredNotes = const [],
    this.noteProfiles = const {},
    required this.randomUsers,
    this.isSearching = false,
    this.isLoadingRandom = false,
  });

  UserSearchLoaded copyWith({
    List<Map<String, dynamic>>? filteredUsers,
    List<Map<String, dynamic>>? filteredNotes,
    Map<String, Map<String, dynamic>>? noteProfiles,
    List<Map<String, dynamic>>? randomUsers,
    bool? isSearching,
    bool? isLoadingRandom,
  }) {
    return UserSearchLoaded(
      filteredUsers: filteredUsers ?? this.filteredUsers,
      filteredNotes: filteredNotes ?? this.filteredNotes,
      noteProfiles: noteProfiles ?? this.noteProfiles,
      randomUsers: randomUsers ?? this.randomUsers,
      isSearching: isSearching ?? this.isSearching,
      isLoadingRandom: isLoadingRandom ?? this.isLoadingRandom,
    );
  }

  @override
  List<Object?> get props => [
        filteredUsers,
        filteredNotes,
        noteProfiles,
        randomUsers,
        isSearching,
        isLoadingRandom
      ];
}

class UserSearchError extends UserSearchState {
  final String message;

  const UserSearchError(this.message);

  @override
  List<Object?> get props => [message];
}
