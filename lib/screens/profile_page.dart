import 'package:flutter/material.dart';
import 'package:qiqstr/widgets/note_list_widget.dart';
import 'package:qiqstr/widgets/sidebar_widget.dart';
import 'package:qiqstr/services/qiqstr_service.dart';
import 'package:qiqstr/models/user_model.dart';
import 'package:qiqstr/widgets/profile_info_widget.dart';

class ProfilePage extends StatefulWidget {
  final String npub;

  const ProfilePage({super.key, required this.npub});

  @override
  _ProfilePageState createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  UserModel? user;
  late DataService dataService;
  bool isLoading = true;
  String? errorMessage;
  bool _isProfileInfoVisible = true;
  final double _separatorHeight = 8;

  @override
  void initState() {
    super.initState();
    dataService = DataService(npub: widget.npub, dataType: DataType.Profile);
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
    if (notification is ScrollUpdateNotification) {
      final double offset = notification.metrics.pixels;
      if (offset <= 0 && !_isProfileInfoVisible) {
        setState(() {
          _isProfileInfoVisible = true;
        });
      } else if (offset > 0 && _isProfileInfoVisible) {
        setState(() {
          _isProfileInfoVisible = false;
        });
      }
    }
    return false;
  }

  @override
  void dispose() {
    dataService.closeConnections();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: SidebarWidget(user: user),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : errorMessage != null
              ? Center(child: Text(errorMessage!))
              : Column(
                  children: [
                    AnimatedSize(
                      duration: const Duration(milliseconds: 600),
                      curve: Curves.easeInOut,
                      child: _isProfileInfoVisible && user != null
                          ? Container(
                              color: Colors.black,
                              child: ProfileInfoWidget(user: user!),
                            )
                          : Container(),
                    ),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 600),
                      height: _isProfileInfoVisible ? _separatorHeight : 0,
                      curve: Curves.easeInOut,
                    ),
                    Expanded(
                      child: NotificationListener<ScrollNotification>(
                        onNotification: _handleScrollNotification,
                        child: NoteListWidget(
                          npub: widget.npub,
                          dataType: DataType.Profile,
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }
}
