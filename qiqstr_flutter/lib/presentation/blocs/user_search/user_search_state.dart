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
  final bool isSearching;

  const UserSearchLoaded({
    required this.filteredUsers,
    this.isSearching = false,
  });

  UserSearchLoaded copyWith({
    List<Map<String, dynamic>>? filteredUsers,
    bool? isSearching,
  }) {
    return UserSearchLoaded(
      filteredUsers: filteredUsers ?? this.filteredUsers,
      isSearching: isSearching ?? this.isSearching,
    );
  }

  @override
  List<Object?> get props => [
        filteredUsers,
        isSearching,
      ];
}

class UserSearchError extends UserSearchState {
  final String message;

  const UserSearchError(this.message);

  @override
  List<Object?> get props => [message];
}
