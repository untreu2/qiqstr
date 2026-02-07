import '../../../core/bloc/base/base_event.dart';

abstract class NoteEvent extends BaseEvent {
  const NoteEvent();
}

class NoteComposed extends NoteEvent {
  final String content;
  final String? replyToId;
  final String? rootId;
  final String? parentAuthor;
  final String? quoteEventId;
  final List<String>? mentions;
  final List<String>? relayUrls;
  final List<List<String>>? tags;

  const NoteComposed({
    required this.content,
    this.replyToId,
    this.rootId,
    this.parentAuthor,
    this.quoteEventId,
    this.mentions,
    this.relayUrls,
    this.tags,
  });

  @override
  List<Object?> get props => [
        content,
        replyToId,
        rootId,
        parentAuthor,
        quoteEventId,
        mentions,
        relayUrls,
        tags,
      ];
}

class NoteContentChanged extends NoteEvent {
  final String content;

  const NoteContentChanged(this.content);

  @override
  List<Object?> get props => [content];
}

class NoteMediaUploaded extends NoteEvent {
  final List<String> filePaths;

  const NoteMediaUploaded(this.filePaths);

  @override
  List<Object?> get props => [filePaths];
}

class NoteMediaRemoved extends NoteEvent {
  final String url;

  const NoteMediaRemoved(this.url);

  @override
  List<Object?> get props => [url];
}

class NoteMentionAdded extends NoteEvent {
  final MentionParams params;

  const NoteMentionAdded(this.params);

  @override
  List<Object?> get props => [params];
}

class NoteContentCleared extends NoteEvent {
  const NoteContentCleared();
}

class NoteUserSearchRequested extends NoteEvent {
  final String query;

  const NoteUserSearchRequested(this.query);

  @override
  List<Object?> get props => [query];
}

class NoteReplySetup extends NoteEvent {
  final String rootId;
  final String? replyId;
  final String parentAuthor;

  const NoteReplySetup({
    required this.rootId,
    this.replyId,
    required this.parentAuthor,
  });

  @override
  List<Object?> get props => [rootId, replyId, parentAuthor];
}

class NoteQuoteSetup extends NoteEvent {
  final String quoteEventId;

  const NoteQuoteSetup(this.quoteEventId);

  @override
  List<Object?> get props => [quoteEventId];
}

class MentionParams {
  final String name;
  final int startIndex;

  const MentionParams({
    required this.name,
    required this.startIndex,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MentionParams &&
          runtimeType == other.runtimeType &&
          name == other.name &&
          startIndex == other.startIndex;

  @override
  int get hashCode => name.hashCode ^ startIndex.hashCode;
}
