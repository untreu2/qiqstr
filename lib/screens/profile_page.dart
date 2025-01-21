import 'package:flutter/material.dart';
import 'package:qiqstr/widgets/note_list_widget.dart';
import 'package:qiqstr/services/qiqstr_service.dart';
import 'package:qiqstr/widgets/sidebar_widget.dart';
import 'package:qiqstr/models/user_model.dart';
import 'package:qiqstr/widgets/profile_info_widget.dart';

class ProfilePage extends StatefulWidget {
  final String npub;

  const ProfilePage({Key? key, required this.npub}) : super(key: key);

  @override
  _ProfilePageState createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  UserModel? user;
  late DataService dataService;
  bool isLoading = true;
  String? errorMessage;

  @override
  void initState() {
    super.initState();
    dataService = DataService(
      npub: widget.npub,
      dataType: DataType.Profile,
    );
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
              : NestedScrollView(
                  headerSliverBuilder:
                      (BuildContext context, bool innerBoxIsScrolled) {
                    return [
                      SliverToBoxAdapter(
                        child: user != null
                            ? ProfileInfoWidget(user: user!)
                            : Container(),
                      ),
                    ];
                  },
                  body: NoteListWidget(
                    npub: widget.npub,
                    dataType: DataType.Profile,
                  ),
                ),
    );
  }
}
