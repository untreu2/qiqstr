import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:nostr_nip19/nostr_nip19.dart';
import '../../ui/screens/auth/login_page.dart';
import '../../ui/screens/auth/edit_new_account_profile.dart';
import '../../ui/screens/settings/keys_info_page.dart';
import '../../ui/screens/home_navigator.dart';
import '../../ui/screens/profile/profile_page.dart';
import '../../ui/screens/profile/following_page.dart';
import '../../ui/screens/profile/suggested_follows_page.dart';
import '../../ui/screens/profile/edit_profile.dart';
import '../../ui/screens/note/feed_page.dart';
import '../../ui/screens/note/thread_page.dart';
import '../../ui/screens/note/note_statistics_page.dart';
import '../../ui/screens/settings/settings_page.dart';
import '../../ui/screens/settings/keys_page.dart';
import '../../ui/screens/settings/relay_page.dart';
import '../../ui/screens/settings/display_page.dart';
import '../../ui/screens/settings/payments_page.dart';
import '../../ui/screens/settings/muted_page.dart';
import '../../ui/screens/settings/event_manager_page.dart';
import '../../ui/screens/webview/webview_page.dart';
import '../../ui/screens/dm/dm_page.dart';
import '../../ui/screens/wallet/wallet_page.dart';
import '../../ui/screens/notification/notification_page.dart';
import '../../models/user_model.dart';
import '../../models/note_model.dart';
import '../../core/di/app_di.dart';
import '../../data/services/auth_service.dart';

