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

  Widget _buildCustomBottomBar() {
    List<Map<String, dynamic>> items = [
      {'icon': 'assets/home_gap.svg', 'index': 0},
      {'icon': 'assets/search_button.svg', 'index': 1},
      {'icon': 'assets/dm_button.svg', 'index': 2},
      {'icon': 'assets/notification_button.svg', 'index': 3},
    ];

    return Container(
      height: 86,
      width: double.infinity,
      color: Colors.black,
      child: Row(
        children: items.map((item) {
          final bool isSelected = _currentIndex == item['index'];
          return Expanded(
            child: GestureDetector(
              onTap: () {
                if (item['index'] == 2) {
                  _handleAction("Designing: DMs");
                } else if (item['index'] == 3) {
                  _handleAction("Designing: Notifications");
                } else {
                  setState(() => _currentIndex = item['index']);
                }
              },
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Spacer(flex: 2),
                  SvgPicture.asset(
                    item['icon'],
                    width: 20,
                    height: 20,
                    color: isSelected ? Colors.amber : Colors.white70,
                  ),
                  const Spacer(flex: 5),
                ],
              ),
            ),
          );
        }).toList(),
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
      extendBody: false,
      bottomNavigationBar: _buildCustomBottomBar(),
    );
  }
}
