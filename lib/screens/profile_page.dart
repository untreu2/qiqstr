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

  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();

    Future.delayed(const Duration(milliseconds: 1250), () {
      if (!mounted) return;

      _scrollController = ScrollController()..addListener(_scrollListener);
      _userHexKey = _convertNpubToHex(widget.user.npub);
      _initializeImmediately();

      setState(() {
        _isInitialized = true;
      });
    });
  }

  @override
  void dispose() {
    if (_isInitialized) {
      _scrollController.dispose();
    }
    dataService?.closeConnections();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return Scaffold(
        backgroundColor: context.colors.background,
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

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

  String? _convertNpubToHex(String npub) {
    try {
      if (npub.startsWith('npub1')) {
        return decodeBasicBech32(npub, 'npub');
      } else if (_isValidHex(npub)) {
        return npub;
      }
    } catch (e) {
      print('[ProfilePage] Error converting npub to hex: $e');
    }
    return npub;
  }

  bool _isValidHex(String value) {
    if (value.isEmpty || value.length != 64) return false;
    return RegExp(r'^[0-9a-fA-F]+$').hasMatch(value);
  }

  void _initializeImmediately() {
    _createDataServiceEarly();
    if (mounted) {
      setState(() {
        _profileInfoLoaded = true;
      });
    }
    Future.microtask(() => _startNotesLoading());
  }

  Future<void> _createDataServiceEarly() async {
    try {
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
      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      print('[ProfilePage] Early DataService creation error: $e');
    }
  }

  Future<void> _startNotesLoading() async {
    try {
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

  void _scrollListener() {
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
              border: Border.all(color: context.colors.borderLight, width: 1.5),
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
          SliverToBoxAdapter(
            child: ProfileInfoWidget(
              user: widget.user,
              sharedDataService: dataService,
            ),
          ),
          if (_profileInfoLoaded && dataService != null)
            NoteListWidgetFactory.create(
              npub: _userHexKey ?? widget.user.npub,
              dataType: DataType.profile,
              sharedDataService: dataService,
            ),
        ],
      ),
    );
  }
}
