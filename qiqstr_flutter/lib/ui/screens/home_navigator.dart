import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import 'package:go_router/go_router.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:qiqstr/ui/screens/note/share_note.dart';
import '../theme/theme_manager.dart';
import '../../core/di/app_di.dart';
import '../../presentation/blocs/theme/theme_bloc.dart';
import '../../presentation/blocs/theme/theme_state.dart';
import '../../presentation/blocs/notification_indicator/notification_indicator_bloc.dart';
import '../../presentation/blocs/notification_indicator/notification_indicator_event.dart';
import '../../presentation/blocs/notification_indicator/notification_indicator_state.dart';
import '../../presentation/blocs/dm/dm_bloc.dart';
import '../../presentation/blocs/dm/dm_event.dart' as dm_events;
import '../../presentation/blocs/dm_indicator/dm_indicator_bloc.dart';
import '../../presentation/blocs/dm_indicator/dm_indicator_event.dart';
import '../../presentation/blocs/dm_indicator/dm_indicator_state.dart';
import '../../data/services/spark_service.dart';
import '../../core/scroll_to_top_notifier.dart';

class HomeNavigator extends StatefulWidget {
  final String npub;
  final StatefulNavigationShell navigationShell;

  const HomeNavigator({
    super.key,
    required this.npub,
    required this.navigationShell,
  });

  @override
  State<HomeNavigator> createState() => _HomeNavigatorState();
}

