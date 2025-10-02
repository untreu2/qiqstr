import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:bounce/bounce.dart';
import 'package:provider/provider.dart';
import 'package:carbon_icons/carbon_icons.dart';

import 'package:qiqstr/screens/feed_page.dart';
import 'package:qiqstr/screens/users_search_page.dart';
import 'package:qiqstr/screens/notification_page.dart';
import 'package:qiqstr/screens/share_note.dart';
import 'package:qiqstr/screens/wallet_page.dart';
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
      {'icon': 'wallet', 'index': 2, 'type': 'carbon'},
      {'icon': 'assets/notification_button.svg', 'index': 3, 'type': 'svg'},
    ];

    return RepaintBoundary(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 30.0),
        child: Row(
          children: [
            Expanded(
              child: RepaintBoundary(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(35.0),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 10.0, sigmaY: 10.0),
                    child: Container(
                      height: 70,
                      decoration: BoxDecoration(
                        color: context.colors.surface.withValues(alpha: 0.6),
                        border: Border.all(
                          color: context.colors.borderLight,
                          width: 1.5,
                        ),
                        borderRadius: BorderRadius.circular(35.0),
                      ),
                      child: Row(
                        children: items.map((item) {
                          final bool isSelected = _currentIndex == item['index'] as int;
                          final index = item['index'] as int;

                          return Expanded(
                            child: RepaintBoundary(
                              key: ValueKey('nav_item_$index'),
                              child: Bounce(
                                scaleFactor: 0.85,
                                onTap: () => _handleNavigation(index),
                                behavior: HitTestBehavior.opaque,
                                child: SizedBox.expand(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      if (index == 3)
                                        RepaintBoundary(
                                          child: _buildNotificationIcon(item['icon'] as String, isSelected),
                                        )
                                      else
                                        RepaintBoundary(
                                          child: _buildRegularIcon(item, isSelected),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            _buildPostButton(),
          ],
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

  Widget _buildPostButton() {
    return RepaintBoundary(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(35.0),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10.0, sigmaY: 10.0),
          child: Container(
            width: 70,
            height: 70,
            decoration: BoxDecoration(
              color: context.colors.surface.withValues(alpha: 0.6),
              border: Border.all(
                color: context.colors.borderLight,
                width: 1.5,
              ),
              borderRadius: BorderRadius.circular(35.0),
            ),
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
              child: SizedBox.expand(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    RepaintBoundary(
                      child: SvgPicture.asset(
                        'assets/new_post_button.svg',
                        width: 24,
                        height: 24,
                        colorFilter: ColorFilter.mode(
                          context.colors.textPrimary,
                          BlendMode.srcIn,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _handleNavigation(int index) {
    if (index == 3) {
      // Notification tab - just navigate
      if (mounted) setState(() => _currentIndex = index);
    } else if (index == 0) {
      // Feed tab - scroll to top if already selected
      if (_currentIndex == 0) {
        _feedPageKey.currentState?.scrollToTop();
      } else {
        if (mounted) setState(() => _currentIndex = index);
      }
    } else {
      // Other tabs
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
