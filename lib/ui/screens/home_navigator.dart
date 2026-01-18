import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:carbon_icons/carbon_icons.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:qiqstr/ui/screens/note/share_note.dart';
import '../theme/theme_manager.dart';
import '../../core/di/app_di.dart';
import '../../presentation/blocs/theme/theme_bloc.dart';
import '../../presentation/blocs/theme/theme_state.dart';
import '../../presentation/blocs/notification_indicator/notification_indicator_bloc.dart';
import '../../presentation/blocs/notification_indicator/notification_indicator_event.dart';
import '../../../data/repositories/notification_repository.dart';

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
  bool _isFirstBuild = true;

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
        debugPrint('[HomeNavigator] initState: initializing NotificationIndicatorBloc');
        indicatorBloc.add(const NotificationIndicatorInitialized());
      }
    });
  }

  @override
  void dispose() {
    _iconAnimationController.dispose();
    _exploreRotationController.dispose();
    super.dispose();
  }

  Widget _buildCustomBottomBar(bool hasNewNotifications) {
    debugPrint('[HomeNavigator] _buildCustomBottomBar: hasNewNotifications=$hasNewNotifications');
    final themeState = context.themeState;
    final navOrder = themeState?.bottomNavOrder ?? [0, 1, 2, 3];

    final navItems = [
      {
        'icon': 'assets/house.svg',
        'iconSelected': 'assets/house_fill.svg',
        'index': 0,
        'type': 'svg'
      },
      {
        'icon': 'assets/chat.svg',
        'iconSelected': 'assets/chat_fill.svg',
        'index': 1,
        'type': 'svg'
      },
      {
        'icon': 'assets/wallet.svg',
        'iconSelected': 'assets/wallet_fill.svg',
        'index': 2,
        'type': 'svg'
      },
      {
        'icon': 'assets/bell.svg',
        'iconSelected': 'assets/bell_fill.svg',
        'index': 3,
        'type': 'svg'
      },
    ];

    final orderedNavItems = navOrder.map((index) => navItems[index]).toList();

    final items = [
      orderedNavItems[0],
      orderedNavItems[1],
      {'icon': 'add', 'index': -1, 'type': 'add'},
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
              height: 60,
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child: Row(
                children: items.map((item) {
                  final index = item['index'] as int;

                  if (item['type'] == 'add') {
                    return Expanded(
                      child: GestureDetector(
                        onTap: () {
                          HapticFeedback.lightImpact();
                          ShareNotePage.show(context);
                        },
                        behavior: HitTestBehavior.opaque,
                        child: Center(
                          child: Container(
                            width: 45,
                            height: 45,
                            decoration: BoxDecoration(
                              color: context.colors.textPrimary,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.add,
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
                                item['icon'] as String, isSelected, hasNewNotifications)
                            : originalIndex == 2
                                ? _buildWalletIcon(
                                    item['icon'] as String, isSelected)
                                : originalIndex == 1
                                    ? _buildExploreIcon(
                                        item['icon'] as String,
                                        item['iconSelected'] as String?,
                                        isSelected)
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

  static const double _iconSize = 21.0;

  Widget _buildIcon({
    required String iconPath,
    required bool isSelected,
    required IconData carbonIcon,
    required int index,
    String? iconType,
    String? iconSelectedPath,
    bool isHome = false,
    bool isExplore = false,
    bool isWallet = false,
    bool isNotification = false,
  }) {
    final iconSize = _iconSize;

    if (_isFirstBuild) {
      return SizedBox(
        width: iconSize,
        height: iconSize,
        child: isSelected
            ? (iconSelectedPath != null && iconSelectedPath.isNotEmpty
                ? SvgPicture.asset(
                    iconSelectedPath,
                    width: iconSize,
                    height: iconSize,
                    fit: BoxFit.contain,
                    colorFilter: ColorFilter.mode(
                      context.colors.textPrimary,
                      BlendMode.srcIn,
                    ),
                  )
                : Icon(
                    carbonIcon,
                    size: iconSize,
                    color: context.colors.textPrimary,
                  ))
            : iconPath.isNotEmpty
                ? SvgPicture.asset(
                    iconPath,
                    width: iconSize,
                    height: iconSize,
                    fit: BoxFit.contain,
                    colorFilter: ColorFilter.mode(
                      context.colors.textPrimary,
                      BlendMode.srcIn,
                    ),
                  )
                : Icon(
                    carbonIcon,
                    size: iconSize,
                    color: context.colors.textPrimary,
                  ),
      );
    }

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
      child: SizedBox(
        key: ValueKey(
            '${isSelected ? (iconSelectedPath ?? iconPath) : iconPath}_${iconType ?? index}'),
        width: iconSize,
        height: iconSize,
        child: isSelected
            ? (iconSelectedPath != null && iconSelectedPath.isNotEmpty
                ? SvgPicture.asset(
                    iconSelectedPath,
                    width: iconSize,
                    height: iconSize,
                    fit: BoxFit.contain,
                    colorFilter: ColorFilter.mode(
                      context.colors.textPrimary,
                      BlendMode.srcIn,
                    ),
                  )
                : Icon(
                    carbonIcon,
                    size: iconSize,
                    color: context.colors.textPrimary,
                  ))
            : iconPath.isNotEmpty
                ? SvgPicture.asset(
                    iconPath,
                    width: iconSize,
                    height: iconSize,
                    fit: BoxFit.contain,
                    colorFilter: ColorFilter.mode(
                      context.colors.textPrimary,
                      BlendMode.srcIn,
                    ),
                  )
                : Icon(
                    carbonIcon,
                    size: iconSize,
                    color: context.colors.textPrimary,
                  ),
      ),
    );
  }

  Widget _buildNotificationIcon(String iconPath, bool isSelected, bool hasNewNotifications) {
    final icon = _buildIcon(
      iconPath: iconPath,
      isSelected: isSelected,
      carbonIcon: CarbonIcons.notification,
      index: 3,
      iconType: 'notification',
      iconSelectedPath: 'assets/bell_fill.svg',
      isNotification: true,
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

  Widget _buildWalletIcon(String iconPath, bool isSelected) {
    return _buildIcon(
      iconPath: iconPath,
      isSelected: isSelected,
      carbonIcon: CarbonIcons.wallet,
      index: 2,
      iconType: 'wallet',
      iconSelectedPath: 'assets/wallet_fill.svg',
      isWallet: true,
    );
  }

  Widget _buildExploreIcon(
      String iconPath, String? iconSelectedPath, bool isSelected) {
    return _buildIcon(
      iconPath: iconPath,
      isSelected: isSelected,
      carbonIcon: CarbonIcons.chat,
      index: 1,
      iconType: 'explore',
      iconSelectedPath: iconSelectedPath,
      isExplore: true,
    );
  }

  Widget _buildRegularIcon(Map<String, dynamic> item, bool isSelected) {
    final String iconPath = item['icon'] as String;
    final String? iconSelectedPath = item['iconSelected'] as String?;
    final int index = item['index'] as int;

    IconData carbonIcon;
    if (index == 0) {
      carbonIcon = CarbonIcons.home;
    } else {
      carbonIcon = CarbonIcons.home;
    }

    return _buildIcon(
      iconPath: iconPath,
      isSelected: isSelected,
      carbonIcon: carbonIcon,
      index: index,
      iconSelectedPath: iconSelectedPath,
      isHome: index == 0,
    );
  }

  void _handleNavigation(int pageViewIndex) {
    final themeState = context.themeState;
    final navOrder = themeState?.bottomNavOrder ?? [0, 1, 2, 3];
    final originalIndex = navOrder[pageViewIndex];

    if (originalIndex == 0) {
      if (widget.navigationShell.currentIndex == pageViewIndex) {
        final npub = widget.npub;
        context.go('/home/feed?npub=${Uri.encodeComponent(npub)}');
      } else {
        if (mounted) {
          _iconAnimationController.reset();
          _iconAnimationController.forward();
          widget.navigationShell.goBranch(pageViewIndex);
        }
      }
    } else if (originalIndex == 3) {
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
    if (_isFirstBuild) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _isFirstBuild = false;
          });
        }
      });
    }

    final indicatorBloc = AppDI.get<NotificationIndicatorBloc>();
    debugPrint('[HomeNavigator] build: indicatorBloc=$indicatorBloc, currentState=${indicatorBloc.state}');
    
    return BlocProvider<NotificationIndicatorBloc>.value(
      value: indicatorBloc,
      child: BlocBuilder<ThemeBloc, ThemeState>(
        builder: (context, themeState) {
          return Scaffold(
            extendBody: true,
            body: PageStorage(
              bucket: PageStorageBucket(),
              child: widget.navigationShell,
            ),
            bottomNavigationBar: StreamBuilder<bool>(
              stream: AppDI.get<NotificationRepository>().hasNewNotificationsStream,
              initialData: false,
              builder: (context, snapshot) {
                final hasNewNotifications = snapshot.data ?? false;
                debugPrint('[HomeNavigator] StreamBuilder: hasNewNotifications=$hasNewNotifications, snapshot.hasData=${snapshot.hasData}');
                return _buildCustomBottomBar(hasNewNotifications);
              },
            ),
          );
        },
      ),
    );
  }
}
