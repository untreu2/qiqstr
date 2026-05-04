import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../data/services/rust_nostr_bridge.dart';
import '../../ui/screens/auth/welcome_page.dart';
import '../../ui/screens/auth/login_page.dart';
import '../../ui/screens/auth/signup_page.dart';
import '../../ui/screens/auth/edit_new_account_profile.dart';
import '../../ui/screens/settings/keys_info_page.dart';
import '../../ui/screens/home_navigator.dart';
import '../../ui/screens/profile/profile_page.dart';
import '../../ui/screens/profile/following_page.dart';
import '../../ui/screens/profile/suggested_follows_page.dart';
import '../../ui/screens/onboarding/onboarding_spark_page.dart';
import '../../ui/screens/profile/edit_profile.dart';
import '../../ui/screens/note/feed_page.dart';
import '../../ui/screens/note/thread_page.dart';
import '../../ui/screens/note/note_statistics_page.dart';
import '../../ui/screens/note/quotes_page.dart';
import '../../ui/screens/settings/settings_page.dart';
import '../../ui/screens/settings/keys_page.dart';
import '../../ui/screens/settings/relay_page.dart';
import '../../ui/screens/settings/database_page.dart';
import '../../ui/screens/settings/display_page.dart';
import '../../ui/screens/settings/payments_page.dart';
import '../../ui/screens/settings/muted_page.dart';
import '../../ui/screens/bookmark/bookmark_page.dart';
import '../../ui/screens/settings/event_manager_page.dart';
import '../../ui/screens/dm/dm_conversations_page.dart';
import '../../ui/screens/dm/dm_chat_page.dart';
import '../../ui/screens/wallet/wallet_page.dart';
import '../../ui/screens/wallet/receive_page.dart';
import '../../ui/screens/notification/notification_page.dart';
import '../../ui/screens/explore/explore_page.dart';
import '../../ui/screens/article/article_detail_page.dart';
import '../../ui/screens/follow_set/follow_sets_page.dart';
import '../../ui/screens/follow_set/follow_set_detail_page.dart';
import '../../core/di/app_di.dart';
import '../../data/services/auth_service.dart';

class AppRouter {
  static final _hexRegExp = RegExp(r'^[0-9a-fA-F]{64}$');

  static bool _isValidHexId(String id) => _hexRegExp.hasMatch(id);

  static String _extractNoteId(GoRouterState state) {
    final queryNoteId = state.uri.queryParameters['noteId'];
    final extra = state.extra;
    if (queryNoteId != null && queryNoteId.isNotEmpty) return queryNoteId;
    if (extra is String && extra.isNotEmpty) return extra;
    if (extra is Map<String, dynamic>) {
      return extra['id']?.toString() ?? '';
    }
    return '';
  }

