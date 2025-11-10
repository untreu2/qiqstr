import 'package:flutter/material.dart';
import '../theme/theme_manager.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/user_model.dart';
import '../screens/profile_page.dart';
import '../core/di/app_di.dart';
import '../presentation/viewmodels/following_page_viewmodel.dart';
import '../widgets/back_button_widget.dart';
import '../widgets/common_buttons.dart';
import '../widgets/title_widget.dart';

class FollowingPage extends StatefulWidget {
  final UserModel user;

  const FollowingPage({
    super.key,
    required this.user,
  });

  @override
  State<FollowingPage> createState() => _FollowingPageState();
}

class _FollowingPageState extends State<FollowingPage> {
  late final FollowingPageViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel = AppDI.get<FollowingPageViewModel>();
    _viewModel.addListener(_onViewModelChanged);
    _viewModel.loadFollowingList(widget.user.npub);
  }

  void _onViewModelChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _viewModel.removeListener(_onViewModelChanged);
    _viewModel.dispose();
    super.dispose();
  }

  Widget _buildHeader(BuildContext context) {
    return const TitleWidget(
      title: 'Following',
      useTopPadding: true,
    );
  }

  Widget _buildUserTile(BuildContext context, UserModel user) {
    String displayName;
    if (user.name.isNotEmpty && user.name != user.npub.substring(0, 8)) {
      displayName = user.name.length > 25 ? '${user.name.substring(0, 25)}...' : user.name;
    } else {
      displayName = user.npub.startsWith('npub1') ? '${user.npub.substring(0, 16)}...' : 'Unknown User';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: GestureDetector(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ProfilePage(user: user),
            ),
          );
        },
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
          decoration: BoxDecoration(
            color: context.colors.overlayLight,
            borderRadius: BorderRadius.circular(40),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundImage: user.profileImage.isNotEmpty ? CachedNetworkImageProvider(user.profileImage) : null,
                backgroundColor: Colors.grey.shade800,
                child: user.profileImage.isEmpty
                    ? Icon(
                        Icons.person,
                        size: 26,
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
                            displayName,
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                              color: context.colors.textPrimary,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (user.nip05.isNotEmpty && user.nip05Verified) ...[
                          const SizedBox(width: 4),
                          Icon(
                            Icons.verified,
                            size: 16,
                            color: context.colors.accent,
                          ),
                        ],
                      ],
                    ),
                    if (_viewModel.isLoadingProfiles) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.5,
                              color: context.colors.textSecondary,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Loading profile...',
                            style: TextStyle(
                              fontSize: 12,
                              color: context.colors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    final state = _viewModel.followingState;

    if (state.isError) {
      return SingleChildScrollView(
        child: Column(
          children: [
            _buildHeader(context),
            SizedBox(height: MediaQuery.of(context).size.height * 0.2),
            Center(
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
                    'Error loading following list',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: context.colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Text(
                      state.error ?? 'Unknown error',
                      style: TextStyle(color: context.colors.textSecondary),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 16),
                  PrimaryButton(
                    label: 'Retry',
                    onPressed: () => _viewModel.loadFollowingList(widget.user.npub),
                    backgroundColor: context.colors.accent,
                    foregroundColor: context.colors.background,
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    if (state.isEmpty) {
      return SingleChildScrollView(
        child: Column(
          children: [
            _buildHeader(context),
            SizedBox(height: MediaQuery.of(context).size.height * 0.2),
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.people_outline,
                    size: 48,
                    color: context.colors.textSecondary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No following found',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: context.colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'This user is not following anyone yet.',
                    style: TextStyle(color: context.colors.textSecondary),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final users = _viewModel.followingUsers;

    return RefreshIndicator(
      onRefresh: () => _viewModel.loadFollowingList(widget.user.npub),
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: _buildHeader(context),
          ),
          if (state.isLoading && users.isEmpty) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(top: 80),
                child: Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.grey,
                    ),
                  ),
                ),
              ),
            ),
          ] else if (users.isNotEmpty) ...[
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  if (index < users.length) {
                    return _buildUserTile(context, users[index]);
                  }
                  return null;
                },
                childCount: users.length,
                addAutomaticKeepAlives: false,
                addRepaintBoundaries: true,
              ),
            ),
          ],
          const SliverToBoxAdapter(
            child: SizedBox(height: 24),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeManager>(
      builder: (context, themeManager, child) {
        return Scaffold(
          backgroundColor: context.colors.background,
          body: Stack(
            children: [
              _buildContent(context),
              const BackButtonWidget.floating(),
            ],
          ),
        );
      },
    );
  }
}
