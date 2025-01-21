import 'package:flutter/material.dart';
import 'package:qiqstr/screens/base_feed_page.dart';
import 'package:qiqstr/services/qiqstr_service.dart';

class FeedPage extends BaseFeedPage {
  const FeedPage({Key? key, required String npub})
      : super(key: key, npub: npub, dataType: DataType.Feed);

  @override
  BaseFeedPageState<FeedPage> createState() => _FeedPageState();
}

class _FeedPageState extends BaseFeedPageState<FeedPage> {}
