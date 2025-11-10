import 'dart:async';
import '../utils/string_optimizer.dart';
import 'reaction_model.dart';
import 'zap_model.dart';
import 'user_model.dart';

class NoteModel {
  final String id;
  final String content;
  final String author;
  final DateTime timestamp;
  final bool isRepost;
  final String? repostedBy;
  final DateTime? repostTimestamp;
  int repostCount;
  final String? rawWs;
  int reactionCount;
  int replyCount;
  bool hasMedia;
  double? estimatedHeight;
  bool isVideo;
  String? videoUrl;
  int zapAmount;
  final bool isReply;
  final String? parentId;
  final String? rootId;
  List<String> replyIds;
  List<Map<String, String>> eTags;
  List<Map<String, String>> pTags;
  String? replyMarker;
  
  UserModel? authorUser;
  UserModel? reposterUser;

  static final Map<String, Map<String, dynamic>> _globalParseCache = {};
  static const int _maxCacheSize = 500;

  final List<NoteModel> _replies = [];
  final Map<String, List<ReactionModel>> _reactions = {};
  final List<NoteModel> _boosts = [];
  final List<ZapModel> _zaps = [];
  
  final _repliesController = StreamController<List<NoteModel>>.broadcast();
  final _reactionsController = StreamController<Map<String, List<ReactionModel>>>.broadcast();
  final _boostsController = StreamController<List<NoteModel>>.broadcast();
  final _zapsController = StreamController<List<ZapModel>>.broadcast();

  Stream<List<NoteModel>> get repliesStream => _repliesController.stream;
  Stream<Map<String, List<ReactionModel>>> get reactionsStream => _reactionsController.stream;
  Stream<List<NoteModel>> get boostsStream => _boostsController.stream;
  Stream<List<ZapModel>> get zapsStream => _zapsController.stream;

  List<NoteModel> get replies => List.unmodifiable(_replies);
  Map<String, List<ReactionModel>> get reactions => Map.unmodifiable(_reactions);
  List<NoteModel> get boosts => List.unmodifiable(_boosts);
  List<ZapModel> get zaps => List.unmodifiable(_zaps);

  NoteModel({
    required this.id,
    required this.content,
    required this.author,
    required this.timestamp,
    this.isRepost = false,
    this.repostedBy,
    this.repostTimestamp,
    this.repostCount = 0,
    this.rawWs,
    this.reactionCount = 0,
    this.replyCount = 0,
    this.hasMedia = false,
    this.estimatedHeight,
    this.isVideo = false,
    this.videoUrl,
    this.zapAmount = 0,
    this.isReply = false,
    this.parentId,
    this.rootId,
    List<String>? replyIds,
    List<Map<String, String>>? eTags,
    List<Map<String, String>>? pTags,
    this.replyMarker,
    this.authorUser,
    this.reposterUser,
  })  : replyIds = replyIds ?? [],
        eTags = eTags ?? [],
        pTags = pTags ?? [];

  void addReply(NoteModel reply) {
    if (!_replies.any((r) => r.id == reply.id)) {
      _replies.add(reply);
      replyCount = _replies.length;
      _repliesController.add(List.unmodifiable(_replies));
    }
  }

  void removeReply(NoteModel reply) {
    final initialLength = _replies.length;
    _replies.removeWhere((r) => r.id == reply.id);
    if (_replies.length < initialLength) {
      replyCount = _replies.length;
      _repliesController.add(List.unmodifiable(_replies));
    }
  }

  void addReaction(ReactionModel reaction) {
    final emoji = reaction.content.isEmpty ? '+' : reaction.content;
    
    final reactionList = _reactions.putIfAbsent(emoji, () => []);
    if (!reactionList.any((r) => r.id == reaction.id)) {
      reactionList.add(reaction);
      reactionCount = _reactions.values.fold(0, (sum, list) => sum + list.length);
      _reactionsController.add(Map.unmodifiable(_reactions));
    }
  }

  void removeReaction(ReactionModel reaction) {
    final emoji = reaction.content.isEmpty ? '+' : reaction.content;
    
    if (_reactions.containsKey(emoji)) {
      final initialLength = _reactions[emoji]!.length;
      _reactions[emoji]!.removeWhere((r) => r.id == reaction.id);
      if (_reactions[emoji]!.length < initialLength) {
        if (_reactions[emoji]!.isEmpty) {
          _reactions.remove(emoji);
        }
        reactionCount = _reactions.values.fold(0, (sum, list) => sum + list.length);
        _reactionsController.add(Map.unmodifiable(_reactions));
      }
    }
  }

  void addBoost(NoteModel boost) {
    if (!_boosts.any((b) => b.id == boost.id)) {
      _boosts.add(boost);
      repostCount = _boosts.length;
      _boostsController.add(List.unmodifiable(_boosts));
    }
  }

  void removeBoost(NoteModel boost) {
    final initialLength = _boosts.length;
    _boosts.removeWhere((b) => b.id == boost.id);
    if (_boosts.length < initialLength) {
      repostCount = _boosts.length;
      _boostsController.add(List.unmodifiable(_boosts));
    }
  }

