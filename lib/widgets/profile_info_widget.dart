import 'package:flutter/material.dart';
import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:qiqstr/models/user_model.dart';
import 'package:qiqstr/screens/edit_profile.dart';
import 'package:qiqstr/services/data_service.dart';
import 'package:hive/hive.dart';
import 'package:qiqstr/models/following_model.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shimmer/shimmer.dart';

class ProfileInfoWidget extends StatefulWidget {
  final UserModel user;

  const ProfileInfoWidget({super.key, required this.user});

  @override
  State<ProfileInfoWidget> createState() => _ProfileInfoWidgetState();
}

class _ProfileInfoWidgetState extends State<ProfileInfoWidget> {
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  bool? _isFollowing;
  String? _currentUserNpub;
  late Box<FollowingModel> _followingBox;
  DataService? _dataService;

  int? _followingCount;
  bool _isLoadingFollowing = true;

  @override
  void initState() {
    super.initState();
    _initFollowStatus();
    _loadFollowingCount();
  }

  Future<void> _initFollowStatus() async {
    _currentUserNpub = await _secureStorage.read(key: 'npub');
    if (_currentUserNpub == null || _currentUserNpub == widget.user.npub)
      return;

    _followingBox = await Hive.openBox<FollowingModel>('followingBox');
    final model = _followingBox.get('following_$_currentUserNpub');
    final isFollowing = model?.pubkeys.contains(widget.user.npub) ?? false;
    setState(() {
      _isFollowing = isFollowing;
    });

    _dataService =
        DataService(npub: _currentUserNpub!, dataType: DataType.Profile);
    await _dataService!.initialize();
  }

  Future<void> _loadFollowingCount() async {
    try {
      final dataService =
          DataService(npub: widget.user.npub, dataType: DataType.Profile);
      await dataService.initialize();
      final followingList =
          await dataService.getFollowingList(widget.user.npub);
      setState(() {
        _followingCount = followingList.length;
        _isLoadingFollowing = false;
      });
    } catch (e) {
      setState(() {
        _isLoadingFollowing = false;
      });
    }
  }

  Future<void> _toggleFollow() async {
    if (_currentUserNpub == null || _dataService == null) return;

    setState(() {
      _isFollowing = !_isFollowing!;
    });

    try {
      if (_isFollowing!) {
        await _dataService!.sendFollow(widget.user.npub);
      } else {
        await _dataService!.sendUnfollow(widget.user.npub);
      }
    } catch (e) {
      setState(() {
        _isFollowing = !_isFollowing!;
      });
    }
  }

  Future<void> _onOpen(LinkableElement link) async {
    final uri = Uri.parse(link.url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.user;
    final screenWidth = MediaQuery.of(context).size.width;
    final websiteUrl = user.website.isNotEmpty &&
            !(user.website.startsWith("http://") ||
                user.website.startsWith("https://"))
        ? "https://${user.website}"
        : user.website;

    return Container(
      color: Colors.black,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CachedNetworkImage(
            imageUrl: user.banner,
            width: screenWidth,
            height: 130,
            fit: BoxFit.cover,
            placeholder: (_, __) => Container(
              height: 130,
              width: screenWidth,
              color: Colors.grey[700],
            ),
            errorWidget: (_, __, ___) => Container(
              height: 130,
              width: screenWidth,
              color: Colors.black,
            ),
          ),
          Container(
            transform: Matrix4.translationValues(0, -30, 0),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _buildAvatar(user),
                    const Spacer(),
                    if (_currentUserNpub != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 35.0),
                        child: (widget.user.npub == _currentUserNpub)
                            ? GestureDetector(
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => EditOwnProfilePage(),
                                    ),
                                  );
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16),
                                  height: 34,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: Colors.white10,
                                    borderRadius: BorderRadius.circular(24),
                                    border: Border.all(color: Colors.white30),
                                  ),
                                  child: const Text(
                                    'Edit profile',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              )
                            : (_isFollowing != null)
                                ? GestureDetector(
                                    onTap: _toggleFollow,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 16),
                                      height: 34,
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        color: Colors.white10,
                                        borderRadius: BorderRadius.circular(24),
                                        border:
                                            Border.all(color: Colors.white30),
                                      ),
                                      child: Text(
                                        _isFollowing! ? 'Following' : 'Follow',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                  )
                                : const SizedBox.shrink(),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                _buildNameRow(user),
                const SizedBox(height: 6),
                if (user.lud16.isNotEmpty)
                  Text(
                    user.lud16,
                    style: TextStyle(fontSize: 13, color: Colors.amber[600]),
                  ),
                if (user.about.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Text(
                      user.about,
                      style:
                          const TextStyle(fontSize: 14, color: Colors.white70),
                    ),
                  ),
                if (user.website.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0, bottom: 1),
                    child: Row(
                      children: [
                        const Icon(Icons.link,
                            color: Color(0xFFECB200), size: 14),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Linkify(
                            onOpen: _onOpen,
                            text: websiteUrl,
                            style: const TextStyle(
                              fontSize: 13,
                              color: Color(0xFFECB200),
                            ),
                            linkStyle: const TextStyle(
                              fontSize: 13,
                              color: Color(0xFFECB200),
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 16),
                _buildFollowingCount(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAvatar(UserModel user) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.black, width: 3),
      ),
      child: CircleAvatar(
        radius: 40,
        backgroundImage: user.profileImage.isNotEmpty
            ? CachedNetworkImageProvider(user.profileImage)
            : null,
        backgroundColor: user.profileImage.isEmpty ? Colors.grey : null,
        child: user.profileImage.isEmpty
            ? const Icon(Icons.person, size: 40, color: Colors.white)
            : null,
      ),
    );
  }

  Widget _buildNameRow(UserModel user) {
    return Row(
      children: [
        Flexible(
          child: RichText(
            text: TextSpan(
              style: const TextStyle(fontSize: 24),
              children: [
                TextSpan(
                  text: user.name.isNotEmpty
                      ? user.name
                      : user.nip05.split('@').first,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                if (user.nip05.isNotEmpty && user.nip05.contains('@'))
                  TextSpan(
                    text: '@${user.nip05.split('@').last}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFFECB200),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFollowingCount() {
    if (_isLoadingFollowing) {
      return Shimmer.fromColors(
        baseColor: Colors.white24,
        highlightColor: Colors.white54,
        child: Container(
          width: 80,
          height: 20,
          color: Colors.white,
        ),
      );
    }

    return Row(
      children: [
        Text(
          'Following: ',
          style: const TextStyle(color: Colors.white70, fontSize: 14),
        ),
        Text(
          '$_followingCount',
          style: const TextStyle(color: Colors.white, fontSize: 14),
        ),
      ],
    );
  }
}
