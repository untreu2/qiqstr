import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:bounce/bounce.dart';
import 'package:provider/provider.dart';
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

class _HomeNavigatorState extends State<HomeNavigator> {
  int _currentIndex = 0;
  final GlobalKey<FeedPageState> _feedPageKey = GlobalKey<FeedPageState>();

  late final List<Widget> _pages = [
    FeedPage(key: _feedPageKey, npub: widget.npub),
    const UserSearchPage(),
    const WalletPage(),
    const NotificationPage(),
  ];

  Widget _buildCustomBottomBar() {
    const items = [
      {'icon': 'assets/home_gap.svg', 'index': 0, 'type': 'svg'},
      {'icon': 'assets/search_button.svg', 'index': 1, 'type': 'svg'},
      {'icon': 'add', 'index': -1, 'type': 'add'},
      {'icon': 'wallet', 'index': 2, 'type': 'carbon'},
      {'icon': 'assets/notification_button.svg', 'index': 3, 'type': 'svg'},
    ];

    return Container(
      decoration: BoxDecoration(
        color: context.colors.surface,
        border: Border(
          top: BorderSide(
            color: context.colors.borderLight,
            width: 0.5,
          ),
        ),
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
              
              final bool isSelected = _currentIndex == index;

              return Expanded(
                child: Bounce(
                  scaleFactor: 0.85,
                  onTap: () => _handleNavigation(index),
                  behavior: HitTestBehavior.opaque,
                  child: Center(
                    child: index == 3
                        ? _buildNotificationIcon(item['icon'] as String, isSelected)
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
    return SvgPicture.asset(
      iconPath,
      width: 20,
      height: 20,
      colorFilter: ColorFilter.mode(
        isSelected ? context.colors.accent : context.colors.textPrimary,
        BlendMode.srcIn,
      ),
    );
  }

  Widget _buildRegularIcon(Map<String, dynamic> item, bool isSelected) {
    if (item['type'] == 'carbon') {
      return Icon(
        CarbonIcons.flash,
        size: 22,
        color: isSelected ? context.colors.accent : context.colors.textPrimary,
      );
    } else {
      return SvgPicture.asset(
        item['icon'] as String,
        width: 20,
        height: 20,
        colorFilter: ColorFilter.mode(
          isSelected ? context.colors.accent : context.colors.textPrimary,
          BlendMode.srcIn,
        ),
      );
    }
  }

  void _handleNavigation(int index) {
    if (index == 3) {
      if (mounted) setState(() => _currentIndex = index);
    } else if (index == 0) {
      if (_currentIndex == 0) {
        _feedPageKey.currentState?.scrollToTop();
      } else {
        if (mounted) setState(() => _currentIndex = index);
      }
    } else {
      if (mounted) setState(() => _currentIndex = index);
    }
  }

  @override
  Widget build(BuildContext context) {
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
          bottomNavigationBar: _buildCustomBottomBar(),
        );
      },
    );
  }
}
