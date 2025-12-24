import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:carbon_icons/carbon_icons.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';

import 'package:qiqstr/ui/screens/note/share_note.dart';
import '../theme/theme_manager.dart';

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

class _HomeNavigatorState extends State<HomeNavigator> with TickerProviderStateMixin {
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
  }

  @override
  void dispose() {
    _iconAnimationController.dispose();
    _exploreRotationController.dispose();
    super.dispose();
  }

  Widget _buildCustomBottomBar() {
    final themeManager = context.themeManager;
    final navOrder = themeManager?.bottomNavOrder ?? [0, 1, 2, 3];

    final navItems = [
      {'icon': 'assets/house.svg', 'iconSelected': 'assets/house_fill.svg', 'index': 0, 'type': 'svg'},
      {'icon': 'assets/chat.svg', 'iconSelected': 'assets/chat_fill.svg', 'index': 1, 'type': 'svg'},
      {'icon': 'assets/wallet.svg', 'iconSelected': 'assets/wallet_fill.svg', 'index': 2, 'type': 'svg'},
      {'icon': 'assets/bell.svg', 'iconSelected': 'assets/bell_fill.svg', 'index': 3, 'type': 'svg'},
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
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          color: context.colors.textPrimary,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.add,
                          color: context.colors.background,
                          size: 26,
                        ),
                      ),
                    ),
                  ),
                );
              }

              final originalIndex = index;
              final themeManager = context.themeManager;
              final navOrder = themeManager?.bottomNavOrder ?? [0, 1, 2, 3];
              final pageViewIndex = navOrder.indexOf(originalIndex);
              final bool isSelected = widget.navigationShell.currentIndex == pageViewIndex;

              return Expanded(
                child: GestureDetector(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    final themeManager = context.themeManager;
                    final navOrder = themeManager?.bottomNavOrder ?? [0, 1, 2, 3];
                    final pageViewIndex = navOrder.indexOf(originalIndex);
                    _handleNavigation(pageViewIndex);
                  },
                  behavior: HitTestBehavior.opaque,
                  child: Center(
                    child: originalIndex == 3
                        ? _buildNotificationIcon(item['icon'] as String, isSelected)
                        : originalIndex == 2
                            ? _buildWalletIcon(item['icon'] as String, isSelected)
                            : originalIndex == 1
                                ? _buildExploreIcon(item['icon'] as String, item['iconSelected'] as String?, isSelected)
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

  static const double _iconSize = 22.0;

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
        key: ValueKey('${isSelected ? (iconSelectedPath ?? iconPath) : iconPath}_${iconType ?? index}'),
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

  Widget _buildNotificationIcon(String iconPath, bool isSelected) {
    return _buildIcon(
      iconPath: iconPath,
      isSelected: isSelected,
      carbonIcon: CarbonIcons.notification,
      index: 3,
      iconType: 'notification',
      iconSelectedPath: 'assets/bell_fill.svg',
      isNotification: true,
    );
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

  Widget _buildExploreIcon(String iconPath, String? iconSelectedPath, bool isSelected) {
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
    final themeManager = context.themeManager;
    final navOrder = themeManager?.bottomNavOrder ?? [0, 1, 2, 3];
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

    return Consumer<ThemeManager>(
      builder: (context, themeManager, child) {
        return Scaffold(
          extendBody: true,
          body: PageStorage(
            bucket: PageStorageBucket(),
            child: widget.navigationShell,
          ),
          bottomNavigationBar: RepaintBoundary(
            child: _buildCustomBottomBar(),
          ),
        );
      },
    );
  }
}
