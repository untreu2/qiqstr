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
  DataService? dataService;
  late ScrollController _scrollController;
  bool _isInitializing = true;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController()..addListener(_scrollListener);

    // Defer all initialization until after page transition
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeDataServiceProgressively();
    });
  }

  Future<void> _initializeDataServiceProgressively() async {
    try {
      // Create DataService instance asynchronously
      dataService = DataService(
        npub: widget.user.npub,
        dataType: DataType.profile,
        onNewNote: (_) {},
        onReactionsUpdated: (_, __) {},
        onRepliesUpdated: (_, __) {},
        onRepostsUpdated: (_, __) {},
        onReactionCountUpdated: (_, __) {},
        onReplyCountUpdated: (_, __) {},
        onRepostCountUpdated: (_, __) {},
      );

      // Phase 1: Immediate lightweight setup (no blocking operations)
      await dataService!.initializeLightweight();

      if (mounted) {
        setState(() {
          _isInitializing = false;
        });
      }

      // Phase 2: Heavy operations in background after UI is responsive
      Future.delayed(const Duration(milliseconds: 50), () {
        if (mounted && dataService != null) {
          dataService!.initializeHeavyOperations().then((_) {
            if (mounted && dataService != null) {
              // Initialize connections to start loading notes
              dataService!.initializeConnections();
            }
          }).catchError((e) {
            print('[ProfilePage] Heavy operations error: $e');
            // Don't show error to user, just log it
          });
        }
      });
    } catch (e) {
      print('[ProfilePage] Lightweight initialization error: $e');
      if (mounted) {
        setState(() {
          _isInitializing = false;
        });
      }
      // Continue anyway - the UI should still work with basic functionality
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    dataService?.closeConnections();
    super.dispose();
  }

  void _scrollListener() {
    // Infinite scroll support
    dataService?.onScrollPositionChanged(
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
          if (_isInitializing)
            _buildLoadingState(context)
          else
            RefreshIndicator(
              onRefresh: () async {
                if (dataService != null) {
                  await dataService!.refreshNotes();
                }
              },
              child: CustomScrollView(
                controller: _scrollController,
                physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                cacheExtent: 1500,
                slivers: [
                  SliverToBoxAdapter(
                    child: ProfileInfoWidget(
                      user: widget.user,
                      sharedDataService: dataService,
                    ),
                  ),
                  NoteListWidget(
                    npub: widget.user.npub,
                    dataType: DataType.profile,
                    sharedDataService: dataService,
                  ),
                ],
              ),
            ),
          _buildFloatingBackButton(context),
        ],
      ),
    );
  }

  Widget _buildLoadingState(BuildContext context) {
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      slivers: [
        SliverToBoxAdapter(
          child: ProfileInfoWidget(
            user: widget.user,
            sharedDataService: dataService,
          ),
        ),
        SliverToBoxAdapter(
          child: Container(
            padding: const EdgeInsets.all(32),
            child: Center(
              child: Column(
                children: [
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        context.colors.accent,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Loading notes...',
                    style: TextStyle(
                      color: context.colors.textSecondary,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
