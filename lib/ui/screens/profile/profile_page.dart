import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:carbon_icons/carbon_icons.dart';
import 'package:bounce/bounce.dart';
import 'package:share_plus/share_plus.dart';
import '../../theme/theme_manager.dart';
import '../../../models/user_model.dart';
import '../../../models/note_model.dart';
import '../../widgets/user/profile_info_widget.dart';
import '../../widgets/common/back_button_widget.dart';
import '../../widgets/common/common_buttons.dart';
import 'package:qiqstr/ui/widgets/note/note_list_widget.dart' as widgets;
import '../../../core/di/app_di.dart';
import '../../../presentation/viewmodels/profile_viewmodel.dart';
import 'dart:async';
import '../../../core/ui/ui_state_builder.dart';

class ProfilePage extends StatefulWidget {
  final UserModel user;

  const ProfilePage({super.key, required this.user});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  late ScrollController _scrollController;
  late ProfileViewModel _profileViewModel;

  final ValueNotifier<List<NoteModel>> _notesNotifier = ValueNotifier([]);
  late final Map<String, UserModel> _profiles;
  final ValueNotifier<bool> _showUsernameBubbleNotifier = ValueNotifier<bool>(false);
  Timer? _scrollDebounceTimer;

  StreamSubscription<Map<String, UserModel>>? _profilesSubscription;

  @override
  void initState() {
    super.initState();
    _profiles = <String, UserModel>{};
    _scrollController = ScrollController()..addListener(_scrollListener);

    _profileViewModel = AppDI.get<ProfileViewModel>();
    _profileViewModel.initialize();

    _profiles[widget.user.npub] = widget.user;

    _profilesSubscription = _profileViewModel.profilesStream.listen((updatedProfiles) {
      if (mounted) {
        setState(() {
          _profiles.addAll(updatedProfiles);
        });
      }
    });

    _profileViewModel.initializeWithUser(widget.user.npub);
  }

  void _scrollListener() {
    if (!_scrollController.hasClients) return;
    
    _scrollDebounceTimer?.cancel();
    _scrollDebounceTimer = Timer(const Duration(milliseconds: 100), () {
      if (!mounted || !_scrollController.hasClients) return;
      
      final shouldShow = _scrollController.offset > 100;
      if (_showUsernameBubbleNotifier.value != shouldShow) {
        _showUsernameBubbleNotifier.value = shouldShow;
      }
    });
  }

  @override
  void dispose() {
    _scrollDebounceTimer?.cancel();
    _profilesSubscription?.cancel();
    _scrollController.removeListener(_scrollListener);
    _scrollController.dispose();
    _notesNotifier.dispose();
    _showUsernameBubbleNotifier.dispose();
    _profileViewModel.dispose();
    super.dispose();
  }

  void _onRetry() {
    _profileViewModel.onRetry();
  }

