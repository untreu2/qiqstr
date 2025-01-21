import 'package:flutter/material.dart';
import 'package:qiqstr/screens/base_feed_page.dart';
import 'package:qiqstr/services/qiqstr_service.dart';
import 'package:qiqstr/widgets/sidebar_widget.dart';
import 'package:qiqstr/models/user_model.dart';

class FeedPage extends BaseFeedPage {
  final DataService dataService;

   FeedPage({
    Key? key,
    required String npub,
  })  : dataService = DataService(npub: npub, dataType: DataType.Feed),
        super(key: key, npub: npub, dataType: DataType.Feed);

  @override
  BaseFeedPageState<FeedPage> createState() => _FeedPageState();
}

class _FeedPageState extends BaseFeedPageState<FeedPage> {
  UserModel? user;

  @override
  void initState() {
    super.initState();
    _loadUserProfile();
  }

  Future<void> _loadUserProfile() async {
    await widget.dataService.initialize();
    final profileData = await widget.dataService.getCachedUserProfile(widget.npub);
    setState(() {
      user = UserModel.fromCachedProfile(widget.npub, profileData);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(

      drawer: SidebarWidget(user: user),
      body: super.build(context),
    );
  }
}
