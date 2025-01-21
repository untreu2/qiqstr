import 'package:flutter/material.dart';
import 'package:qiqstr/screens/base_feed_page.dart';
import 'package:qiqstr/services/qiqstr_service.dart';

class ProfilePage extends BaseFeedPage {
  const ProfilePage({Key? key, required String npub})
      : super(key: key, npub: npub, dataType: DataType.Profile);

  @override
  BaseFeedPageState<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends BaseFeedPageState<ProfilePage> {}
