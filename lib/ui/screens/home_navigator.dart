import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:carbon_icons/carbon_icons.dart';
import 'package:provider/provider.dart';

import 'package:qiqstr/ui/screens/note/feed_page.dart';
import 'package:qiqstr/ui/screens/notification/notification_page.dart';
import 'package:qiqstr/ui/screens/wallet/wallet_page.dart';
import 'package:qiqstr/ui/screens/dm/dm_page.dart';
import 'package:qiqstr/ui/screens/note/share_note.dart';
import 'package:qiqstr/ui/widgets/common/sidebar_widget.dart';
import '../theme/theme_manager.dart';

class HomeNavigator extends StatefulWidget {
  final String npub;

  const HomeNavigator({
    super.key,
    required this.npub,
  });

  @override
  State<HomeNavigator> createState() => _HomeNavigatorState();
}

class _HomeNavigatorState extends State<HomeNavigator> with TickerProviderStateMixin {
  int _currentIndex = 0;
  final GlobalKey<FeedPageState> _feedPageKey = GlobalKey<FeedPageState>();
  late AnimationController _iconAnimationController;
  late AnimationController _exploreRotationController;
  bool _isFirstBuild = true;

  final Map<int, Widget> _pageCache = {};

  Widget _getPage(int index) {
    if (!_pageCache.containsKey(index)) {
      switch (index) {
        case 0:
          _pageCache[index] = FeedPage(key: _feedPageKey, npub: widget.npub);
          break;
        case 1:
          _pageCache[index] = const DmPage();
          break;
        case 2:
          _pageCache[index] = const WalletPage();
          break;
        case 3:
          _pageCache[index] = const NotificationPage();
          break;
      }
    }
    return _pageCache[index]!;
  }


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
      {'icon': 'assets/home_gap.svg', 'index': 0, 'type': 'svg'},
      {'icon': '', 'index': 1, 'type': 'carbon'},
      {'icon': 'assets/wallet_icon.svg', 'index': 2, 'type': 'svg'},
      {'icon': 'assets/notification_button.svg', 'index': 3, 'type': 'svg'},
    ];

    final orderedNavItems = navOrder.map((index) => navItems[index]).toList();

    final items = [
      orderedNavItems[0],
      orderedNavItems[1],
      {'icon': 'add', 'index': -1, 'type': 'add'},
      orderedNavItems[2],
      orderedNavItems[3],
    ];

    return Container(
      decoration: BoxDecoration(
        color: context.colors.surface,
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
              final bool isSelected = _currentIndex == pageViewIndex;

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
                  child: originalIndex == 3
                      ? _buildNotificationIcon(item['icon'] as String, isSelected)
                      : originalIndex == 2
                          ? _buildWalletIcon(item['icon'] as String, isSelected)
                          : originalIndex == 1
                              ? _buildExploreIcon(isSelected)
                              : _buildRegularIcon(item, isSelected),
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  static const double _iconSizeSelected = 25.0;
  static const double _iconSizeUnselected = 21.0;
  static const double _homeIconSizeSelected = 26.0;
  static const double _homeIconSizeUnselected = 24.0;
  static const double _sendAltIconSize = 28.0;
  static const double _sendAltIconSizeSelected = 30.0;

  Widget _buildIcon({
    required String iconPath,
    required bool isSelected,
    required IconData carbonIcon,
    required int index,
    String? iconType,
    bool isHome = false,
    bool isExplore = false,
    bool isWallet = false,
    bool isNotification = false,
  }) {
    final iconSize =
        isHome ? (isSelected ? _homeIconSizeSelected : _homeIconSizeUnselected) : (isSelected ? _iconSizeSelected : _iconSizeUnselected);

    if (_isFirstBuild) {
      final themeManager = context.themeManager;
      final isDarkMode = themeManager?.isDarkMode ?? false;

      return SizedBox(
        width: iconSize,
        height: iconSize,
        child: isSelected
            ? (isHome
                ? isDarkMode
                    ? ColorFiltered(
                        colorFilter: const ColorFilter.matrix([
                          -1,
                          0,
                          0,
                          0,
                          255,
                          0,
                          -1,
                          0,
                          0,
                          255,
                          0,
                          0,
                          -1,
                          0,
                          255,
                          0,
                          0,
                          0,
                          1,
                          0,
                        ]),
                        child: Image.asset(
                          'assets/home_filled.png',
                          width: iconSize,
                          height: iconSize,
                          fit: BoxFit.contain,
                        ),
                      )
                    : Image.asset(
                        'assets/home_filled.png',
                        width: iconSize,
                        height: iconSize,
                        fit: BoxFit.contain,
                      )
                : isExplore
                    ? Icon(
                        isSelected ? CarbonIcons.send_alt_filled : CarbonIcons.send_alt,
                        size: isSelected ? _sendAltIconSizeSelected : _sendAltIconSize,
                        color: context.colors.textPrimary,
                      )
                    : isWallet
                        ? isDarkMode
                            ? ColorFiltered(
                                colorFilter: const ColorFilter.matrix([
                                  -1,
                                  0,
                                  0,
                                  0,
                                  255,
                                  0,
                                  -1,
                                  0,
                                  0,
                                  255,
                                  0,
                                  0,
                                  -1,
                                  0,
                                  255,
                                  0,
                                  0,
                                  0,
                                  1,
                                  0,
                                ]),
                                child: Image.asset(
                                  'assets/wallet_filled.png',
                                  width: iconSize,
                                  height: iconSize,
                                  fit: BoxFit.contain,
                                ),
                              )
                            : Image.asset(
                                'assets/wallet_filled.png',
                                width: iconSize,
                                height: iconSize,
                                fit: BoxFit.contain,
                              )
                        : isNotification
                            ? isDarkMode
                                ? ColorFiltered(
                                    colorFilter: const ColorFilter.matrix([
                                      -1,
                                      0,
                                      0,
                                      0,
                                      255,
                                      0,
                                      -1,
                                      0,
                                      0,
                                      255,
                                      0,
                                      0,
                                      -1,
                                      0,
                                      255,
                                      0,
                                      0,
                                      0,
                                      1,
                                      0,
                                    ]),
                                    child: Image.asset(
                                      'assets/notification_filled.png',
                                      width: iconSize,
                                      height: iconSize,
                                      fit: BoxFit.contain,
                                    ),
                                  )
                                : Image.asset(
                                    'assets/notification_filled.png',
                                    width: iconSize,
                                    height: iconSize,
                                    fit: BoxFit.contain,
                                  )
                            : Icon(
                                carbonIcon,
                                size: iconSize,
                                color: context.colors.accent,
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
          child: Transform.scale(
            scale: isSelected ? 1.0 + (animation.value * 0.1) : 1.0,
            child: child,
          ),
        );
      },
      child: Builder(
        builder: (context) {
          final themeManager = context.themeManager;
          final isDarkMode = themeManager?.isDarkMode ?? false;

          return SizedBox(
            key: ValueKey(
                '${isSelected ? (isHome ? 'home_filled' : isExplore ? 'explore' : isWallet ? 'wallet_filled' : isNotification ? 'notification_filled' : 'carbon') : 'svg'}_${iconType ?? index}_${isDarkMode ? 'dark' : 'light'}'),
            width: iconSize,
            height: iconSize,
            child: isSelected
                ? (isHome
                    ? isDarkMode
                        ? ColorFiltered(
                            colorFilter: const ColorFilter.matrix([
                              -1,
                              0,
                              0,
                              0,
                              255,
                              0,
                              -1,
                              0,
                              0,
                              255,
                              0,
                              0,
                              -1,
                              0,
                              255,
                              0,
                              0,
                              0,
                              1,
                              0,
                            ]),
                            child: Image.asset(
                              'assets/home_filled.png',
                              width: iconSize,
                              height: iconSize,
                              fit: BoxFit.contain,
                            ),
                          )
                        : Image.asset(
                            'assets/home_filled.png',
                            width: iconSize,
                            height: iconSize,
                            fit: BoxFit.contain,
                          )
                    : isExplore
                        ? Icon(
                            isSelected ? CarbonIcons.send_alt_filled : CarbonIcons.send_alt,
                            size: isSelected ? _sendAltIconSizeSelected : _sendAltIconSize,
                            color: context.colors.textPrimary,
                          )
                        : isWallet
                            ? isDarkMode
                                ? ColorFiltered(
                                    colorFilter: const ColorFilter.matrix([
                                      -1,
                                      0,
                                      0,
                                      0,
                                      255,
                                      0,
                                      -1,
                                      0,
                                      0,
                                      255,
                                      0,
                                      0,
                                      -1,
                                      0,
                                      255,
                                      0,
                                      0,
                                      0,
                                      1,
                                      0,
                                    ]),
                                    child: Image.asset(
                                      'assets/wallet_filled.png',
                                      width: iconSize,
                                      height: iconSize,
                                      fit: BoxFit.contain,
                                    ),
                                  )
                                : Image.asset(
                                    'assets/wallet_filled.png',
                                    width: iconSize,
                                    height: iconSize,
                                    fit: BoxFit.contain,
                                  )
                            : isNotification
                                ? isDarkMode
                                    ? ColorFiltered(
                                        colorFilter: const ColorFilter.matrix([
                                          -1,
                                          0,
                                          0,
                                          0,
                                          255,
                                          0,
                                          -1,
                                          0,
                                          0,
                                          255,
                                          0,
                                          0,
                                          -1,
                                          0,
                                          255,
                                          0,
                                          0,
                                          0,
                                          1,
                                          0,
                                        ]),
                                        child: Image.asset(
                                          'assets/notification_filled.png',
                                          width: iconSize,
                                          height: iconSize,
                                          fit: BoxFit.contain,
                                        ),
                                      )
                                    : Image.asset(
                                        'assets/notification_filled.png',
                                        width: iconSize,
                                        height: iconSize,
                                        fit: BoxFit.contain,
                                      )
                                : Icon(
                                    carbonIcon,
                                    size: iconSize,
                                    color: context.colors.accent,
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
        },
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
      isWallet: true,
    );
  }

  Widget _buildExploreIcon(bool isSelected) {
    return Icon(
      isSelected ? CarbonIcons.send_alt_filled : CarbonIcons.send_alt,
      size: isSelected ? _sendAltIconSizeSelected : _sendAltIconSize,
      color: context.colors.textPrimary,
    );
  }

  Widget _buildRegularIcon(Map<String, dynamic> item, bool isSelected) {
    final String iconPath = item['icon'] as String;
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
      isHome: index == 0,
    );
  }

  void _handleNavigation(int pageViewIndex) {
    final themeManager = context.themeManager;
    final navOrder = themeManager?.bottomNavOrder ?? [0, 1, 2, 3];
    final originalIndex = navOrder[pageViewIndex];

    if (originalIndex == 0) {
      if (_currentIndex == pageViewIndex) {
        _feedPageKey.currentState?.scrollToTop();
      } else {
        if (mounted) {
          _iconAnimationController.reset();
          _iconAnimationController.forward();
          setState(() {
            _currentIndex = pageViewIndex;
          });
        }
      }
    } else {
      if (mounted) {
        _iconAnimationController.reset();
        _iconAnimationController.forward();
        setState(() {
          _currentIndex = pageViewIndex;
        });
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
        final navOrder = themeManager.bottomNavOrder;

        return Scaffold(
          extendBody: true,
          drawer: const SidebarWidget(),
          body: PageStorage(
            bucket: PageStorageBucket(),
            child: IndexedStack(
              index: _currentIndex,
              children: navOrder.map((originalIndex) {
                if (navOrder.indexOf(originalIndex) <= _currentIndex || originalIndex == 0) {
                  return _getPage(originalIndex);
                }
                return const SizedBox.shrink();
              }).toList(),
            ),
          ),
          bottomNavigationBar: RepaintBoundary(
            child: _buildCustomBottomBar(),
          ),
        );
      },
    );
  }
}
