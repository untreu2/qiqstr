class CacheConfig {
  static const Duration profileTTL = Duration(hours: 24);
  static const Duration feedNoteTTL = Duration(days: 7);
  static const Duration notificationTTL = Duration(days: 30);
  static const Duration followingListTTL = Duration(hours: 6);
  static const Duration articleTTL = Duration(days: 14);

  static const int kindProfile = 0;
  static const int kindNote = 1;
  static const int kindFollowing = 3;
  static const int kindRepost = 6;
  static const int kindReaction = 7;
  static const int kindMuteList = 10000;
  static const int kindZap = 9735;
  static const int kindArticle = 30023;

  static bool isReplaceable(int kind) {
    return kind == 0 || kind == 3 || (kind >= 10000 && kind < 20000);
  }

  static bool isParameterizedReplaceable(int kind) {
    return kind >= 30000 && kind < 40000;
  }

  static bool isRegularEvent(int kind) {
    return !isReplaceable(kind) && !isParameterizedReplaceable(kind);
  }
}
