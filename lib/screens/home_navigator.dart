import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:bounce/bounce.dart';
import 'package:provider/provider.dart';

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

  Widget _buildWalletIcon(String iconPath, bool isSelected) {
    return SvgPicture.asset(
      iconPath,
      width: 17,
      height: 17,
      colorFilter: ColorFilter.mode(
        isSelected ? context.colors.accent : context.colors.textPrimary,
        BlendMode.srcIn,
      ),
    );
  }

  Widget _buildRegularIcon(Map<String, dynamic> item, bool isSelected) {
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
