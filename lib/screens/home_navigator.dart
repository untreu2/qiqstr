import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:bounce/bounce.dart';
import 'package:carbon_icons/carbon_icons.dart';

import 'package:qiqstr/screens/feed_page.dart';
import 'package:qiqstr/screens/users_search_page.dart';
import 'package:qiqstr/screens/notification_page.dart';
import 'package:qiqstr/screens/wallet_page.dart';
import 'package:qiqstr/screens/share_note.dart';
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
                  onTap: () => _handleNavigation(index),
                  behavior: HitTestBehavior.opaque,
                  child: Center(
                    child: index == 3
                        ? _buildNotificationIcon(item['icon'] as String, isSelected)
                        : index == 2
                            ? _buildWalletIcon(item['icon'] as String, isSelected)
                            : _buildRegularIcon(item, isSelected),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  Widget _buildNotificationIcon(String iconPath, bool isSelected) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      transitionBuilder: (Widget child, Animation<double> animation) {
        return FadeTransition(
          opacity: animation,
          child: Transform.scale(
            scale: isSelected ? 1.0 + (animation.value * 0.1) : 1.0,
            child: child,
          ),
        );
      },
      child: isSelected
          ? Icon(
              CarbonIcons.notification,
              key: const ValueKey('carbon_notification'),
              size: 24,
              color: context.colors.accent,
            )
          : SvgPicture.asset(
              iconPath,
              key: const ValueKey('svg_notification'),
              width: 21,
              height: 21,
              colorFilter: ColorFilter.mode(
                context.colors.textPrimary,
                BlendMode.srcIn,
              ),
            ),
    );
  }

  Widget _buildWalletIcon(String iconPath, bool isSelected) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      transitionBuilder: (Widget child, Animation<double> animation) {
        return FadeTransition(
          opacity: animation,
          child: Transform.scale(
            scale: isSelected ? 1.0 + (animation.value * 0.1) : 1.0,
            child: child,
          ),
        );
      },
      child: isSelected
          ? Icon(
              CarbonIcons.wallet,
              key: const ValueKey('carbon_wallet'),
              size: 22,
              color: context.colors.accent,
            )
          : SvgPicture.asset(
              iconPath,
              key: const ValueKey('svg_wallet'),
              width: 18,
              height: 18,
              colorFilter: ColorFilter.mode(
                context.colors.textPrimary,
                BlendMode.srcIn,
              ),
            ),
    );
  }

  Widget _buildRegularIcon(Map<String, dynamic> item, bool isSelected) {
    final String iconPath = item['icon'] as String;
    final int index = item['index'] as int;

    // Use carbon icons for selected state
    IconData carbonIcon;
    if (index == 0) {
      carbonIcon = CarbonIcons.home; // Home icon
    } else if (index == 1) {
      carbonIcon = CarbonIcons.search; // Search icon
    } else {
      carbonIcon = CarbonIcons.home; // Fallback
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      transitionBuilder: (Widget child, Animation<double> animation) {
        return FadeTransition(
          opacity: animation,
          child: Transform.scale(
            scale: isSelected ? 1.0 + (animation.value * 0.1) : 1.0,
            child: child,
          ),
        );
      },
      child: isSelected
          ? Icon(
              carbonIcon,
              key: ValueKey('carbon_$index'),
              size: 24,
              color: context.colors.accent,
            )
          : SvgPicture.asset(
              iconPath,
              key: ValueKey('svg_$index'),
              width: 20,
              height: 20,
              colorFilter: ColorFilter.mode(
                context.colors.textPrimary,
                BlendMode.srcIn,
              ),
            ),
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
  }
}
