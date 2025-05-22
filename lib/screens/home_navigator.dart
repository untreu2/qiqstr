import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:qiqstr/screens/feed_page.dart';
import 'package:qiqstr/screens/users_search_page.dart';

class HomeNavigator extends StatefulWidget {
  final String npub;
  const HomeNavigator({Key? key, required this.npub}) : super(key: key);

  @override
  State<HomeNavigator> createState() => _HomeNavigatorState();
}

class _HomeNavigatorState extends State<HomeNavigator> {
  int _currentIndex = 0;

  late final List<Widget> _pages = [
    FeedPage(npub: widget.npub),
    const UserSearchPage(),
    const SizedBox(),
    const SizedBox(),
  ];

  void _handleAction(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex >= 2 ? 0 : _currentIndex,
        children: _pages,
      ),
      extendBody: true,
      bottomNavigationBar: ClipRRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: BottomNavigationBar(
            backgroundColor: Colors.black.withOpacity(0.5),
            type: BottomNavigationBarType.fixed,
            currentIndex: _currentIndex,
            showSelectedLabels: false,
            showUnselectedLabels: false,
            selectedItemColor: Colors.amber,
            unselectedItemColor: Colors.white70,
            onTap: (index) {
              if (index == 2) {
                _handleAction("Designing: DMs");
              } else if (index == 3) {
                _handleAction("Designing: Notifications");
              } else {
                setState(() => _currentIndex = index);
              }
            },
            items: [
              BottomNavigationBarItem(
                icon: SvgPicture.asset(
                  'assets/home_gap.svg',
                  width: 18,
                  height: 18,
                  color: _currentIndex == 0 ? Colors.amber : Colors.white70,
                ),
                label: '',
              ),
              BottomNavigationBarItem(
                icon: SvgPicture.asset(
                  'assets/search_button.svg',
                  width: 18,
                  height: 18,
                  color: _currentIndex == 1 ? Colors.amber : Colors.white70,
                ),
                label: '',
              ),
              BottomNavigationBarItem(
                icon: SvgPicture.asset(
                  'assets/dm_button.svg',
                  width: 18,
                  height: 18,
                  color: Colors.white70,
                ),
                label: '',
              ),
              BottomNavigationBarItem(
                icon: SvgPicture.asset(
                  'assets/notification_button.svg',
                  width: 18,
                  height: 18,
                  color: Colors.white70,
                ),
                label: '',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