  void addZap(ZapModel zap) {
    if (!_zaps.any((z) => z.id == zap.id)) {
      _zaps.add(zap);
      zapAmount = _zaps.fold(0, (sum, z) => sum + z.amount);
      _zapsController.add(List.unmodifiable(_zaps));
    }
  }

  void removeZap(ZapModel zap) {
    final initialLength = _zaps.length;
    _zaps.removeWhere((z) => z.id == zap.id);
    if (_zaps.length < initialLength) {
      zapAmount = _zaps.fold(0, (sum, z) => sum + z.amount);
      _zapsController.add(List.unmodifiable(_zaps));
    }
  }

  bool hasReactionBy(String userPubkey) {
    return _reactions.values.any(
      (reactionList) => reactionList.any((r) => r.author == userPubkey)
    );
  }

  String? getReactionBy(String userPubkey) {
    for (final entry in _reactions.entries) {
      if (entry.value.any((r) => r.author == userPubkey)) {
        return entry.key;
      }
    }
    return null;
  }

  bool isBoostedBy(String userPubkey) {
    return _boosts.any((b) => b.repostedBy == userPubkey);
  }

  bool isZappedBy(String userPubkey) {
    return _zaps.any((z) => z.sender == userPubkey);
  }

  void dispose() {
    _repliesController.close();
    _reactionsController.close();
    _boostsController.close();
    _zapsController.close();
  }

  Map<String, dynamic> get parsedContentLazy {
    if (_globalParseCache.containsKey(id)) {
      return _globalParseCache[id]!;
    }

    final parsed = _parseInternal();

    if (_globalParseCache.length >= _maxCacheSize) {
      final keysToRemove = _globalParseCache.keys.take(_maxCacheSize ~/ 5).toList();
      for (final key in keysToRemove) {
        _globalParseCache.remove(key);
      }
    }

    _globalParseCache[id] = parsed;
    return parsed;
  }

  static void clearParseCache() {
    _globalParseCache.clear();
  }

  bool get hasMediaLazy => (parsedContentLazy['mediaUrls'] as List).isNotEmpty;

  Map<String, dynamic> _parseInternal() {
    return stringOptimizer.parseContentOptimized(content);
  }

  @override
  bool operator ==(Object other) => identical(this, other) || other is NoteModel && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;

  factory NoteModel.fromJson(Map<String, dynamic> json) {
    return NoteModel(
      id: json['id'] as String,
      content: json['content'] as String,
      author: json['author'] as String,
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        (json['timestamp'] as int) * 1000,
      ),
      isRepost: json['isRepost'] as bool? ?? false,
      repostedBy: json['repostedBy'] as String?,
      repostTimestamp: json['repostTimestamp'] != null
          ? DateTime.fromMillisecondsSinceEpoch(
              (json['repostTimestamp'] as int) * 1000,
            )
          : null,
      repostCount: json['repostCount'] as int? ?? 0,
      rawWs: json['rawWs'] as String?,
      reactionCount: json['reactionCount'] as int? ?? 0,
      replyCount: json['replyCount'] as int? ?? 0,
      hasMedia: json['hasMedia'] as bool? ?? false,
      estimatedHeight: (json['estimatedHeight'] as num?)?.toDouble(),
      isVideo: json['isVideo'] as bool? ?? false,
      videoUrl: json['videoUrl'] as String?,
      zapAmount: json['zapAmount'] as int? ?? 0,
      isReply: json['isReply'] as bool? ?? false,
      parentId: json['parentId'] as String?,
      rootId: json['rootId'] as String?,
      replyIds: json['replyIds'] != null ? List<String>.from(json['replyIds']) : null,
      eTags: json['eTags'] != null ? List<Map<String, String>>.from(json['eTags'].map((tag) => Map<String, String>.from(tag))) : null,
      pTags: json['pTags'] != null ? List<Map<String, String>>.from(json['pTags'].map((tag) => Map<String, String>.from(tag))) : null,
      replyMarker: json['replyMarker'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'content': content,
      'author': author,
      'timestamp': timestamp.millisecondsSinceEpoch ~/ 1000,
      'isRepost': isRepost,
      'repostedBy': repostedBy,
      'repostTimestamp': repostTimestamp?.millisecondsSinceEpoch == null ? null : repostTimestamp!.millisecondsSinceEpoch ~/ 1000,
      'repostCount': repostCount,
      'rawWs': rawWs,
      'reactionCount': reactionCount,
      'replyCount': replyCount,
      'hasMedia': hasMedia,
      'estimatedHeight': estimatedHeight,
      'isVideo': isVideo,
      'videoUrl': videoUrl,
      'zapAmount': zapAmount,
      'isReply': isReply,
      'parentId': parentId,
      'rootId': rootId,
      'replyIds': replyIds,
      'eTags': eTags,
      'pTags': pTags,
      'replyMarker': replyMarker,
    };
  }
}
