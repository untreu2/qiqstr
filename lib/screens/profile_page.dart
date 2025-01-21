import 'package:flutter/material.dart';
import 'package:qiqstr/widgets/note_list_widget.dart';
import 'package:qiqstr/services/qiqstr_service.dart';
import 'package:qiqstr/widgets/sidebar_widget.dart';
import 'package:qiqstr/models/user_model.dart';

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
        errorMessage = 'Profil yüklenirken bir hata oluştu.';
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
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            user?.banner.isNotEmpty == true
                                ? Image.network(
                                    user!.banner,
                                    width: double.infinity,
                                    height: 200.0,
                                    fit: BoxFit.cover,
                                  )
                                : Container(
                                    width: double.infinity,
                                    height: 200.0,
                                    color: Colors.black,
                                  ),
                            Container(
                              width: double.infinity,
                              color: Colors.black,
                              padding: const EdgeInsets.all(16.0),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  CircleAvatar(
                                    radius: 40.0,
                                    backgroundImage: user?.profileImage.isNotEmpty == true
                                        ? NetworkImage(user!.profileImage)
                                        : null,
                                    backgroundColor: user?.profileImage.isNotEmpty == false
                                        ? Colors.grey
                                        : null,
                                    child: user?.profileImage.isEmpty == true
                                        ? const Icon(
                                            Icons.person,
                                            size: 40.0,
                                            color: Colors.white,
                                          )
                                        : null,
                                  ),
                                  const SizedBox(width: 16.0),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          user?.name ?? 'Anonymous',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 20.0,
                                          ),
                                        ),
                                        if (user?.nip05.isNotEmpty == true)
                                          Text(
                                            user!.nip05,
                                            style: const TextStyle(
                                              color: Colors.white70,
                                              fontSize: 14.0,
                                            ),
                                          ),
                                        if (user?.about.isNotEmpty == true)
                                          Padding(
                                            padding: const EdgeInsets.only(top: 4.0),
                                            child: Text(
                                              user!.about,
                                              style: const TextStyle(
                                                color: Colors.white70,
                                                fontSize: 14.0,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16.0),
                          ],
                        ),
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
