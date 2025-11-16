import '../../models/note_model.dart';

abstract class BaseFeedFilter {
  String get filterKey;
  
  int get limit => 500;
  
  List<NoteModel> apply(List<NoteModel> notes);
  
  bool accepts(NoteModel note);
  
  List<NoteModel> sort(List<NoteModel> notes) {
    notes.sort((a, b) {
      final aTime = a.isRepost ? (a.repostTimestamp ?? a.timestamp) : a.timestamp;
      final bTime = b.isRepost ? (b.repostTimestamp ?? b.timestamp) : b.timestamp;
      final result = bTime.compareTo(aTime);
      return result == 0 ? a.id.compareTo(b.id) : result;
    });
    return notes;
  }
}

class HomeFeedFilter extends BaseFeedFilter {
  final String currentUserNpub;
  final Set<String> followedUsers;
  final bool showReplies;
  
  HomeFeedFilter({
    required this.currentUserNpub,
    required this.followedUsers,
    this.showReplies = false,
  });
  
  @override
  String get filterKey => '$currentUserNpub-home-${followedUsers.length}';
  
  @override
  bool accepts(NoteModel note) {
    if (note.isRepost) {
      if (!followedUsers.contains(note.repostedBy)) {
        return false;
      }
    } else {
      if (!followedUsers.contains(note.author)) {
        return false;
      }
    }
    
    if (!showReplies && note.isReply && !note.isRepost) {
      return false;
    }
    
    return true;
  }
  
  @override
  List<NoteModel> apply(List<NoteModel> notes) {
    final filtered = notes.where(accepts).toList();
    return sort(filtered);
  }
}

class ProfileFeedFilter extends BaseFeedFilter {
  final String targetUserNpub;
  final String currentUserNpub;
  final bool showReplies;
  
  ProfileFeedFilter({
    required this.targetUserNpub,
    required this.currentUserNpub,
    this.showReplies = false,
  });
  
  @override
  String get filterKey => '$currentUserNpub-profile-$targetUserNpub';
  
  @override
  int get limit => 200;
  
  @override
  bool accepts(NoteModel note) {
    if (note.isRepost) {
      if (note.repostedBy != targetUserNpub) {
        return false;
      }
    } else {
      if (note.author != targetUserNpub) {
        return false;
      }
    }
    
    if (!showReplies && note.isReply && !note.isRepost) {
      return false;
    }
    
    return true;
  }
  
  @override
  List<NoteModel> apply(List<NoteModel> notes) {
    final filtered = notes.where(accepts).toList();
    return sort(filtered);
  }
}

class ProfileRepliesFilter extends BaseFeedFilter {
  final String targetUserNpub;
  final String currentUserNpub;
  
  ProfileRepliesFilter({
    required this.targetUserNpub,
    required this.currentUserNpub,
  });
  
  @override
  String get filterKey => '$currentUserNpub-profile-replies-$targetUserNpub';
  
  @override
  int get limit => 200;
  
  @override
  bool accepts(NoteModel note) {
    if (note.isRepost) {
      return false;
    }
    
    if (note.author != targetUserNpub) {
      return false;
    }
    
    if (!note.isReply) {
      return false;
    }
    
    return true;
  }
  
  @override
  List<NoteModel> apply(List<NoteModel> notes) {
    final filtered = notes.where(accepts).toList();
    return sort(filtered);
  }
}

class HashtagFilter extends BaseFeedFilter {
  final String hashtag;
  final String currentUserNpub;
  
  HashtagFilter({
    required this.hashtag,
    required this.currentUserNpub,
  });
  
  @override
  String get filterKey => '$currentUserNpub-hashtag-${hashtag.toLowerCase()}';
  
  @override
  int get limit => 100;
  
  @override
  bool accepts(NoteModel note) {
    final targetHashtag = hashtag.toLowerCase();
    
    if (note.tTags.isNotEmpty) {
      return note.tTags.contains(targetHashtag);
    }
    
    final content = note.content.toLowerCase();
    final hashtagRegex = RegExp(r'#(\w+)');
    final matches = hashtagRegex.allMatches(content);
    
    for (final match in matches) {
      final extractedHashtag = match.group(1)?.toLowerCase();
      if (extractedHashtag == targetHashtag) {
        return true;
      }
    }
    
    return false;
  }
  
  @override
  List<NoteModel> apply(List<NoteModel> notes) {
    final filtered = notes.where(accepts).toList();
    return sort(filtered);
  }
}

class GlobalFeedFilter extends BaseFeedFilter {
  final String currentUserNpub;
  final bool showReplies;
  
  GlobalFeedFilter({
    required this.currentUserNpub,
    this.showReplies = false,
  });
  
  @override
  String get filterKey => '$currentUserNpub-global';
  
  @override
  int get limit => 100;
  
  @override
  bool accepts(NoteModel note) {
    if (!showReplies && note.isReply && !note.isRepost) {
      return false;
    }
    
    return true;
  }
  
  @override
  List<NoteModel> apply(List<NoteModel> notes) {
    final filtered = notes.where(accepts).toList();
    return sort(filtered);
  }
}

