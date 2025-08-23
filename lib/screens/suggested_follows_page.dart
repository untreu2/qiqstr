import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:hive/hive.dart';
import 'package:qiqstr/constants/suggestions.dart';
import 'package:qiqstr/models/user_model.dart';
import 'package:qiqstr/services/profile_service.dart';
import 'package:qiqstr/screens/home_navigator.dart';
import 'package:qiqstr/services/data_service.dart';
import 'package:qiqstr/theme/theme_manager.dart';
import 'package:nostr/nostr.dart';

class SuggestedFollowsPage extends StatefulWidget {
  final String npub;
  final DataService dataService;

  const SuggestedFollowsPage({
    super.key,
    required this.npub,
    required this.dataService,
  });

  @override
  State<SuggestedFollowsPage> createState() => _SuggestedFollowsPageState();
}

class _SuggestedFollowsPageState extends State<SuggestedFollowsPage> {
  List<UserModel> _suggestedUsers = [];
  Set<String> _selectedUsers = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSuggestedUsers();
  }

  final Map<String, String> _npubToHexMap = {};

  Future<void> _loadSuggestedUsers() async {
    setState(() => _isLoading = true);

    final profileService = ProfileService();
    final List<UserModel> users = [];

    for (String pubkeyHex in suggestedUsers) {
      try {
        final profileData = await profileService.getCachedUserProfile(pubkeyHex);
        final npubKey = Nip19.encodePubkey(pubkeyHex);

        _npubToHexMap[npubKey] = pubkeyHex;

        final user = UserModel.fromCachedProfile(npubKey, profileData);
        users.add(user);

        final box = await Hive.openBox<UserModel>('users');
        await box.put(pubkeyHex, user);

        print('Successfully loaded user: ${user.name.isNotEmpty ? user.name : 'Anonymous'} (${pubkeyHex.substring(0, 8)}...)');
      } catch (e) {
        print('Error loading user $pubkeyHex: $e');

        try {
          final npubKey = Nip19.encodePubkey(pubkeyHex);
          _npubToHexMap[npubKey] = pubkeyHex;

          final fallbackUser = UserModel(
            npub: npubKey,
            name: 'User ${users.length + 1}',
            about: 'A Nostr user',
            profileImage: '',
            nip05: '',
            banner: '',
            lud16: '',
            website: '',
            updatedAt: DateTime.now(),
          );
          users.add(fallbackUser);
          print('Added fallback user for $pubkeyHex');
        } catch (fallbackError) {
          print('Failed to create fallback user for $pubkeyHex: $fallbackError');
        }
      }
    }

    print('Total suggested users loaded: ${users.length}');
    setState(() {
      _suggestedUsers = users;

      _selectedUsers = users.map((user) => user.npub).toSet();
      _isLoading = false;
    });
  }

  void _toggleUserSelection(String npub) {
    setState(() {
      if (_selectedUsers.contains(npub)) {
        _selectedUsers.remove(npub);
      } else {
        _selectedUsers.add(npub);
      }
    });
  }

  Future<void> _continueToHome() async {
    setState(() => _isLoading = true);

    try {
      if (_selectedUsers.isNotEmpty) {
        print('Following ${_selectedUsers.length} selected users...');

        for (String npub in _selectedUsers) {
          try {
            final hexPubkey = _npubToHexMap[npub];
            if (hexPubkey != null) {
              await widget.dataService.sendFollow(hexPubkey);
              print('Successfully followed user: $npub (hex: ${hexPubkey.substring(0, 8)}...)');
            } else {
              print('Warning: Could not find hex pubkey for $npub');
            }
          } catch (e) {
            print('Error following user $npub: $e');
          }
        }

        print('Finished following process');

        await Future.delayed(const Duration(seconds: 2));
      }

      print('Closing current DataService...');
      await widget.dataService.closeConnections();

      await Future.delayed(const Duration(milliseconds: 500));

      print('Creating new DataService for feed mode...');
      final feedDataService = DataService(
        npub: widget.npub,
        dataType: DataType.feed,
      );

      print('Initializing new DataService...');
      await feedDataService.initialize();

      final followingList = await feedDataService.getFollowingList(widget.npub);
      print('Following list loaded with ${followingList.length} users: $followingList');

      print('New DataService initialized successfully with ${feedDataService.notes.length} cached notes');

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => HomeNavigator(
              npub: widget.npub,
              dataService: feedDataService,
            ),
          ),
        );
      }
    } catch (e) {
      print('Error in continue process: $e');

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => HomeNavigator(
              npub: widget.npub,
              dataService: widget.dataService,
            ),
          ),
        );
      }
    }
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 100, 24, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Here are some interesting people you might want to follow to get started.',
            style: TextStyle(
              fontSize: 16,
              color: context.colors.textSecondary,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUserTile(UserModel user) {
    final isSelected = _selectedUsers.contains(user.npub);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isSelected ? context.colors.primary : context.colors.border,
          width: isSelected ? 2 : 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _toggleUserSelection(user.npub),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 30,
                  backgroundImage: user.profileImage.isNotEmpty ? CachedNetworkImageProvider(user.profileImage) : null,
                  backgroundColor: Colors.grey.shade700,
                  child: user.profileImage.isEmpty
                      ? Icon(
                          Icons.person,
                          size: 36,
                          color: context.colors.textSecondary,
                        )
                      : null,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              user.name.isNotEmpty ? user.name : 'Anonymous',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: context.colors.textPrimary,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (user.nip05.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                '• ${user.nip05}',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: context.colors.secondary,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isSelected ? context.colors.primary : Colors.transparent,
                    border: Border.all(
                      color: isSelected ? context.colors.primary : context.colors.border,
                      width: 2,
                    ),
                  ),
                  child: isSelected
                      ? Icon(
                          Icons.check,
                          color: Colors.white,
                          size: 16,
                        )
                      : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _skipToHome() async {
    _selectedUsers.clear();
    await _continueToHome();
  }

  Widget _buildBottomSection() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
      decoration: BoxDecoration(
        color: context.colors.background,
        border: Border(
          top: BorderSide(color: context.colors.border),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: _skipToHome,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 16),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: context.colors.overlayLight,
                borderRadius: BorderRadius.circular(25),
                border: Border.all(color: context.colors.borderAccent),
              ),
              child: Text(
                'Skip',
                style: TextStyle(
                  color: context.colors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: _continueToHome,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 16),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: context.colors.buttonPrimary,
                borderRadius: BorderRadius.circular(25),
                border: Border.all(color: context.colors.borderAccent),
              ),
              child: Text(
                'Continue',
                style: TextStyle(
                  color: context.colors.background,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.background,
      body: _isLoading
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: context.colors.primary),
                  const SizedBox(height: 20),
                  Text(
                    'Loading suggested users...',
                    style: TextStyle(
                      color: context.colors.textSecondary,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            )
          : Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildHeader(),
                        const SizedBox(height: 48),
                        if (_suggestedUsers.isEmpty)
                          Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(
                                'No suggested users available at the moment.',
                                style: TextStyle(
                                  color: context.colors.textSecondary,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                          )
                        else
                          ...(_suggestedUsers.map((user) => _buildUserTile(user))),
                        const SizedBox(height: 120),
                      ],
                    ),
                  ),
                ),
                _buildBottomSection(),
              ],
            ),
    );
  }
}
