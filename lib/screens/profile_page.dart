import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:bounce/bounce.dart';
import 'package:qiqstr/services/data_service.dart';
import 'package:qiqstr/widgets/note_list_widget.dart';
import 'package:qiqstr/models/user_model.dart';
import 'package:qiqstr/widgets/profile_info_widget.dart';
import 'package:nostr_nip19/nostr_nip19.dart';
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
  bool _profileInfoLoaded = false;
  String? _userHexKey;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController()..addListener(_scrollListener);

    // Convert npub to hex format for DataService
    _userHexKey = _convertNpubToHex(widget.user.npub);

    // Initialize immediately without loading states
    _initializeImmediately();
  }

  String? _convertNpubToHex(String npub) {
    try {
      if (npub.startsWith('npub1')) {
        return decodeBasicBech32(npub, 'npub');
      } else if (_isValidHex(npub)) {
        return npub; // Already hex format
      }
    } catch (e) {
      print('[ProfilePage] Error converting npub to hex: $e');
    }
    return npub; // Return original if conversion fails
  }

  bool _isValidHex(String value) {
    if (value.isEmpty || value.length != 64) return false;
    return RegExp(r'^[0-9a-fA-F]+$').hasMatch(value);
  }

  void _initializeImmediately() {
    // Create DataService and show content immediately
    _createDataServiceEarly();

    // Show profile info immediately
    if (mounted) {
      setState(() {
        _profileInfoLoaded = true;
      });
    }

    // Start notes loading in background
    Future.microtask(() => _startNotesLoading());
  }

  Future<void> _createDataServiceEarly() async {
    try {
      // Create DataService early so ProfileInfoWidget can use it
      // Use hex format for DataService
      dataService = DataService(
        npub: _userHexKey ?? widget.user.npub,
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
    try {
      // DataService should already exist from _createDataServiceEarly()
      if (dataService == null) {
        print('[ProfilePage] DataService not found, creating new one');
        dataService = DataService(
          npub: _userHexKey ?? widget.user.npub,
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
          _buildStagedContent(context),
          _buildFloatingBackButton(context),
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
          // Show profile info immediately
          SliverToBoxAdapter(
            child: ProfileInfoWidget(
              user: widget.user,
              sharedDataService: dataService,
            ),
          ),

          // Show notes section after profile info is loaded
          if (_profileInfoLoaded && dataService != null)
            NoteListWidget(
              npub: _userHexKey ?? widget.user.npub,
              dataType: DataType.profile,
              sharedDataService: dataService,
            ),
        ],
      ),
    );
  }
}
