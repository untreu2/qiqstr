import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:qiqstr/screens/feed_page.dart';
import 'package:qiqstr/screens/users_search_page.dart';
import 'package:qiqstr/screens/notification_page.dart';
import 'package:qiqstr/services/data_service.dart';

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

    return ClipRRect(
      borderRadius: BorderRadius.zero,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          height: 86,
          width: double.infinity,
          padding: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(color: Colors.black.withOpacity(0.5)),
          child: Row(
            children: items.map((item) {
              final bool isSelected = _currentIndex == item['index'];
              final index = item['index'];

              return Expanded(
                child: GestureDetector(
                  onTap: () {
                    if (index == 2) {
                      
                      _handleAction("Designing: DMs");
                    } else if (index == 3) {
                      widget.dataService.markAllUserNotificationsAsRead().then((_) {
                        if (mounted) setState(() => _currentIndex = index);
                      });
                    } else {
                      if (mounted)
                        setState(() {
                        _currentIndex = index;
                      });
                    }
                  },
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Spacer(flex: 3),
                      if (index == 3)
                        Stack(
                          clipBehavior: Clip.none,
                          children: [
                            SvgPicture.asset(
                              item['icon'],
                              width: 20,
                              height: 20,
                              color: isSelected ? Colors.amber : Colors.white70,
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
                                      color: Colors.white,
                                      shape: BoxShape.circle,
                                      border: Border.all(color: Colors.black, width: 0.5),
                                    ),
                                    constraints: const BoxConstraints(
                                      minWidth: 14,
                                      minHeight: 14,
                                    ),
                                    child: Text('$count',
                                        style: const TextStyle(
                                          color: Colors.black,
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
                          color: isSelected ? Colors.amber : Colors.white70,
                        ),
                      const Spacer(flex: 4),
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
