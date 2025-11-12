import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:bounce/bounce.dart';
import 'package:carbon_icons/carbon_icons.dart';
import 'package:provider/provider.dart';

import 'package:qiqstr/ui/screens/feed_page.dart';
import 'package:qiqstr/ui/screens/users_search_page.dart';
import 'package:qiqstr/ui/screens/notification_page.dart';
import 'package:qiqstr/ui/screens/wallet_page.dart';
import 'package:qiqstr/ui/screens/share_note.dart';
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
  bool _isFirstBuild = true;

  late final List<Widget> _pages = [
    FeedPage(key: _feedPageKey, npub: widget.npub),
    const UserSearchPage(),
    const WalletPage(),
    const NotificationPage(),
  ];

  @override
  void initState() {
    super.initState();
    _iconAnimationController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
  }

  @override
  void dispose() {
    _iconAnimationController.dispose();
    super.dispose();
  }

  Widget _buildCustomBottomBar() {
    const items = [
      {'icon': 'assets/home_gap.svg', 'index': 0, 'type': 'svg'},
      {'icon': 'assets/search_button.svg', 'index': 1, 'type': 'svg'},
      {'icon': 'add', 'index': -1, 'type': 'add'},
      {'icon': 'assets/wallet_icon.svg', 'index': 2, 'type': 'svg'},
      {'icon': 'assets/notification_button.svg', 'index': 3, 'type': 'svg'},
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
                  child: Bounce(
                    scaleFactor: 0.85,
                    onTap: () {
                      HapticFeedback.lightImpact();
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const ShareNotePage(),
                        ),
                      );
                    },
                    behavior: HitTestBehavior.opaque,
                    child: Center(
                      child: Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          color: context.colors.buttonPrimary,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.add,
                          color: context.colors.buttonText,
                          size: 26,
                        ),
                      ),
                    ),
                  ),
                );
              }

              final bool isSelected = _currentIndex == index;

              return Expanded(
                child: Bounce(
                  scaleFactor: 0.85,
                  onTap: () {
                    HapticFeedback.lightImpact();
                    _handleNavigation(index);
                  },
                  behavior: HitTestBehavior.opaque,
                  child: Stack(
                    alignment: Alignment.center,
                    clipBehavior: Clip.none,
                    children: [
                      index == 3
                          ? _buildNotificationIcon(item['icon'] as String, isSelected)
                          : index == 2
                              ? _buildWalletIcon(item['icon'] as String, isSelected)
                              : _buildRegularIcon(item, isSelected),
                      Positioned(
                        top: -12,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeInOut,
                          width: isSelected ? 48 : 0,
                          height: 4,
                          decoration: BoxDecoration(
                            color: context.colors.accent,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    ],
                  ),
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
  static const double _homeIconSizeUnselected = 22.0;

  Widget _buildIcon({
    required String iconPath,
    required bool isSelected,
    required IconData carbonIcon,
    required int index,
    String? iconType,
    bool isHome = false,
  }) {
    final iconSize = isHome
        ? (isSelected ? _homeIconSizeSelected : _homeIconSizeUnselected)
        : (isSelected ? _iconSizeSelected : _iconSizeUnselected);
    
    if (_isFirstBuild) {
      return SizedBox(
        width: iconSize,
        height: iconSize,
        child: isSelected
            ? Icon(
                carbonIcon,
                size: iconSize,
                color: context.colors.accent,
              )
            : SvgPicture.asset(
                iconPath,
                width: iconSize,
                height: iconSize,
                fit: BoxFit.contain,
                colorFilter: ColorFilter.mode(
                  context.colors.textPrimary,
                  BlendMode.srcIn,
                ),
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
      child: SizedBox(
        key: ValueKey('${isSelected ? 'carbon' : 'svg'}_${iconType ?? index}'),
        width: iconSize,
        height: iconSize,
        child: isSelected
            ? Icon(
                carbonIcon,
                size: iconSize,
                color: context.colors.accent,
              )
            : SvgPicture.asset(
                iconPath,
                width: iconSize,
                height: iconSize,
                fit: BoxFit.contain,
                colorFilter: ColorFilter.mode(
                  context.colors.textPrimary,
                  BlendMode.srcIn,
                ),
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
    );
  }

  Widget _buildWalletIcon(String iconPath, bool isSelected) {
    return _buildIcon(
      iconPath: iconPath,
      isSelected: isSelected,
      carbonIcon: CarbonIcons.wallet,
      index: 2,
      iconType: 'wallet',
    );
  }

  Widget _buildRegularIcon(Map<String, dynamic> item, bool isSelected) {
    final String iconPath = item['icon'] as String;
    final int index = item['index'] as int;

    IconData carbonIcon;
    if (index == 0) {
      carbonIcon = CarbonIcons.home;
    } else if (index == 1) {
      carbonIcon = CarbonIcons.search;
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

  void _handleNavigation(int index) {
    if (index == 3) {
      if (mounted) {
        _iconAnimationController.reset();
        _iconAnimationController.forward();
        setState(() => _currentIndex = index);
      }
    } else if (index == 0) {
      if (_currentIndex == 0) {
        _feedPageKey.currentState?.scrollToTop();
      } else {
        if (mounted) {
          _iconAnimationController.reset();
          _iconAnimationController.forward();
          setState(() => _currentIndex = index);
        }
      }
    } else {
      if (mounted) {
        _iconAnimationController.reset();
        _iconAnimationController.forward();
        setState(() => _currentIndex = index);
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
            child: IndexedStack(
              index: _currentIndex,
              children: _pages,
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