class AppRouter {
  static final GoRouter router = GoRouter(
    initialLocation: '/login',
    redirect: _handleRedirect,
    routes: [
      GoRoute(
        path: '/login',
        name: 'login',
        builder: (context, state) => const LoginPage(),
      ),
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
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          final location = state.uri.toString();
          final uri = Uri.parse(location);
          final npub = uri.queryParameters['npub'] ?? '';
          return HomeNavigator(
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
                  final npub = uri.queryParameters['npub'] ?? '';
                  final hashtag = uri.queryParameters['hashtag'];
                  return FeedPage(npub: npub, hashtag: hashtag);
                },
                routes: [
                  GoRoute(
                    path: 'profile',
                    name: 'feed-profile',
                    builder: (context, state) {
                      final npubParam = state.uri.queryParameters['npub'] ?? '';
                      final pubkeyHexParam = state.uri.queryParameters['pubkeyHex'] ?? '';
                      String pubkeyHex;
                      if (pubkeyHexParam.isNotEmpty) {
                        pubkeyHex = pubkeyHexParam;
                        if (pubkeyHex.startsWith('npub1')) {
                          try {
                            pubkeyHex = decodeBasicBech32(pubkeyHex, 'npub');
                          } catch (e) {
                            pubkeyHex = pubkeyHexParam;
                          }
                        }
                      } else if (npubParam.isNotEmpty) {
                        if (npubParam.startsWith('npub1')) {
                          try {
                            pubkeyHex = decodeBasicBech32(npubParam, 'npub');
                          } catch (e) {
                            pubkeyHex = npubParam;
                          }
                        } else {
                          pubkeyHex = npubParam;
                        }
                      } else {
                        pubkeyHex = '';
                      }
                      final displayName = pubkeyHex.length > 8 ? pubkeyHex.substring(0, 8) : pubkeyHex;
                      final user = UserModel.create(
                        pubkeyHex: pubkeyHex,
                        name: displayName,
                        about: '',
                        profileImage: '',
                        banner: '',
                        website: '',
                        nip05: '',
                        lud16: '',
                        updatedAt: DateTime.now(),
                        nip05Verified: false,
                      );
                      return ProfilePage(user: user);
                    },
                  ),
                  GoRoute(
                    path: 'thread',
                    name: 'feed-thread',
                    builder: (context, state) {
                      final rootNoteId = state.uri.queryParameters['rootNoteId'] ?? '';
                      final focusedNoteId = state.uri.queryParameters['focusedNoteId'];
                      return ThreadPage(
                        rootNoteId: rootNoteId,
                        focusedNoteId: focusedNoteId,
                      );
                    },
                  ),
                  GoRoute(
                    path: 'note-statistics',
                    name: 'feed-note-statistics',
                    builder: (context, state) {
                      final note = state.extra as NoteModel?;
                      if (note == null) {
                        return const Scaffold(
                          body: Center(child: Text('Note not found')),
                        );
                      }
                      return NoteStatisticsPage(note: note);
                    },
                  ),
                  GoRoute(
                    path: 'following',
                    name: 'feed-following',
                    builder: (context, state) {
                      final user = state.extra as UserModel?;
                      if (user == null) {
                        final npub = state.uri.queryParameters['npub'] ?? '';
                        final pubkeyHex = state.uri.queryParameters['pubkeyHex'] ?? npub;
                        final defaultUser = UserModel.create(
                          pubkeyHex: pubkeyHex,
                          name: pubkeyHex.length > 8 ? pubkeyHex.substring(0, 8) : pubkeyHex,
                        );
                        return FollowingPage(user: defaultUser);
                      }
                      return FollowingPage(user: user);
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
                name: 'dm',
                builder: (context, state) => const DmPage(),
                routes: [
                  GoRoute(
                    path: 'profile',
                    name: 'dm-profile',
                    builder: (context, state) {
                      final npubParam = state.uri.queryParameters['npub'] ?? '';
                      final pubkeyHexParam = state.uri.queryParameters['pubkeyHex'] ?? '';
                      String pubkeyHex;
                      if (pubkeyHexParam.isNotEmpty) {
                        pubkeyHex = pubkeyHexParam;
                        if (pubkeyHex.startsWith('npub1')) {
                          try {
                            pubkeyHex = decodeBasicBech32(pubkeyHex, 'npub');
                          } catch (e) {
                            pubkeyHex = pubkeyHexParam;
                          }
                        }
                      } else if (npubParam.isNotEmpty) {
                        if (npubParam.startsWith('npub1')) {
                          try {
                            pubkeyHex = decodeBasicBech32(npubParam, 'npub');
                          } catch (e) {
                            pubkeyHex = npubParam;
                          }
                        } else {
                          pubkeyHex = npubParam;
                        }
                      } else {
                        pubkeyHex = '';
                      }
                      final displayName = pubkeyHex.length > 8 ? pubkeyHex.substring(0, 8) : pubkeyHex;
                      final user = UserModel.create(
                        pubkeyHex: pubkeyHex,
                        name: displayName,
                        about: '',
                        profileImage: '',
                        banner: '',
                        website: '',
                        nip05: '',
                        lud16: '',
                        updatedAt: DateTime.now(),
                        nip05Verified: false,
                      );
                      return ProfilePage(user: user);
                    },
                  ),
                  GoRoute(
                    path: 'note-statistics',
                    name: 'dm-note-statistics',
                    builder: (context, state) {
                      final note = state.extra as NoteModel?;
                      if (note == null) {
                        return const Scaffold(
                          body: Center(child: Text('Note not found')),
                        );
                      }
                      return NoteStatisticsPage(note: note);
                    },
                  ),
                  GoRoute(
                    path: 'following',
                    name: 'dm-following',
                    builder: (context, state) {
                      final user = state.extra as UserModel?;
                      if (user == null) {
                        final npub = state.uri.queryParameters['npub'] ?? '';
                        final pubkeyHex = state.uri.queryParameters['pubkeyHex'] ?? npub;
                        final defaultUser = UserModel.create(
                          pubkeyHex: pubkeyHex,
                          name: pubkeyHex.length > 8 ? pubkeyHex.substring(0, 8) : pubkeyHex,
                        );
                        return FollowingPage(user: defaultUser);
                      }
                      return FollowingPage(user: user);
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
                      final npubParam = state.uri.queryParameters['npub'] ?? '';
                      final pubkeyHexParam = state.uri.queryParameters['pubkeyHex'] ?? '';
                      String pubkeyHex;
                      if (pubkeyHexParam.isNotEmpty) {
                        pubkeyHex = pubkeyHexParam;
                        if (pubkeyHex.startsWith('npub1')) {
                          try {
                            pubkeyHex = decodeBasicBech32(pubkeyHex, 'npub');
                          } catch (e) {
                            pubkeyHex = pubkeyHexParam;
                          }
                        }
                      } else if (npubParam.isNotEmpty) {
                        if (npubParam.startsWith('npub1')) {
                          try {
                            pubkeyHex = decodeBasicBech32(npubParam, 'npub');
                          } catch (e) {
                            pubkeyHex = npubParam;
                          }
                        } else {
                          pubkeyHex = npubParam;
                        }
                      } else {
                        pubkeyHex = '';
                      }
                      final displayName = pubkeyHex.length > 8 ? pubkeyHex.substring(0, 8) : pubkeyHex;
                      final user = UserModel.create(
                        pubkeyHex: pubkeyHex,
                        name: displayName,
                        about: '',
                        profileImage: '',
                        banner: '',
                        website: '',
                        nip05: '',
                        lud16: '',
                        updatedAt: DateTime.now(),
                        nip05Verified: false,
                      );
                      return ProfilePage(user: user);
                    },
                  ),
                  GoRoute(
                    path: 'thread',
                    name: 'notifications-thread',
                    builder: (context, state) {
                      final rootNoteId = state.uri.queryParameters['rootNoteId'] ?? '';
                      final focusedNoteId = state.uri.queryParameters['focusedNoteId'];
                      return ThreadPage(
                        rootNoteId: rootNoteId,
                        focusedNoteId: focusedNoteId,
                      );
                    },
                  ),
                  GoRoute(
                    path: 'note-statistics',
                    name: 'notifications-note-statistics',
                    builder: (context, state) {
                      final note = state.extra as NoteModel?;
                      if (note == null) {
                        return const Scaffold(
                          body: Center(child: Text('Note not found')),
                        );
                      }
                      return NoteStatisticsPage(note: note);
                    },
                  ),
                  GoRoute(
                    path: 'following',
                    name: 'notifications-following',
                    builder: (context, state) {
                      final user = state.extra as UserModel?;
                      if (user == null) {
                        final npub = state.uri.queryParameters['npub'] ?? '';
                        final pubkeyHex = state.uri.queryParameters['pubkeyHex'] ?? npub;
                        final defaultUser = UserModel.create(
                          pubkeyHex: pubkeyHex,
                          name: pubkeyHex.length > 8 ? pubkeyHex.substring(0, 8) : pubkeyHex,
                        );
                        return FollowingPage(user: defaultUser);
                      }
                      return FollowingPage(user: user);
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
          final npubParam = state.uri.queryParameters['npub'] ?? '';
          final pubkeyHexParam = state.uri.queryParameters['pubkeyHex'] ?? '';
          String pubkeyHex;
          if (pubkeyHexParam.isNotEmpty) {
            pubkeyHex = pubkeyHexParam;
            if (pubkeyHex.startsWith('npub1')) {
              try {
                pubkeyHex = decodeBasicBech32(pubkeyHex, 'npub');
              } catch (e) {
                pubkeyHex = pubkeyHexParam;
              }
            }
          } else if (npubParam.isNotEmpty) {
            if (npubParam.startsWith('npub1')) {
              try {
                pubkeyHex = decodeBasicBech32(npubParam, 'npub');
              } catch (e) {
                pubkeyHex = npubParam;
              }
            } else {
              pubkeyHex = npubParam;
            }
          } else {
            pubkeyHex = '';
          }
          final displayName = pubkeyHex.length > 8 ? pubkeyHex.substring(0, 8) : pubkeyHex;
          final user = UserModel.create(
            pubkeyHex: pubkeyHex,
            name: displayName,
            about: '',
            profileImage: '',
            banner: '',
            website: '',
            nip05: '',
            lud16: '',
            updatedAt: DateTime.now(),
            nip05Verified: false,
          );
          return ProfilePage(user: user);
        },
      ),
      GoRoute(
        path: '/thread',
        name: 'thread',
        builder: (context, state) {
          final rootNoteId = state.uri.queryParameters['rootNoteId'] ?? '';
          final focusedNoteId = state.uri.queryParameters['focusedNoteId'];
          return ThreadPage(
            rootNoteId: rootNoteId,
            focusedNoteId: focusedNoteId,
          );
        },
      ),
      GoRoute(
        path: '/note-statistics',
        name: 'note-statistics',
        builder: (context, state) {
          final note = state.extra as NoteModel?;
          if (note == null) {
            return const Scaffold(
              body: Center(child: Text('Note not found')),
            );
          }
          return NoteStatisticsPage(note: note);
        },
      ),
      GoRoute(
        path: '/following',
        name: 'following',
        builder: (context, state) {
          final user = state.extra as UserModel?;
          if (user == null) {
            final npub = state.uri.queryParameters['npub'] ?? '';
            final pubkeyHex = state.uri.queryParameters['pubkeyHex'] ?? npub;
            final defaultUser = UserModel.create(
              pubkeyHex: pubkeyHex,
              name: pubkeyHex.length > 8 ? pubkeyHex.substring(0, 8) : pubkeyHex,
            );
            return FollowingPage(user: defaultUser);
          }
          return FollowingPage(user: user);
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
        path: '/event-manager',
        name: 'event-manager',
        builder: (context, state) => const EventManagerPage(),
      ),
      GoRoute(
        path: '/webview',
        name: 'webview',
        builder: (context, state) {
          final url = state.uri.queryParameters['url'] ?? '';
          return WebViewPage(url: url);
        },
      ),
    ],
  );

  static Future<String?> _handleRedirect(BuildContext context, GoRouterState state) async {
    final authService = AppDI.get<AuthService>();
    final isAuthResult = await authService.isAuthenticated();
    final isAuthenticated = isAuthResult.isSuccess && isAuthResult.data == true;
    
    final isLoginRoute = state.matchedLocation == '/login';
    final isKeysInfoRoute = state.matchedLocation == '/keys-info';
    final isProfileSetupRoute = state.matchedLocation == '/profile-setup';
    final isSuggestedFollowsRoute = state.matchedLocation == '/suggested-follows';
    
    final isAuthFlow = isLoginRoute || isKeysInfoRoute || isProfileSetupRoute || isSuggestedFollowsRoute;
    
    if (!isAuthenticated && !isAuthFlow) {
      return '/login';
    }
    
    if (isAuthenticated && isLoginRoute) {
      final npubResult = await authService.getCurrentUserNpub();
      if (npubResult.isSuccess && npubResult.data != null && npubResult.data!.isNotEmpty) {
        return '/home/feed?npub=${Uri.encodeComponent(npubResult.data!)}';
      }
    }
    
    return null;
  }
}

