abstract class BaseFeedFilter {
  String get filterKey;
  
  int get limit => 500;
  
  List<Map<String, dynamic>> apply(List<Map<String, dynamic>> events);
  
  bool accepts(Map<String, dynamic> event);
  
  List<Map<String, dynamic>> sort(List<Map<String, dynamic>> events) {
    events.sort((a, b) {
      final aIsRepost = _isRepost(a);
      final bIsRepost = _isRepost(b);
      final aTime = aIsRepost ? _getRepostTimestamp(a) ?? _getTimestamp(a) : _getTimestamp(a);
      final bTime = bIsRepost ? _getRepostTimestamp(b) ?? _getTimestamp(b) : _getTimestamp(b);
      final result = bTime.compareTo(aTime);
      return result == 0 ? _getEventId(a).compareTo(_getEventId(b)) : result;
    });
    return events;
  }

  bool _isRepost(Map<String, dynamic> event) {
    return event['kind'] == 6;
  }

  DateTime _getTimestamp(Map<String, dynamic> event) {
    final createdAt = event['created_at'] as int? ?? 0;
    return DateTime.fromMillisecondsSinceEpoch(createdAt * 1000);
  }

  DateTime? _getRepostTimestamp(Map<String, dynamic> event) {
    if (!_isRepost(event)) return null;
    return _getTimestamp(event);
  }

  String _getEventId(Map<String, dynamic> event) {
    return event['id'] as String? ?? '';
  }

  String _getAuthor(Map<String, dynamic> event) {
    final author = event['author'] as String?;
    if (author != null && author.isNotEmpty) {
      return author;
    }
    return event['pubkey'] as String? ?? '';
  }

  String? _getRepostedBy(Map<String, dynamic> event) {
    if (!_isRepost(event)) return null;
    return _getAuthor(event);
  }

  bool _isReply(Map<String, dynamic> event) {
    final isReply = event['isReply'] as bool?;
    if (isReply != null) {
      return isReply;
    }
    final tags = event['tags'] as List<dynamic>? ?? [];
    for (final tag in tags) {
      if (tag is List && tag.isNotEmpty && tag[0] == 'e') {
        return true;
      }
    }
    return false;
  }

  List<String> _getTTags(Map<String, dynamic> event) {
    final tags = event['tags'] as List<dynamic>? ?? [];
    final result = <String>[];
    for (final tag in tags) {
      if (tag is List && tag.isNotEmpty && tag[0] == 't' && tag.length > 1) {
        result.add(tag[1].toString());
      }
    }
    return result;
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
  bool accepts(Map<String, dynamic> event) {
    final isRepost = _isRepost(event);
    if (isRepost) {
      final repostedBy = _getRepostedBy(event);
      if (repostedBy == null || !followedUsers.contains(repostedBy)) {
        return false;
      }
    } else {
      final author = _getAuthor(event);
      if (!followedUsers.contains(author)) {
        return false;
      }
    }
    
    if (!showReplies && _isReply(event) && !isRepost) {
      return false;
    }
    
    return true;
  }
  
  @override
  List<Map<String, dynamic>> apply(List<Map<String, dynamic>> events) {
    final filtered = events.where(accepts).toList();
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
  bool accepts(Map<String, dynamic> event) {
    final isRepost = _isRepost(event);
    if (isRepost) {
      final repostedBy = _getRepostedBy(event);
      if (repostedBy != targetUserNpub) {
        return false;
      }
    } else {
      final author = _getAuthor(event);
      if (author != targetUserNpub) {
        return false;
      }
    }
    
    if (!showReplies && _isReply(event) && !isRepost) {
      return false;
    }
    
    return true;
  }
  
  @override
  List<Map<String, dynamic>> apply(List<Map<String, dynamic>> events) {
    final filtered = events.where(accepts).toList();
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
  bool accepts(Map<String, dynamic> event) {
    if (_isRepost(event)) {
      return false;
    }
    
    final author = _getAuthor(event);
    if (author != targetUserNpub) {
      return false;
    }
    
    if (!_isReply(event)) {
      return false;
    }
    
    return true;
  }
  
  @override
  List<Map<String, dynamic>> apply(List<Map<String, dynamic>> events) {
    final filtered = events.where(accepts).toList();
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
  bool accepts(Map<String, dynamic> event) {
    final targetHashtag = hashtag.toLowerCase();
    
    final tTags = _getTTags(event);
    if (tTags.isNotEmpty) {
      return tTags.any((tag) => tag.toLowerCase() == targetHashtag);
    }
    
    final content = (event['content'] as String? ?? '').toLowerCase();
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
  List<Map<String, dynamic>> apply(List<Map<String, dynamic>> events) {
    final filtered = events.where(accepts).toList();
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
  bool accepts(Map<String, dynamic> event) {
    final isRepost = _isRepost(event);
    if (!showReplies && _isReply(event) && !isRepost) {
      return false;
    }
    
    return true;
  }
  
  @override
  List<Map<String, dynamic>> apply(List<Map<String, dynamic>> events) {
    final filtered = events.where(accepts).toList();
    return sort(filtered);
  }
}

