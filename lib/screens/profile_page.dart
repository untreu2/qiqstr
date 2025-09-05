import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:bounce/bounce.dart';
import 'package:qiqstr/services/data_service.dart';
import 'package:qiqstr/services/data_service_manager.dart';
import 'package:qiqstr/services/memory_manager.dart';
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
    _userHexKey = _convertNpubToHex(widget.user.npub);
    _initializeImmediately();
  }

  @override
  void dispose() {
    _scrollController.dispose();

    if (_userHexKey != null || widget.user.npub.isNotEmpty) {
      DataServiceManager.instance.releaseProfileService(_userHexKey ?? widget.user.npub);
    }

    super.dispose();
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
    Future.microtask(() {
      try {
        final memoryManager = MemoryManager.instance;
        memoryManager.prepareForProfileTransition();
        memoryManager.optimizeForProfileView();
      } catch (e) {
        print('[ProfilePage] Memory optimization error: $e');
      }
    });

    _createDataServiceEarly();
    if (mounted) {
      setState(() {
        _profileInfoLoaded = true;
      });
    }

    _startNotesLoading();
  }

  Future<void> _createDataServiceEarly() async {
    try {
      dataService = DataServiceManager.instance.getOrCreateService(
        npub: _userHexKey ?? widget.user.npub,
        dataType: DataType.profile,
        onNewNote: (_) {
          if (mounted) setState(() {});
        },
        onReactionsUpdated: (_, __) {
          if (mounted) setState(() {});
        },
        onRepliesUpdated: (_, __) {
          if (mounted) setState(() {});
        },
        onRepostsUpdated: (_, __) {
          if (mounted) setState(() {});
        },
        onReactionCountUpdated: (_, __) {
          if (mounted) setState(() {});
        },
        onReplyCountUpdated: (_, __) {
          if (mounted) setState(() {});
        },
        onRepostCountUpdated: (_, __) {
          if (mounted) setState(() {});
        },
      );

      await dataService!.initializeLightweight();
      if (mounted) {
        setState(() {});
      }

      print('[ProfilePage] Ultra-fast service created for smooth transition: ${_userHexKey ?? widget.user.npub}');
    } catch (e) {
      print('[ProfilePage] Early DataService creation error: $e');
    }
  }

  Future<void> _startNotesLoading() async {
    try {
      dataService = DataServiceManager.instance.getOrCreateService(
        npub: _userHexKey ?? widget.user.npub,
        dataType: DataType.profile,
        onNewNote: (_) {
          if (mounted) setState(() {});
        },
        onReactionsUpdated: (_, __) {
          if (mounted) setState(() {});
        },
        onRepliesUpdated: (_, __) {
          if (mounted) setState(() {});
        },
        onRepostsUpdated: (_, __) {
          if (mounted) setState(() {});
        },
        onReactionCountUpdated: (_, __) {
          if (mounted) setState(() {});
        },
        onReplyCountUpdated: (_, __) {
          if (mounted) setState(() {});
        },
        onRepostCountUpdated: (_, __) {
          if (mounted) setState(() {});
        },
      );

      await dataService!.initializeLightweight();

      if (mounted && dataService != null) {
        final heavyOpsFuture = dataService!.initializeHeavyOperations();

        final connectionsFuture = Future.delayed(const Duration(milliseconds: 10)).then((_) => dataService!.initializeConnections());

        Future.wait([heavyOpsFuture, connectionsFuture], eagerError: false).catchError((e) {
          print('[ProfilePage] Ultra-fast parallel initialization error: $e');
        });
      }
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