  static Widget _buildNoteStatisticsPage(BuildContext context, GoRouterState state) {
    final noteId = _extractNoteId(state);
    if (noteId.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) context.pop();
      });
      return const SizedBox.shrink();
    }
    return NoteStatisticsPage(noteId: noteId);
  }

  static String _normalizeToHex(String? pubkey) {
    if (pubkey == null || pubkey.isEmpty) return '';
    if (pubkey.startsWith('npub1')) {
      try {
        return decodeBasicBech32(pubkey, 'npub');
      } catch (e) {
        return pubkey;
      }
    }
    return pubkey;
  }

  static String _resolveProfileHex(GoRouterState state) {
    final pubkeyParam = state.uri.queryParameters['pubkey'] ?? '';
    final npubParam = state.uri.queryParameters['npub'] ?? '';
    final fromPubkey = _normalizeToHex(pubkeyParam.isNotEmpty ? pubkeyParam : null);
    if (fromPubkey.isNotEmpty && _isValidHexId(fromPubkey)) return fromPubkey;
    if (npubParam.isNotEmpty) return _normalizeToHex(npubParam);
    return fromPubkey;
  }

  static String _resolveFollowingHex(GoRouterState state) {
    final pubkeyParam = state.uri.queryParameters['pubkey'] ?? '';
    final npubParam = state.uri.queryParameters['npub'] ?? '';
    String pubkeyHex =
        pubkeyParam.isNotEmpty ? pubkeyParam : npubParam;
    if (pubkeyHex.isEmpty && state.extra is Map<String, dynamic>) {
      pubkeyHex =
          (state.extra as Map<String, dynamic>)['pubkey'] as String? ?? '';
    }
    return _normalizeToHex(pubkeyHex);
  }

  static final GoRouter router = GoRouter(
    initialLocation: '/welcome',
    redirect: _handleRedirect,
    routes: [
      GoRoute(
        path: '/keys-info',
        name: 'keys-info',
        builder: (context, state) {
          final npub = state.uri.queryParameters['npub'] ?? '';
          final extra = state.extra as Map<String, String>?;
          final mnemonic = extra?['mnemonic'] ?? '';
          return KeysInfoPage(npub: npub, mnemonic: mnemonic);
        },
      ),
      GoRoute(
        path: '/profile-setup',
        name: 'profile-setup',
        builder: (context, state) {
          final npub = state.uri.queryParameters['npub'] ?? '';
          return EditNewAccountProfilePage(npub: npub);
        },
      ),
      GoRoute(
        path: '/suggested-follows',
        name: 'suggested-follows',
        builder: (context, state) {
          final npub = state.uri.queryParameters['npub'] ?? '';
          return SuggestedFollowsPage(npub: npub);
        },
      ),
      GoRoute(
        path: '/onboarding-spark',
        name: 'onboarding-spark',
        builder: (context, state) {
          final npub = state.uri.queryParameters['npub'] ?? '';
          return OnboardingSparkPage(npub: npub);
        },
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          final location = state.uri.toString();
          final uri = Uri.parse(location);
          final npub = uri.queryParameters['npub'] ?? '';
          return HomeNavigator(
            key: ValueKey('home_$npub'),
            npub: npub,
            navigationShell: navigationShell,
          );
        },
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/home/feed',
                name: 'feed',
                builder: (context, state) {
                  final location = state.uri.toString();
                  final uri = Uri.parse(location);
                  final userHex = _normalizeToHex(uri.queryParameters['npub']);
                  final hashtag = uri.queryParameters['hashtag'];
                  return FeedPage(
                    key: ValueKey('feed_$userHex'),
                    userHex: userHex,
                    hashtag: hashtag,
                  );
                },
                routes: [
                  GoRoute(
                    path: 'profile',
                    name: 'feed-profile',
                    builder: (context, state) {
                      final pubkeyHex = _resolveProfileHex(state);
                      return ProfilePage(pubkeyHex: pubkeyHex);
                    },
                  ),
                  GoRoute(
                    path: 'thread/:chain',
                    name: 'feed-thread',
                    builder: (context, state) {
                      final chain = state.pathParameters['chain'] ?? '';
                      final initialNoteData =
                          state.extra as Map<String, dynamic>?;
                      return ThreadPage(
                        chain: chain,
                        initialNoteData: initialNoteData,
                      );
                    },
                  ),
                  GoRoute(
                    path: 'quotes',
                    name: 'feed-quotes',
                    builder: (context, state) {
                      final noteId = state.uri.queryParameters['noteId'] ?? '';
                      return QuotesPage(noteId: noteId);
                    },
                  ),
                  GoRoute(
                    path: 'note-statistics',
                    name: 'feed-note-statistics',
                    builder: _buildNoteStatisticsPage,
                  ),
                  GoRoute(
                    path: 'following',
                    name: 'feed-following',
                    builder: (context, state) {
                      final pubkeyHex = _resolveFollowingHex(state);
                      return FollowingPage(pubkeyHex: pubkeyHex);
                    },
                  ),
                  GoRoute(
                    path: 'explore',
                    name: 'feed-explore',
                    builder: (context, state) => const ExplorePage(),
                    routes: [
                      GoRoute(
                        path: 'article',
                        name: 'feed-explore-article',
                        builder: (context, state) {
                          final articleId =
                              state.uri.queryParameters['articleId'] ?? '';
                          return ArticleDetailPage(articleId: articleId);
                        },
                      ),
                    ],
                  ),
                  GoRoute(
                    path: 'article',
                    name: 'feed-article',
                    builder: (context, state) {
                      final articleId =
                          state.uri.queryParameters['articleId'] ?? '';
                      return ArticleDetailPage(articleId: articleId);
                    },
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/home/dm',
                name: 'dm-tab',
                builder: (context, state) => const DmConversationsPage(),
                routes: [
                  GoRoute(
                    path: 'chat',
                    name: 'dm-tab-chat',
                    builder: (context, state) {
                      final pubkeyHex = _normalizeToHex(
                          state.uri.queryParameters['pubkey'] ?? '');
                      return DmChatPage(pubkeyHex: pubkeyHex);
                    },
                  ),
                  GoRoute(
                    path: 'profile',
                    name: 'dm-profile',
                    builder: (context, state) {
                      final pubkeyHex = _resolveProfileHex(state);
                      return ProfilePage(pubkeyHex: pubkeyHex);
                    },
                  ),
                  GoRoute(
                    path: 'thread/:chain',
                    name: 'dm-thread',
                    builder: (context, state) {
                      final chain = state.pathParameters['chain'] ?? '';
                      final initialNoteData =
                          state.extra as Map<String, dynamic>?;
                      return ThreadPage(
                        chain: chain,
                        initialNoteData: initialNoteData,
                      );
                    },
                  ),
                  GoRoute(
                    path: 'note-statistics',
                    name: 'dm-note-statistics',
                    builder: _buildNoteStatisticsPage,
                  ),
                  GoRoute(
                    path: 'quotes',
                    name: 'dm-quotes',
                    builder: (context, state) {
                      final noteId =
                          state.uri.queryParameters['noteId'] ?? '';
                      return QuotesPage(noteId: noteId);
                    },
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/home/wallet',
                name: 'wallet',
                builder: (context, state) => const WalletPage(),
                routes: [
                  GoRoute(
                    path: 'receive',
                    name: 'wallet-receive',
                    builder: (context, state) {
                      final lud16 = state.uri.queryParameters['lud16'];
                      return ReceivePage(lud16: lud16);
                    },
                  ),
                  GoRoute(
                    path: 'profile',
                    name: 'wallet-profile',
                    builder: (context, state) {
                      final pubkeyHex = _resolveProfileHex(state);
                      return ProfilePage(pubkeyHex: pubkeyHex);
                    },
                  ),
                  GoRoute(
                    path: 'thread/:chain',
                    name: 'wallet-thread',
                    builder: (context, state) {
                      final chain = state.pathParameters['chain'] ?? '';
                      final initialNoteData =
                          state.extra as Map<String, dynamic>?;
                      return ThreadPage(
                        chain: chain,
                        initialNoteData: initialNoteData,
                      );
                    },
                  ),
                  GoRoute(
                    path: 'note-statistics',
                    name: 'wallet-note-statistics',
                    builder: _buildNoteStatisticsPage,
                  ),
                  GoRoute(
                    path: 'quotes',
                    name: 'wallet-quotes',
                    builder: (context, state) {
                      final noteId =
                          state.uri.queryParameters['noteId'] ?? '';
                      return QuotesPage(noteId: noteId);
                    },
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/home/notifications',
                name: 'notifications',
                builder: (context, state) => const NotificationPage(),
                routes: [
                  GoRoute(
                    path: 'profile',
                    name: 'notifications-profile',
                    builder: (context, state) {
                      final pubkeyHex = _resolveProfileHex(state);
                      return ProfilePage(pubkeyHex: pubkeyHex);
                    },
                  ),
                  GoRoute(
                    path: 'thread/:chain',
                    name: 'notifications-thread',
                    builder: (context, state) {
                      final chain = state.pathParameters['chain'] ?? '';
                      final initialNoteData =
                          state.extra as Map<String, dynamic>?;
                      return ThreadPage(
                        chain: chain,
                        initialNoteData: initialNoteData,
                      );
                    },
                  ),
                  GoRoute(
                    path: 'quotes',
                    name: 'notifications-quotes',
                    builder: (context, state) {
                      final noteId = state.uri.queryParameters['noteId'] ?? '';
                      return QuotesPage(noteId: noteId);
                    },
                  ),
                  GoRoute(
                    path: 'note-statistics',
                    name: 'notifications-note-statistics',
                    builder: _buildNoteStatisticsPage,
                  ),
                  GoRoute(
                    path: 'following',
                    name: 'notifications-following',
                    builder: (context, state) {
                      final pubkeyHex = _resolveFollowingHex(state);
                      return FollowingPage(pubkeyHex: pubkeyHex);
                    },
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/profile',
        name: 'profile',
        builder: (context, state) {
          final pubkeyHex = _resolveProfileHex(state);
          return ProfilePage(pubkeyHex: pubkeyHex);
        },
      ),
      GoRoute(
        path: '/thread/:chain',
        name: 'thread',
        builder: (context, state) {
          final chain = state.pathParameters['chain'] ?? '';
          final initialNoteData = state.extra as Map<String, dynamic>?;
          return ThreadPage(
            chain: chain,
            initialNoteData: initialNoteData,
          );
        },
      ),
      GoRoute(
        path: '/quotes',
        name: 'quotes',
        builder: (context, state) {
          final noteId = state.uri.queryParameters['noteId'] ?? '';
          return QuotesPage(noteId: noteId);
        },
      ),
      GoRoute(
        path: '/note-statistics',
        name: 'note-statistics',
        builder: _buildNoteStatisticsPage,
      ),
      GoRoute(
        path: '/following',
        name: 'following',
        builder: (context, state) {
          final pubkeyHex = _resolveFollowingHex(state);
          return FollowingPage(pubkeyHex: pubkeyHex);
        },
      ),
      GoRoute(
        path: '/edit-profile',
        name: 'edit-profile',
        builder: (context, state) {
          return const EditOwnProfilePage();
        },
      ),
      GoRoute(
        path: '/settings',
        name: 'settings',
        builder: (context, state) => const SettingsPage(),
      ),
      GoRoute(
        path: '/keys',
        name: 'keys',
        builder: (context, state) => const KeysPage(),
      ),
      GoRoute(
        path: '/relays',
        name: 'relays',
        builder: (context, state) => const RelayPage(),
      ),
      GoRoute(
        path: '/database',
        name: 'database',
        builder: (context, state) => const DatabasePage(),
      ),
      GoRoute(
        path: '/display',
        name: 'display',
        builder: (context, state) => const DisplayPage(),
      ),
      GoRoute(
        path: '/payments',
        name: 'payments',
        builder: (context, state) => const PaymentsPage(),
      ),
      GoRoute(
        path: '/muted',
        name: 'muted',
        builder: (context, state) => const MutedPage(),
      ),
      GoRoute(
        path: '/bookmarks',
        name: 'bookmarks',
        builder: (context, state) => const BookmarkPage(),
      ),
      GoRoute(
        path: '/follow-sets',
        name: 'follow-sets',
        builder: (context, state) => const FollowSetsPage(),
      ),
      GoRoute(
        path: '/follow-set-detail',
        name: 'follow-set-detail',
        builder: (context, state) {
          final dTag = state.uri.queryParameters['dTag'] ?? '';
          final pubkey = state.uri.queryParameters['pubkey'];
          return FollowSetDetailPage(dTag: dTag, ownerPubkey: pubkey);
        },
      ),
      GoRoute(
        path: '/event-manager',
        name: 'event-manager',
        builder: (context, state) => const EventManagerPage(),
      ),
      GoRoute(
        path: '/welcome',
        name: 'welcome',
        builder: (context, state) {
          final isAddAccount =
              state.uri.queryParameters['addAccount'] == 'true';
          return WelcomePage(isAddAccount: isAddAccount);
        },
      ),
      GoRoute(
        path: '/login',
        name: 'login',
        builder: (context, state) {
          final isAddAccount =
              state.uri.queryParameters['addAccount'] == 'true';
          return LoginPage(isAddAccount: isAddAccount);
        },
      ),
      GoRoute(
        path: '/signup',
        name: 'signup',
        builder: (context, state) => const SignupPage(),
      ),
      GoRoute(
        path: '/article',
        name: 'article',
        builder: (context, state) {
          final articleId = state.uri.queryParameters['articleId'] ?? '';
          return ArticleDetailPage(articleId: articleId);
        },
      ),
    ],
  );

  static Future<String?> _handleRedirect(
      BuildContext context, GoRouterState state) async {
    final authService = AppDI.get<AuthService>();

    final cachedNpub = authService.currentUserNpub;
    final isAuthenticated = cachedNpub != null && cachedNpub.isNotEmpty;

    final isWelcomeRoute = state.matchedLocation == '/welcome';
    final isLoginRoute = state.matchedLocation == '/login';
    final isSignupRoute = state.matchedLocation == '/signup';
    final isKeysInfoRoute = state.matchedLocation == '/keys-info';
    final isProfileSetupRoute = state.matchedLocation == '/profile-setup';
    final isSuggestedFollowsRoute =
        state.matchedLocation == '/suggested-follows';
    final isOnboardingSparkRoute =
        state.matchedLocation == '/onboarding-spark';

    final isAuthFlow = isWelcomeRoute ||
        isLoginRoute ||
        isSignupRoute ||
        isKeysInfoRoute ||
        isProfileSetupRoute ||
        isSuggestedFollowsRoute ||
        isOnboardingSparkRoute;

    if (!isAuthenticated && !isAuthFlow) {
      final isAuthResult = await authService.isAuthenticated();
      final isAuthenticatedFull =
          isAuthResult.isSuccess && isAuthResult.data == true;
      if (!isAuthenticatedFull) return '/welcome';
    }

    if (isAuthenticated && (isWelcomeRoute || isLoginRoute || isSignupRoute)) {
      final isAddAccount = state.uri.queryParameters['addAccount'] == 'true';
      if (!isAddAccount && cachedNpub.isNotEmpty) {
        return '/home/feed?npub=${Uri.encodeComponent(cachedNpub)}';
      }
    }

    return null;
  }
}
