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
  bool _showFakeLoading = true;
  bool _showProfileInfo = false;
  bool _profileInfoLoaded = false;
  bool _notesLoading = false;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController()..addListener(_scrollListener);

    // Staged loading: Profile info first, then notes
    _startStagedLoading();
  }

  void _startStagedLoading() {
    // Create DataService immediately during fake loading so ProfileInfoWidget can use it
    _createDataServiceEarly();

    // Phase 1: Show fake loading for 200ms
    Future.delayed(const Duration(milliseconds: 200), () {
      if (mounted) {
        setState(() {
          _showFakeLoading = false;
          _showProfileInfo = true;
        });

        // Phase 2: Wait for profile info to settle, then start notes loading
        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted) {
            setState(() {
              _profileInfoLoaded = true;
            });

            // Phase 3: Add additional 200ms delay before fetching notes
            Future.delayed(const Duration(milliseconds: 200), () {
              if (mounted) {
                _startNotesLoading();
              }
            });
          }
        });
      }
    });
  }

  Future<void> _createDataServiceEarly() async {
    try {
      // Create DataService early so ProfileInfoWidget can use it
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

      // Do lightweight initialization immediately
      await dataService!.initializeLightweight();

      if (mounted) {
        setState(() {
          // Trigger rebuild so ProfileInfoWidget gets the DataService
        });
      }
    } catch (e) {
      print('[ProfilePage] Early DataService creation error: $e');
    }
  }

  Future<void> _startNotesLoading() async {
    if (mounted) {
      setState(() {
        _notesLoading = true;
      });
    }

    try {
      // DataService should already exist from _createDataServiceEarly()
      if (dataService == null) {
        print('[ProfilePage] DataService not found, creating new one');
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
        await dataService!.initializeLightweight();
      }

      if (mounted) {
        setState(() {
          _notesLoading = false;
        });
      }

      // Start heavy operations in background
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted && dataService != null) {
          dataService!.initializeHeavyOperations().then((_) {
            if (mounted && dataService != null) {
              dataService!.initializeConnections();
            }
          }).catchError((e) {
            print('[ProfilePage] Heavy operations error: $e');
          });
        }
      });
    } catch (e) {
      print('[ProfilePage] Notes loading error: $e');
      if (mounted) {
        setState(() {
          _notesLoading = false;
        });
      }
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
      backgroundColor: _showFakeLoading ? context.colors.background : context.colors.background,
      body: Stack(
        children: [
          if (_showFakeLoading) _buildFakeLoadingScreen(context) else _buildStagedContent(context),
          if (!_showFakeLoading) _buildFloatingBackButton(context),
        ],
      ),
    );
  }

  Widget _buildStagedContent(BuildContext context) {
    return RefreshIndicator(
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
          // Phase 1: Always show profile info first
          if (_showProfileInfo)
            SliverToBoxAdapter(
              child: ProfileInfoWidget(
                user: widget.user,
                sharedDataService: dataService,
              ),
            ),

          // Phase 2: Show notes section only after profile info is loaded
          if (_profileInfoLoaded) ...[
            if (_notesLoading)
              SliverToBoxAdapter(
                child: _buildNotesLoadingIndicator(context),
              )
            else if (dataService != null)
              NoteListWidget(
                npub: widget.user.npub,
                dataType: DataType.profile,
                sharedDataService: dataService,
              )
            else
              SliverToBoxAdapter(
                child: _buildNotesLoadingIndicator(context),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildNotesLoadingIndicator(BuildContext context) {
    return Container(
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
    );
  }

  Widget _buildFakeLoadingScreen(BuildContext context) {
    return Container(
      color: context.colors.background,
      child: Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(
              context.colors.accent,
            ),
          ),
        ),
      ),
    );
  }
}
