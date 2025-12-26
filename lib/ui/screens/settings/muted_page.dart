import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../theme/theme_manager.dart';
import '../../../models/user_model.dart';
import '../../../core/di/app_di.dart';
import '../../../data/repositories/user_repository.dart';
import '../../../data/services/auth_service.dart';
import '../../../data/services/data_service.dart';
import '../../../data/services/mute_cache_service.dart';
import '../../../data/services/user_batch_fetcher.dart';
import '../../widgets/common/back_button_widget.dart';
import '../../widgets/common/title_widget.dart';
import '../../widgets/common/snackbar_widget.dart';
import 'package:carbon_icons/carbon_icons.dart';
import 'package:nostr_nip19/nostr_nip19.dart';

class MutedPage extends StatefulWidget {
  const MutedPage({super.key});

  @override
  State<MutedPage> createState() => _MutedPageState();
}

class _MutedPageState extends State<MutedPage> {
  List<UserModel> _mutedUsers = [];
  bool _isLoading = true;
  String? _error;
  final Map<String, bool> _unmutingStates = {};

  late final UserRepository _userRepository;
  late final AuthService _authService;
  late final DataService _dataService;
  late final MuteCacheService _muteCacheService;

  @override
  void initState() {
    super.initState();
    _userRepository = AppDI.get<UserRepository>();
    _authService = AppDI.get<AuthService>();
    _dataService = AppDI.get<DataService>();
    _muteCacheService = MuteCacheService.instance;
    _loadMutedUsers();
  }

