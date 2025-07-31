import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:qiqstr/screens/feed_page.dart';
import 'package:bounce/bounce.dart';
import 'package:qiqstr/screens/users_search_page.dart';
import 'package:qiqstr/screens/notification_page.dart';
import 'package:qiqstr/screens/share_note.dart';
import 'package:qiqstr/services/data_service.dart';
import '../theme/theme_manager.dart';
import 'package:provider/provider.dart';

class HomeNavigator extends StatefulWidget {
  final String npub;
  final DataService dataService;

  const HomeNavigator({
    Key? key,
    required this.npub,
    required this.dataService,
  }) : super(key: key);

  @override
  State<HomeNavigator> createState() => _HomeNavigatorState();
}

class _HomeNavigatorState extends State<HomeNavigator> {
  int _currentIndex = 0;

  late final List<Widget> _pages = [
    FeedPage(npub: widget.npub),
    const UserSearchPage(),
    const SizedBox(),
    NotificationPage(dataService: widget.dataService),
  ];

  void _handleAction(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  Widget _buildCustomBottomBar() {
    List<Map<String, dynamic>> items = [
      {'icon': 'assets/home_gap.svg', 'index': 0},
      {'icon': 'assets/search_button.svg', 'index': 1},
      {'icon': 'assets/dm_button.svg', 'index': 2},
      {'icon': 'assets/notification_button.svg', 'index': 3},
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 30.0),
      child: Row(
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(25.0),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Container(
                  height: 70,
                  decoration: BoxDecoration(
                    color: context.colors.backgroundTransparent,
                    border: Border.all(
                      color: context.colors.borderLight,
                      width: 1.5,
                    ),
                    borderRadius: BorderRadius.circular(25.0),
                  ),
                  child: Row(
                    children: items.map((item) {
                      final bool isSelected = _currentIndex == item['index'];
                      final index = item['index'];

                      return Expanded(
                        child: Bounce(
                          scaleFactor: 0.85,
                          onTap: () {
                            if (index == 2) {
                              _handleAction("Designing: DMs");
                            } else if (index == 3) {
                              widget.dataService.markAllUserNotificationsAsRead().then((_) {
                                if (mounted) setState(() => _currentIndex = index);
                              });
                            } else {
                              if (mounted) {
                                setState(() {
                                  _currentIndex = index;
                                });
                              }
                            }
                          },
                          behavior: HitTestBehavior.opaque,
                          child: SizedBox.expand(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                if (index == 3)
                                  Stack(
                                    clipBehavior: Clip.none,
                                    children: [
                                      SvgPicture.asset(
                                        item['icon'],
                                        width: 20,
                                        height: 20,
                                        color: isSelected ? context.colors.accent : context.colors.textSecondary,
                                      ),
                                      ValueListenableBuilder<int>(
                                        valueListenable: widget.dataService.unreadNotificationsCountNotifier,
                                        builder: (context, count, child) {
                                          if (count == 0) {
                                            return const SizedBox.shrink();
                                          }
                                          return Positioned(
                                            top: -4,
                                            right: -5,
                                            child: Container(
                                              padding: const EdgeInsets.all(1),
                                              decoration: BoxDecoration(
                                                color: context.colors.surface,
                                                shape: BoxShape.circle,
                                                border: Border.all(color: context.colors.textPrimary, width: 0.5),
                                              ),
                                              constraints: const BoxConstraints(
                                                minWidth: 14,
                                                minHeight: 14,
                                              ),
                                              child: Text('$count',
                                                  style: TextStyle(
                                                    color: context.colors.textPrimary,
                                                    fontSize: 9,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                  textAlign: TextAlign.center),
                                            ),
                                          );
                                        },
                                      ),
                                    ],
                                  )
                                else
                                  SvgPicture.asset(
                                    item['icon'],
                                    width: 20,
                                    height: 20,
                                    color: isSelected ? context.colors.accent : context.colors.textSecondary,
                                  ),
                              ],
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
          const SizedBox(width: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(25.0),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(
                width: 70,
                height: 70,
                decoration: BoxDecoration(
                  color: context.colors.backgroundTransparent,
                  border: Border.all(
                    color: context.colors.borderLight,
                    width: 1.5,
                  ),
                  borderRadius: BorderRadius.circular(25.0),
                ),
                child: Bounce(
                  scaleFactor: 0.85,
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ShareNotePage(dataService: widget.dataService),
                      ),
                    );
                  },
                  behavior: HitTestBehavior.opaque,
                  child: SizedBox.expand(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SvgPicture.asset(
                          'assets/new_post_button.svg',
                          width: 24,
                          height: 24,
                          color: context.colors.textSecondary,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeManager>(
      builder: (context, themeManager, child) {
        return Scaffold(
          extendBody: true,
          body: IndexedStack(
            index: _currentIndex,
            children: _pages,
          ),
          bottomNavigationBar: _buildCustomBottomBar(),
        );
      },
    );
  }
}
