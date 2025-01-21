import 'package:flutter/material.dart';
import 'package:qiqstr/widgets/note_list_widget.dart';
import 'package:qiqstr/services/qiqstr_service.dart';
import 'package:qiqstr/widgets/sidebar_widget.dart';
import 'package:qiqstr/models/user_model.dart';

class FeedPage extends StatefulWidget {
  final String npub;

  const FeedPage({Key? key, required this.npub}) : super(key: key);

  @override
  _FeedPageState createState() => _FeedPageState();
}

class _FeedPageState extends State<FeedPage> {
  UserModel? user;
  late DataService dataService;

  @override
  void initState() {
    super.initState();
    dataService = DataService(npub: widget.npub, dataType: DataType.Feed);
    _loadUserProfile();
  }

  Future<void> _loadUserProfile() async {
    await dataService.initialize();
    final profileData = await dataService.getCachedUserProfile(widget.npub);
    setState(() {
      user = UserModel.fromCachedProfile(widget.npub, profileData);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: SidebarWidget(user: user),
      body: NoteListWidget(
        npub: widget.npub,
        dataType: DataType.Feed,
      ),
    );
  }
}
