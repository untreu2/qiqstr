import 'dart:ui';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:qiqstr/screens/feed_page.dart';
import 'package:bounce/bounce.dart';
import 'package:qiqstr/screens/users_search_page.dart';
import 'package:qiqstr/screens/notification_page.dart';
import 'package:qiqstr/screens/share_note.dart';
import 'package:qiqstr/services/data_service.dart';
import '../colors.dart';

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
                filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                child: LiquidGlass(
                  shape: LiquidRoundedSuperellipse(
                    borderRadius: Radius.circular(25.0),
                  ),
                  settings: LiquidGlassSettings(
                    thickness: 15,
                    glassColor: Color(0xFF000000),
                    lightIntensity: 0.8,
                    ambientStrength: 0.3,
                  ),
                  child: Container(
                    height: 70,
                    decoration: BoxDecoration(
                      color: AppColors.backgroundTransparent,
                      border: Border.all(
                        color: AppColors.borderLight,
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
                                        color: isSelected ? AppColors.accent : AppColors.textSecondary,
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
                                                color: AppColors.surface,
                                                shape: BoxShape.circle,
                                                border: Border.all(color: AppColors.textPrimary, width: 0.5),
                                              ),
                                              constraints: const BoxConstraints(
                                                minWidth: 14,
                                                minHeight: 14,
                                              ),
                                              child: Text('$count',
                                                  style: const TextStyle(
                                                    color: AppColors.textPrimary,
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
                                    color: isSelected ? AppColors.accent : AppColors.textSecondary,
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
          ),
          const SizedBox(width: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(25.0),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: LiquidGlass(
                shape: LiquidRoundedSuperellipse(
                  borderRadius: Radius.circular(25.0),
                ),
                settings: LiquidGlassSettings(
                  thickness: 15,
                  glassColor: Color(0xFF000000),
                  lightIntensity: 0.8,
                  ambientStrength: 0.3,
                ),
                child: Container(
                  width: 70,
                  height: 70,
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.3),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.2),
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
                          color: AppColors.textSecondary,
                        ),
                      ],
                    ),
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
    return Scaffold(
      extendBody: true,
      body: IndexedStack(
        index: _currentIndex,
        children: _pages,
      ),
      bottomNavigationBar: _buildCustomBottomBar(),
    );
  }
}
