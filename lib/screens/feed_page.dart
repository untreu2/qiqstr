import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:qiqstr/widgets/note_list_widget.dart';
import 'package:qiqstr/widgets/sidebar_widget.dart';
import 'package:qiqstr/services/qiqstr_service.dart';
import 'package:qiqstr/models/user_model.dart';

class FeedPage extends StatefulWidget {
  final String npub;

  const FeedPage({super.key, required this.npub});

  @override
  _FeedPageState createState() => _FeedPageState();
}

class _FeedPageState extends State<FeedPage> {
  UserModel? user;
  late DataService dataService;
  bool isLoading = true;
  String? errorMessage;
  bool _isAppBarVisible = true;

  @override
  void initState() {
    super.initState();
    dataService = DataService(npub: widget.npub, dataType: DataType.Feed);
    _loadUserProfile();
  }

  Future<void> _loadUserProfile() async {
    try {
      await dataService.initialize();
      final profileData = await dataService.getCachedUserProfile(widget.npub);
      setState(() {
        user = UserModel.fromCachedProfile(widget.npub, profileData);
        isLoading = false;
      });
    } catch (e) {
      setState(() {
        errorMessage = 'An error occurred while loading the profile.';
        isLoading = false;
      });
    }
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (notification is UserScrollNotification) {
      if (notification.direction == ScrollDirection.reverse) {
        if (_isAppBarVisible) {
          setState(() {
            _isAppBarVisible = false;
          });
        }
      } else if (notification.direction == ScrollDirection.forward) {
        if (!_isAppBarVisible) {
          setState(() {
            _isAppBarVisible = true;
          });
        }
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final double statusBarHeight = MediaQuery.of(context).padding.top;
    final double appBarHeight = kToolbarHeight + statusBarHeight;

    return Scaffold(
      drawer: SidebarWidget(user: user),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : errorMessage != null
              ? Center(child: Text(errorMessage!))
              : Column(
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      height: _isAppBarVisible ? appBarHeight : 0,
                      curve: Curves.easeInOut,
                      child: Container(
                        color: Colors.black,
                        child: SafeArea(
                          bottom: false,
                          child: AppBar(
                            title: const Text(
                              'qiqstr',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                fontSize: 20.0,
                              ),
                            ),
                            backgroundColor: Colors.black,
                            elevation: 0,
                            shadowColor: Colors.transparent,
                            surfaceTintColor: Colors.transparent,
                            automaticallyImplyLeading: true,
                            iconTheme: const IconThemeData(color: Colors.white),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: NotificationListener<ScrollNotification>(
                        onNotification: _handleScrollNotification,
                        child: NoteListWidget(
                          npub: widget.npub,
                          dataType: DataType.Feed,
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }
}