  @override
  Widget build(BuildContext context) {
    final double topPadding = MediaQuery.of(context).padding.top;
    final colors = context.colors;

    return Scaffold(
      backgroundColor: colors.background,
      body: Stack(
        children: [
          _buildContent(context),
          const BackButtonWidget.floating(
            topOffset: 6,
          ),
          _buildShareButton(context, topPadding),
          Positioned(
            top: topPadding + 8,
            left: 0,
            right: 0,
            child: Center(
              child: ValueListenableBuilder<bool>(
                valueListenable: _showUsernameBubbleNotifier,
                builder: (context, showBubble, child) {
                  return AnimatedOpacity(
                    opacity: showBubble ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 200),
                    child: IgnorePointer(
                      ignoring: !showBubble,
                      child: GestureDetector(
                        onTap: () {
                          _scrollController.animateTo(
                            0,
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeOut,
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: colors.buttonPrimary,
                            borderRadius: BorderRadius.circular(40),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 24,
                                height: 24,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: colors.avatarPlaceholder,
                                  image: widget.user.profileImage.isNotEmpty
                                      ? DecorationImage(
                                          image: CachedNetworkImageProvider(widget.user.profileImage),
                                          fit: BoxFit.cover,
                                        )
                                      : null,
                                ),
                                child: widget.user.profileImage.isEmpty
                                    ? Icon(
                                        Icons.person,
                                        size: 14,
                                        color: colors.textSecondary,
                                      )
                                    : null,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                widget.user.name.isNotEmpty ? widget.user.name : widget.user.npub.substring(0, 8),
                                style: TextStyle(
                                  color: colors.buttonText,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async {
        _profileViewModel.onRetry();
        await Future.delayed(const Duration(milliseconds: 500));
      },
      child: CustomScrollView(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        cacheExtent: 1200,
        slivers: [
          SliverToBoxAdapter(
            child: ProfileInfoWidget(
              user: widget.user,
              onNavigateToProfile: (npub) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ProfilePage(
                      user: UserModel(
                        pubkeyHex: npub,
                        name: npub.length > 8 ? npub.substring(0, 8) : npub,
                        about: '',
                        profileImage: '',
                        banner: '',
                        website: '',
                        nip05: '',
                        lud16: '',
                        updatedAt: DateTime.now(),
                        nip05Verified: false,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          _buildProfileNotes(context),
        ],
      ),
    );
  }

  Widget _buildProfileNotes(BuildContext context) {
    return AnimatedBuilder(
      animation: _profileViewModel,
      builder: (context, child) {
        return SliverUIStateBuilder<List<NoteModel>>(
          state: _profileViewModel.profileNotesState,
          builder: (context, notes) {
            _notesNotifier.value = notes;

            return widgets.NoteListWidget(
              notes: notes,
              currentUserNpub: _profileViewModel.currentUserNpub,
              notesNotifier: _notesNotifier,
              profiles: _profiles,
              isLoading: _profileViewModel.isLoadingMore,
              canLoadMore: _profileViewModel.canLoadMoreProfileNotes,
              onLoadMore: _profileViewModel.loadMoreProfileNotes,
              scrollController: _scrollController,
            );
          },
          loading: () => const Center(
            child: Padding(
              padding: EdgeInsets.all(32.0),
              child: CircularProgressIndicator(),
            ),
          ),
          error: (error) => Center(
            child: Padding(
              padding: EdgeInsets.all(32.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 48,
                    color: context.colors.error,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Error loading notes',
                    style: TextStyle(
                      color: context.colors.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    error,
                    style: TextStyle(color: context.colors.textSecondary),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  PrimaryButton(
                    label: 'Retry',
                    onPressed: _onRetry,
                  ),
                ],
              ),
            ),
          ),
          empty: (message) => Center(
            child: Padding(
              padding: const EdgeInsets.all(32.0),
              child: Text(
                message ?? 'No notes from this user yet',
                style: TextStyle(color: context.colors.textSecondary),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildShareButton(BuildContext context, double topPadding) {
    return Positioned(
      top: topPadding + 6,
      right: 16,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: context.colors.buttonPrimary,
          borderRadius: BorderRadius.circular(22.0),
        ),
        child: Bounce(
          scaleFactor: 0.85,
          onTap: () async {
            try {
              final npub = widget.user.npub;
              final nostrLink = 'nostr:$npub';
              
              final box = context.findRenderObject() as RenderBox?;
              await SharePlus.instance.share(
                ShareParams(
                  text: nostrLink,
                  sharePositionOrigin: box != null 
                      ? box.localToGlobal(Offset.zero) & box.size 
                      : null,
                ),
              );
            } catch (e) {
              debugPrint('[ProfilePage] Share error: $e');
            }
          },
          behavior: HitTestBehavior.opaque,
          child: Semantics(
            label: 'Share',
            button: true,
            child: Icon(
              CarbonIcons.share,
              color: context.colors.buttonText,
              size: 20,
            ),
          ),
        ),
      ),
    );
  }
}
