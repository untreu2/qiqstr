import '../../../core/bloc/base/base_state.dart';

abstract class NoteState extends BaseState {
  const NoteState();
}

class NoteInitial extends NoteState {
  const NoteInitial();
}

class NoteLoading extends NoteState {
  const NoteLoading();
}

class NoteComposedSuccess extends NoteState {
  final Map<String, dynamic> note;

  const NoteComposedSuccess(this.note);

  @override
  List<Object?> get props => [note];
}

class NoteComposeState extends NoteState {
  final String content;
  final bool isReply;
  final bool isQuote;
  final String? rootId;
  final String? replyId;
  final String? parentAuthor;
  final String? quoteEventId;
  final List<String> mediaUrls;
  final bool isUploadingMedia;
  final bool isSearchingUsers;
  final List<Map<String, dynamic>> userSuggestions;
  final bool canPost;

  const NoteComposeState({
    required this.content,
    this.isReply = false,
    this.isQuote = false,
    this.rootId,
    this.replyId,
    this.parentAuthor,
    this.quoteEventId,
    this.mediaUrls = const [],
    this.isUploadingMedia = false,
    this.isSearchingUsers = false,
    this.userSuggestions = const [],
    this.canPost = false,
  });

  @override
  List<Object?> get props => [
        content,
        isReply,
        isQuote,
        rootId,
        replyId,
        parentAuthor,
        quoteEventId,
        mediaUrls,
        isUploadingMedia,
        isSearchingUsers,
        userSuggestions,
        canPost,
      ];

  NoteComposeState copyWith({
    String? content,
    bool? isReply,
    bool? isQuote,
    String? rootId,
    String? replyId,
    String? parentAuthor,
    String? quoteEventId,
    List<String>? mediaUrls,
    bool? isUploadingMedia,
    bool? isSearchingUsers,
    List<Map<String, dynamic>>? userSuggestions,
    bool? canPost,
  }) {
    return NoteComposeState(
      content: content ?? this.content,
      isReply: isReply ?? this.isReply,
      isQuote: isQuote ?? this.isQuote,
      rootId: rootId ?? this.rootId,
      replyId: replyId ?? this.replyId,
      parentAuthor: parentAuthor ?? this.parentAuthor,
      quoteEventId: quoteEventId ?? this.quoteEventId,
      mediaUrls: mediaUrls ?? this.mediaUrls,
      isUploadingMedia: isUploadingMedia ?? this.isUploadingMedia,
      isSearchingUsers: isSearchingUsers ?? this.isSearchingUsers,
      userSuggestions: userSuggestions ?? this.userSuggestions,
      canPost: canPost ?? this.canPost,
    );
  }
}

class NoteError extends NoteState {
  final String message;

  const NoteError(this.message);

  @override
  List<Object?> get props => [message];
}