  Future<void> _loadMutedUsers() async {
    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });

      final currentUserResult = await _authService.getCurrentUserNpub();
      if (currentUserResult.isError || currentUserResult.data == null) {
        if (mounted) {
          setState(() {
            _error = 'Not authenticated';
            _isLoading = false;
          });
        }
        return;
      }

      final currentUserNpub = currentUserResult.data!;
      String currentUserHex = currentUserNpub;
      
      if (currentUserNpub.startsWith('npub1')) {
        final hexResult = _authService.npubToHex(currentUserNpub);
        if (hexResult != null) {
          currentUserHex = hexResult;
        }
      }

      final mutedPubkeys = await _muteCacheService.getOrFetch(currentUserHex, () async {
        final result = await _dataService.getMuteList(currentUserHex);
        return result.isSuccess ? result.data : null;
      });

      if (mutedPubkeys == null || mutedPubkeys.isEmpty) {
        if (mounted) {
          setState(() {
            _mutedUsers = [];
            _isLoading = false;
          });
        }
        return;
      }

      final npubs = <String>[];
      for (final pubkey in mutedPubkeys) {
        String npub = pubkey;
        try {
          if (!pubkey.startsWith('npub1')) {
            npub = encodeBasicBech32(pubkey, 'npub');
          }
        } catch (e) {
          npub = pubkey;
        }
        npubs.add(npub);
      }

      final userResults = await _userRepository.getUserProfiles(npubs, priority: FetchPriority.high);

      final users = <UserModel>[];
      for (int i = 0; i < npubs.length; i++) {
        final npub = npubs[i];
        final pubkey = mutedPubkeys[i];
        final userResult = userResults[npub];
        if (userResult != null && userResult.isSuccess) {
          users.add(userResult.data!);
        } else {
          users.add(UserModel.create(
            pubkeyHex: pubkey,
            name: npub.length > 16 ? npub.substring(0, 16) : npub,
            about: '',
            profileImage: '',
            banner: '',
            website: '',
            nip05: '',
            lud16: '',
            updatedAt: DateTime.now(),
            nip05Verified: false,
          ));
        }
      }

      if (mounted) {
        setState(() {
          _mutedUsers = users;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _unmuteUser(UserModel user) async {
    if (_unmutingStates[user.pubkeyHex] == true) return;

    setState(() {
      _unmutingStates[user.pubkeyHex] = true;
    });

    try {
      final result = await _userRepository.unmuteUser(user.npub);
      
      if (mounted) {
        result.fold(
          (_) {
            setState(() {
              _mutedUsers.removeWhere((u) => u.pubkeyHex == user.pubkeyHex);
              _unmutingStates.remove(user.pubkeyHex);
            });
            AppSnackbar.success(context, 'User unmuted successfully');
          },
          (error) {
            setState(() {
              _unmutingStates.remove(user.pubkeyHex);
            });
            AppSnackbar.error(context, 'Failed to unmute user: $error');
          },
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _unmutingStates.remove(user.pubkeyHex);
        });
        AppSnackbar.error(context, 'Failed to unmute user: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeManager>(
      builder: (context, themeManager, child) {
        return Scaffold(
          backgroundColor: context.colors.background,
          body: Stack(
            children: [
              SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeader(context),
                    const SizedBox(height: 16),
                    _buildMutedSection(context),
                    const SizedBox(height: 150),
                  ],
                ),
              ),
              const BackButtonWidget.floating(),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top + 60),
      child: const TitleWidget(
        title: 'Muted',
        fontSize: 32,
        subtitle: "Manage your muted users.",
        padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
      ),
    );
  }

  Widget _buildMutedSection(BuildContext context) {
    if (_isLoading) {
      return Padding(
        padding: const EdgeInsets.all(32),
        child: Center(
          child: CircularProgressIndicator(
            color: context.colors.textPrimary,
          ),
        ),
      );
    }

    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(32),
        child: Center(
          child: Column(
            children: [
              Icon(
                CarbonIcons.warning,
                size: 48,
                color: context.colors.error,
              ),
              const SizedBox(height: 16),
              Text(
                'Error loading muted users',
                style: TextStyle(
                  color: context.colors.textPrimary,
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _error!,
                style: TextStyle(
                  color: context.colors.textSecondary,
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _loadMutedUsers,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_mutedUsers.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(32),
        child: Center(
          child: Column(
            children: [
              Icon(
                CarbonIcons.user_multiple,
                size: 48,
                color: context.colors.textSecondary,
              ),
              const SizedBox(height: 16),
              Text(
                'No muted users',
                style: TextStyle(
                  color: context.colors.textPrimary,
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Users you mute will appear here',
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

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          ..._mutedUsers.map((user) => _buildUserTile(context, user)),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildUserTile(BuildContext context, UserModel user) {
    final isUnmuting = _unmutingStates[user.pubkeyHex] == true;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: context.colors.overlayLight,
        borderRadius: BorderRadius.circular(40),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: user.profileImage.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: user.profileImage,
                    width: 40,
                    height: 40,
                    fit: BoxFit.cover,
                    placeholder: (context, url) => Container(
                      width: 40,
                      height: 40,
                      color: context.colors.avatarPlaceholder,
                      child: Icon(
                        CarbonIcons.user,
                        size: 20,
                        color: context.colors.textSecondary,
                      ),
                    ),
                    errorWidget: (context, url, error) => Container(
                      width: 40,
                      height: 40,
                      color: context.colors.avatarPlaceholder,
                      child: Icon(
                        CarbonIcons.user,
                        size: 20,
                        color: context.colors.textSecondary,
                      ),
                    ),
                  )
                : Container(
                    width: 40,
                    height: 40,
                    color: context.colors.avatarPlaceholder,
                    child: Icon(
                      CarbonIcons.user,
                      size: 20,
                      color: context.colors.textSecondary,
                    ),
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user.name,
                  style: TextStyle(
                    color: context.colors.textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (user.nip05.isNotEmpty)
                  Text(
                    user.nip05,
                    style: TextStyle(
                      color: context.colors.textSecondary,
                      fontSize: 14,
                    ),
                  ),
              ],
            ),
          ),
          GestureDetector(
            onTap: isUnmuting ? null : () => _unmuteUser(user),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: context.colors.overlayLight,
                borderRadius: BorderRadius.circular(40),
              ),
              child: isUnmuting
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(context.colors.textPrimary),
                      ),
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          CarbonIcons.notification_off,
                          size: 16,
                          color: context.colors.textPrimary,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Unmute',
                          style: TextStyle(
                            color: context.colors.textPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

