import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:bounce/bounce.dart';
import 'package:qiqstr/services/data_service.dart';
import 'package:qiqstr/widgets/note_list_widget.dart';
import 'package:qiqstr/models/user_model.dart';
import 'package:qiqstr/widgets/profile_info_widget.dart';
import '../theme/theme_manager.dart';

class ProfilePage extends StatefulWidget {
  final UserModel user;

  const ProfilePage({super.key, required this.user});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  late DataService dataService;
  late ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    dataService = DataService(npub: widget.user.npub, dataType: DataType.profile);
    _scrollController = ScrollController()..addListener(_scrollListener);

    // Initialize DataService
    WidgetsBinding.instance.addPostFrameCallback((_) {
      dataService.initialize();
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    dataService.closeConnections();
    super.dispose();
  }

  void _scrollListener() {
    // Infinite scroll support
    dataService.onScrollPositionChanged(
      _scrollController.position.pixels,
      _scrollController.position.maxScrollExtent,
    );
  }

  Widget _buildFloatingBackButton(BuildContext context) {
    final double topPadding = MediaQuery.of(context).padding.top;

    return Positioned(
      top: topPadding - 8,
      left: 16,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(25.0),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: context.colors.backgroundTransparent,
              border: Border.all(
                color: context.colors.borderLight,
                width: 1.5,
              ),
              borderRadius: BorderRadius.circular(25.0),
            ),
            child: Bounce(
              scaleFactor: 0.85,
              onTap: () => Navigator.pop(context),
              behavior: HitTestBehavior.opaque,
              child: Icon(
                Icons.arrow_back,
                color: context.colors.textSecondary,
                size: 20,
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.background,
      body: Stack(
        children: [
          RefreshIndicator(
            onRefresh: () async {
              await dataService.refreshNotes();
            },
            child: CustomScrollView(
              controller: _scrollController,
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              cacheExtent: 1500,
              slivers: [
                SliverToBoxAdapter(
                  child: ProfileInfoWidget(user: widget.user),
                ),
                NoteListWidget(
                  npub: widget.user.npub,
                  dataType: DataType.profile,
                ),
              ],
            ),
          ),
          _buildFloatingBackButton(context),
        ],
      ),
    );
  }
}