class _HomeNavigatorState extends State<HomeNavigator>
    with TickerProviderStateMixin {
  late AnimationController _iconAnimationController;
  late AnimationController _exploreRotationController;
  @override
  void initState() {
    super.initState();
    _iconAnimationController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _exploreRotationController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final indicatorBloc = AppDI.get<NotificationIndicatorBloc>();
        indicatorBloc.add(const NotificationIndicatorInitialized());

        final dmBloc = AppDI.get<DmBloc>();
        dmBloc.add(const dm_events.DmConversationsLoadRequested());

        final dmIndicatorBloc = AppDI.get<DmIndicatorBloc>();
        dmIndicatorBloc.add(const DmIndicatorInitialized());
      }
    });
  }

  @override
  void dispose() {
    _iconAnimationController.dispose();
    _exploreRotationController.dispose();
    super.dispose();
  }

  static const double _iconSize = 25.0;

  Widget _buildCustomBottomBar(
      bool hasNewNotifications, bool hasNewDmMessages) {
    final themeState = context.themeState;
    final navOrder = themeState?.bottomNavOrder ?? [0, 1, 2, 3];

    final navItems = [
      {
        'iconRegular': PhosphorIcons.house(),
        'iconFill': PhosphorIcons.house(PhosphorIconsStyle.fill),
        'index': 0
      },
      {
        'iconRegular': PhosphorIcons.chatCircle(),
        'iconFill': PhosphorIcons.chatCircle(PhosphorIconsStyle.fill),
        'index': 1
      },
      {
        'iconRegular': PhosphorIcons.wallet(),
        'iconFill': PhosphorIcons.wallet(PhosphorIconsStyle.fill),
        'index': 2
      },
      {
        'iconRegular': PhosphorIcons.bell(),
        'iconFill': PhosphorIcons.bell(PhosphorIconsStyle.fill),
        'index': 3
      },
    ];

    final orderedNavItems = navOrder.map((index) => navItems[index]).toList();

    final items = [
      orderedNavItems[0],
      orderedNavItems[1],
      {'iconRegular': null, 'iconFill': null, 'index': -1, 'type': 'add'},
      orderedNavItems[2],
      orderedNavItems[3],
    ];

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
        child: Container(
          decoration: BoxDecoration(
            color: context.colors.surface.withValues(alpha: 0.8),
          ),
          child: SafeArea(
            child: Container(
              height: 55,
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child: Row(
                children: items.map((item) {
                  final index = item['index'] as int;

                  if (item['type'] == 'add') {
                    return Expanded(
                      child: GestureDetector(
                        onTap: () async {
                          HapticFeedback.lightImpact();
                          final result = await ShareNotePage.show(context);
                          if (result == true && mounted) {
                            final currentIndex =
                                widget.navigationShell.currentIndex;
                            if (currentIndex != 0) {
                              widget.navigationShell.goBranch(0);
                            }
                          }
                        },
                        behavior: HitTestBehavior.opaque,
                        child: Center(
                          child: Container(
                            width: 45,
                            height: 45,
                            decoration: BoxDecoration(
                              color: context.colors.textPrimary,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: PhosphorIcon(
                              PhosphorIcons.plus(),
                              color: context.colors.background,
                              size: 25,
                            ),
                          ),
                        ),
                      ),
                    );
                  }

                  final originalIndex = index;
                  final themeState = context.themeState;
                  final navOrder = themeState?.bottomNavOrder ?? [0, 1, 2, 3];
                  final pageViewIndex = navOrder.indexOf(originalIndex);
                  final bool isSelected =
                      widget.navigationShell.currentIndex == pageViewIndex;

                  return Expanded(
                    child: GestureDetector(
                      onTap: () {
                        HapticFeedback.lightImpact();
                        final themeState = context.themeState;
                        final navOrder =
                            themeState?.bottomNavOrder ?? [0, 1, 2, 3];
                        final pageViewIndex = navOrder.indexOf(originalIndex);
                        _handleNavigation(pageViewIndex);
                      },
                      behavior: HitTestBehavior.opaque,
                      child: Center(
                        child: originalIndex == 3
                            ? _buildNotificationIcon(
                                item, isSelected, hasNewNotifications)
                            : originalIndex == 2
                                ? _buildWalletIcon(item, isSelected)
                                : originalIndex == 1
                                    ? _buildDmIcon(
                                        item, isSelected, hasNewDmMessages)
                                    : _buildRegularIcon(item, isSelected),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPhosphorIcon({
    required PhosphorIconData regularIcon,
    required PhosphorIconData fillIcon,
    required bool isSelected,
  }) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      switchInCurve: Curves.easeInOut,
      switchOutCurve: Curves.easeInOut,
      transitionBuilder: (Widget child, Animation<double> animation) {
        return FadeTransition(
          opacity: animation,
          child: child,
        );
      },
      child: PhosphorIcon(
        key: ValueKey(isSelected),
        isSelected ? fillIcon : regularIcon,
        size: _iconSize,
        color: context.colors.textPrimary,
      ),
    );
  }

  Widget _buildNotificationIcon(
      Map<String, dynamic> item, bool isSelected, bool hasNewNotifications) {
    final icon = _buildPhosphorIcon(
      regularIcon: item['iconRegular'] as PhosphorIconData,
      fillIcon: item['iconFill'] as PhosphorIconData,
      isSelected: isSelected,
    );

    if (hasNewNotifications) {
      return SizedBox(
        width: _iconSize + 6,
        height: _iconSize + 6,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: 0,
              top: 0,
              child: icon,
            ),
            Positioned(
              right: -2,
              top: -2,
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: context.colors.accent,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: context.colors.background,
                    width: 1.5,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return icon;
  }

  Widget _buildWalletIcon(Map<String, dynamic> item, bool isSelected) {
    return _buildPhosphorIcon(
      regularIcon: item['iconRegular'] as PhosphorIconData,
      fillIcon: item['iconFill'] as PhosphorIconData,
      isSelected: isSelected,
    );
  }

  Widget _buildDmIcon(
      Map<String, dynamic> item, bool isSelected, bool hasNewDmMessages) {
    final icon = _buildPhosphorIcon(
      regularIcon: item['iconRegular'] as PhosphorIconData,
      fillIcon: item['iconFill'] as PhosphorIconData,
      isSelected: isSelected,
    );

    if (hasNewDmMessages) {
      return SizedBox(
        width: _iconSize + 6,
        height: _iconSize + 6,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: 0,
              top: 0,
              child: icon,
            ),
            Positioned(
              right: -6,
              top: -2,
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: context.colors.accent,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: context.colors.background,
                    width: 1.5,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return icon;
  }

  Widget _buildRegularIcon(Map<String, dynamic> item, bool isSelected) {
    return _buildPhosphorIcon(
      regularIcon: item['iconRegular'] as PhosphorIconData,
      fillIcon: item['iconFill'] as PhosphorIconData,
      isSelected: isSelected,
    );
  }

  Future<void> _handleNavigation(int pageViewIndex) async {
    final themeState = context.themeState;
    final navOrder = themeState?.bottomNavOrder ?? [0, 1, 2, 3];
    final originalIndex = navOrder[pageViewIndex];

    if (originalIndex == 0) {
      if (widget.navigationShell.currentIndex == pageViewIndex) {
        final location = GoRouterState.of(context).uri.toString();
        final isAtFeedRoot = location.startsWith('/home/feed') &&
            !location.startsWith('/home/feed/');
        if (isAtFeedRoot) {
          ScrollToTopNotifier.triggerFeed();
        } else {
          widget.navigationShell.goBranch(pageViewIndex, initialLocation: true);
        }
      } else {
        if (mounted) {
          _iconAnimationController.reset();
          _iconAnimationController.forward();
          widget.navigationShell.goBranch(pageViewIndex);
        }
      }
    } else if (originalIndex == 2) {
      final sparkService = AppDI.get<SparkService>();
      final isConnectedResult = await sparkService.isConnected();
      final isConnected =
          isConnectedResult.isSuccess && isConnectedResult.data == true;
      if (!mounted) return;
      if (!isConnected) {
        context
            .push('/onboarding-spark?npub=${Uri.encodeComponent(widget.npub)}');
        return;
      }
      _iconAnimationController.reset();
      _iconAnimationController.forward();
      widget.navigationShell.goBranch(pageViewIndex);
    } else if (originalIndex == 1) {
      AppDI.get<DmIndicatorBloc>().add(const DmIndicatorChecked());
      if (mounted) {
        _iconAnimationController.reset();
        _iconAnimationController.forward();
        widget.navigationShell.goBranch(pageViewIndex);
      }
    } else if (originalIndex == 3) {
      final indicatorBloc = AppDI.get<NotificationIndicatorBloc>();
      indicatorBloc.add(const NotificationIndicatorChecked());
      if (widget.navigationShell.currentIndex == pageViewIndex) {
        final npub = widget.npub;
        context.go('/home/notifications?npub=${Uri.encodeComponent(npub)}');
      } else {
        if (mounted) {
          _iconAnimationController.reset();
          _iconAnimationController.forward();
          widget.navigationShell.goBranch(pageViewIndex);
        }
      }
    } else {
      if (mounted) {
        _iconAnimationController.reset();
        _iconAnimationController.forward();
        widget.navigationShell.goBranch(pageViewIndex);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final indicatorBloc = AppDI.get<NotificationIndicatorBloc>();

    return BlocProvider<NotificationIndicatorBloc>.value(
      value: indicatorBloc,
      child: BlocBuilder<ThemeBloc, ThemeState>(
        builder: (context, themeState) {
          return PopScope(
            canPop: false,
            onPopInvokedWithResult: (didPop, _) {
              if (didPop) return;

              if (GoRouter.of(context).canPop()) {
                context.pop();
                return;
              }

              final navOrder =
                  context.themeState?.bottomNavOrder ?? [0, 1, 2, 3];
              final feedPageViewIndex = navOrder.indexOf(0);

              if (widget.navigationShell.currentIndex != feedPageViewIndex) {
                widget.navigationShell
                    .goBranch(feedPageViewIndex, initialLocation: true);
              }
            },
            child: Scaffold(
              extendBody: true,
              body: PageStorage(
                bucket: PageStorageBucket(),
                child: widget.navigationShell,
              ),
              bottomNavigationBar: BlocBuilder<NotificationIndicatorBloc,
                  NotificationIndicatorState>(
                bloc: AppDI.get<NotificationIndicatorBloc>(),
                builder: (context, notifState) {
                  final hasNewNotifications =
                      notifState is NotificationIndicatorLoaded &&
                          notifState.hasNewNotifications;
                  return BlocBuilder<DmIndicatorBloc, DmIndicatorState>(
                    bloc: AppDI.get<DmIndicatorBloc>(),
                    builder: (context, dmState) {
                      final hasNewDmMessages = dmState is DmIndicatorLoaded &&
                          dmState.hasNewMessages;
                      return _buildCustomBottomBar(
                          hasNewNotifications, hasNewDmMessages);
                    },
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }
}
