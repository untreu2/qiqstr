import 'package:flutter/material.dart';
import '../theme/theme_manager.dart';
import '../models/user_model.dart';
import '../models/note_model.dart';
import '../widgets/profile_info_widget.dart';
import '../widgets/back_button_widget.dart';
import 'package:qiqstr/widgets/note_list_widget.dart' as widgets;
import '../core/di/app_di.dart';
import '../presentation/viewmodels/profile_viewmodel.dart';
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

  // Legacy interface requirements for NoteListWidget
  final ValueNotifier<List<NoteModel>> _notesNotifier = ValueNotifier([]);
  final Map<String, UserModel> _profiles = {};

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();

    // Initialize ProfileViewModel
    _profileViewModel = AppDI.get<ProfileViewModel>();
    _profileViewModel.initialize();

    // Add this user to profiles map for legacy interface
    _profiles[widget.user.npub] = widget.user;

    // Initialize ProfileViewModel with user and load notes
    _profileViewModel.initializeWithUser(widget.user.npub);
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
    return Scaffold(
      backgroundColor: context.colors.background,
      body: Stack(
        children: [
          _buildContent(context),
          const BackButtonWidget.floating(
            topOffset: 6,
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
        cacheExtent: 1500,
        slivers: [
          SliverToBoxAdapter(
            child: ProfileInfoWidget(
              user: widget.user,
              onNavigateToProfile: (npub) {
                // Navigate to another profile
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
            // Update notesNotifier for legacy interface
            _notesNotifier.value = notes;

            // Use the same NoteListWidget structure as other pages
            return widgets.NoteListWidget(
              notes: notes,
              currentUserNpub: widget.user.npub,
              notesNotifier: _notesNotifier,
              profiles: _profiles,
              isLoading: false,
              hasMore: false,
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
                  ElevatedButton(
                    onPressed: _onRetry,
                    child: const Text('Retry'),
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
