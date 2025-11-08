import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../theme/theme_manager.dart';
import '../models/user_model.dart';
import '../models/note_model.dart';
import '../widgets/profile_info_widget.dart';
import '../widgets/back_button_widget.dart';
import '../widgets/common_buttons.dart';
import 'package:qiqstr/widgets/note_list_widget.dart' as widgets;
import '../core/di/app_di.dart';
import '../presentation/viewmodels/profile_viewmodel.dart';
import '../data/repositories/auth_repository.dart';
import '../core/ui/ui_state_builder.dart';

class ProfilePage extends StatefulWidget {
  final UserModel user;

  const ProfilePage({super.key, required this.user});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  late ScrollController _scrollController;
  late ProfileViewModel _profileViewModel;
  late AuthRepository _authRepository;

  final ValueNotifier<List<NoteModel>> _notesNotifier = ValueNotifier([]);
  late final Map<String, UserModel> _profiles;
  String? _currentUserNpub;
  bool _showUsernameBubble = false;

  @override
  void initState() {
    super.initState();
    _profiles = <String, UserModel>{};
    _scrollController = ScrollController()..addListener(_scrollListener);

    _profileViewModel = AppDI.get<ProfileViewModel>();
    _authRepository = AppDI.get<AuthRepository>();
    _profileViewModel.initialize();

    _profiles[widget.user.npub] = widget.user;

    _loadCurrentUser();
    _profileViewModel.initializeWithUser(widget.user.npub);
  }

  void _scrollListener() {
    if (_scrollController.hasClients) {
      final shouldShow = _scrollController.offset > 100;
      if (_showUsernameBubble != shouldShow) {
        setState(() {
          _showUsernameBubble = shouldShow;
        });
      }
    }
  }

  void _loadCurrentUser() async {
    try {
      final result = await _authRepository.getCurrentUserNpub();
      result.fold(
        (npub) {
          if (mounted) {
            setState(() {
              _currentUserNpub = npub;
            });
          }
        },
        (error) {
          debugPrint('[ProfilePage] Failed to get current user: $error');
        },
      );
    } catch (e) {
      debugPrint('[ProfilePage] Error loading current user: $e');
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _notesNotifier.dispose();
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
          Positioned(
            top: topPadding + 8,
            left: 0,
            right: 0,
            child: Center(
              child: AnimatedOpacity(
                opacity: _showUsernameBubble ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 300),
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
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async => _onRetry(),
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
              currentUserNpub: _currentUserNpub ?? '',
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
}
