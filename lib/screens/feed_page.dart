import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:qiqstr/widgets/note_list_widget.dart';
import 'package:qiqstr/services/qiqstr_service.dart';
import 'package:qiqstr/widgets/sidebar_widget.dart';
import 'package:qiqstr/models/user_model.dart';
import 'package:qiqstr/screens/share_note.dart';

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: SidebarWidget(user: user),
      floatingActionButton: FloatingActionButton(
        shape: const CircleBorder(),
        backgroundColor: Colors.white,
        onPressed: () {
          showDialog(
            context: context,
            builder: (_) => ShareNoteDialog(dataService: dataService),
          );
        },
        child: SizedBox(
          width: 24.0,
          height: 24.0,
          child: SvgPicture.asset(
            'assets/new_post_button.svg',
            color: Colors.black,
            fit: BoxFit.contain,
          ),
        ),
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : errorMessage != null
              ? Center(child: Text(errorMessage!))
              : NestedScrollView(
                  headerSliverBuilder:
                      (BuildContext context, bool innerBoxIsScrolled) {
                    return [
                      SliverAppBar(
                        title: const Text(
                          'qiqstr',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 20.0,
                          ),
                        ),
                        pinned: false,
                        snap: false,
                        backgroundColor: Colors.black,
                        iconTheme: const IconThemeData(color: Colors.white),
                      ),
                    ];
                  },
                  body: NoteListWidget(
                    npub: widget.npub,
                    dataType: DataType.Feed,
                  ),
                ),
    );
  }
}
