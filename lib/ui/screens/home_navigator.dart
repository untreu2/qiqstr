import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'package:go_router/go_router.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:qiqstr/ui/screens/note/share_note.dart';
import '../theme/theme_manager.dart';
import '../../core/di/app_di.dart';
import '../../presentation/blocs/theme/theme_bloc.dart';
import '../../presentation/blocs/theme/theme_state.dart';
import '../../presentation/blocs/notification_indicator/notification_indicator_bloc.dart';
import '../../presentation/blocs/notification_indicator/notification_indicator_event.dart';
import '../../presentation/blocs/notification_indicator/notification_indicator_state.dart';
import '../../presentation/blocs/dm/dm_bloc.dart';
import '../../presentation/blocs/dm/dm_event.dart' as dm_events;
import '../../presentation/blocs/wallet/wallet_bloc.dart';
import '../../presentation/blocs/wallet/wallet_event.dart';
import '../../data/services/coinos_service.dart';

class HomeNavigator extends StatefulWidget {
  final String npub;
  final StatefulNavigationShell navigationShell;

  const HomeNavigator({
    super.key,
    required this.npub,
    required this.navigationShell,
  });

  @override
  State<HomeNavigator> createState() => _HomeNavigatorState();
}

class _HomeNavigatorState extends State<HomeNavigator>
    with TickerProviderStateMixin {
  late AnimationController _iconAnimationController;
  late AnimationController _exploreRotationController;
  bool _isFirstBuild = true;

  @override
  void initState() {
    super.initState();
    _iconAnimationController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _exploreRotationController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final indicatorBloc = AppDI.get<NotificationIndicatorBloc>();
        indicatorBloc.add(const NotificationIndicatorInitialized());

        final dmBloc = AppDI.get<DmBloc>();
        dmBloc.add(const dm_events.DmConversationsLoadRequested());

        final walletBloc = AppDI.get<WalletBloc>();
        walletBloc.add(const WalletAutoConnectRequested());
      }
    });
  }

  @override
  void dispose() {
    _iconAnimationController.dispose();
    _exploreRotationController.dispose();
    super.dispose();
  }

  Widget _buildCustomBottomBar(bool hasNewNotifications) {
    final themeState = context.themeState;
    final navOrder = themeState?.bottomNavOrder ?? [0, 1, 2, 3];

    final navItems = [
      {
        'icon': 'assets/house.svg',
        'iconSelected': 'assets/house_fill.svg',
        'index': 0,
        'type': 'svg'
      },
      {
        'icon': 'assets/chat.svg',
        'iconSelected': 'assets/chat_fill.svg',
        'index': 1,
        'type': 'svg'
      },
      {
        'icon': 'assets/wallet.svg',
        'iconSelected': 'assets/wallet_fill.svg',
        'index': 2,
        'type': 'svg'
      },
      {
        'icon': 'assets/bell.svg',
        'iconSelected': 'assets/bell_fill.svg',
        'index': 3,
        'type': 'svg'
      },
    ];

    final orderedNavItems = navOrder.map((index) => navItems[index]).toList();

    final items = [
      orderedNavItems[0],
      orderedNavItems[1],
      {'icon': 'add', 'index': -1, 'type': 'add'},
      orderedNavItems[2],
      orderedNavItems[3],
    ];

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
        child: Container(
          decoration: BoxDecoration(
            color: context.colors.surface.withValues(alpha: 0.8),
          ),
          child: SafeArea(
            child: Container(
              height: 55,
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child: Row(
                children: items.map((item) {
                  final index = item['index'] as int;

                  if (item['type'] == 'add') {
                    return Expanded(
                      child: GestureDetector(
                        onTap: () async {
                          HapticFeedback.lightImpact();
                          final result = await ShareNotePage.show(context);
                          if (result == true && mounted) {
                            final currentIndex =
                                widget.navigationShell.currentIndex;
                            if (currentIndex != 0) {
                              widget.navigationShell.goBranch(0);
                            }
                          }
                        },
                        behavior: HitTestBehavior.opaque,
                        child: Center(
                          child: Container(
                            width: 45,
                            height: 45,
                            decoration: BoxDecoration(
                              color: context.colors.textPrimary,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Icon(
                              Icons.add,
                              color: context.colors.background,
                              size: 25,
                            ),
                          ),
                        ),
                      ),
                    );
                  }

                  final originalIndex = index;
                  final themeState = context.themeState;
                  final navOrder = themeState?.bottomNavOrder ?? [0, 1, 2, 3];
                  final pageViewIndex = navOrder.indexOf(originalIndex);
                  final bool isSelected =
                      widget.navigationShell.currentIndex == pageViewIndex;

                  return Expanded(
                    child: GestureDetector(
                      onTap: () {
                        HapticFeedback.lightImpact();
                        final themeState = context.themeState;
                        final navOrder =
                            themeState?.bottomNavOrder ?? [0, 1, 2, 3];
                        final pageViewIndex = navOrder.indexOf(originalIndex);
                        _handleNavigation(pageViewIndex);
                      },
                      behavior: HitTestBehavior.opaque,
                      child: Center(
                        child: originalIndex == 3
                            ? _buildNotificationIcon(item['icon'] as String,
                                isSelected, hasNewNotifications)
                            : originalIndex == 2
                                ? _buildWalletIcon(
                                    item['icon'] as String, isSelected)
                                : originalIndex == 1
                                    ? _buildExploreIcon(
                                        item['icon'] as String,
                                        item['iconSelected'] as String? ??
                                            item['icon'] as String,
                                        isSelected)
                                    : _buildRegularIcon(item, isSelected),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  static const double _iconSize = 21.0;

  Widget _buildIcon({
    required String iconPath,
    required String iconSelectedPath,
    required bool isSelected,
    required int index,
    String? iconType,
  }) {
    final iconSize = _iconSize;
    final currentIconPath = isSelected ? iconSelectedPath : iconPath;

    if (_isFirstBuild) {
      return SizedBox(
        width: iconSize,
        height: iconSize,
        child: SvgPicture.asset(
          currentIconPath,
          width: iconSize,
          height: iconSize,
          fit: BoxFit.contain,
          colorFilter: ColorFilter.mode(
            context.colors.textPrimary,
            BlendMode.srcIn,
          ),
        ),
      );
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      switchInCurve: Curves.easeInOut,
      switchOutCurve: Curves.easeInOut,
      transitionBuilder: (Widget child, Animation<double> animation) {
        return FadeTransition(
          opacity: animation,
          child: child,
        );
      },
      child: SizedBox(
        key: ValueKey('${currentIconPath}_${iconType ?? index}'),
        width: iconSize,
        height: iconSize,
        child: SvgPicture.asset(
          currentIconPath,
          width: iconSize,
          height: iconSize,
          fit: BoxFit.contain,
          colorFilter: ColorFilter.mode(
            context.colors.textPrimary,
            BlendMode.srcIn,
          ),
        ),
      ),
    );
  }

  Widget _buildNotificationIcon(
      String iconPath, bool isSelected, bool hasNewNotifications) {
    final icon = _buildIcon(
      iconPath: iconPath,
      iconSelectedPath: 'assets/bell_fill.svg',
      isSelected: isSelected,
      index: 3,
      iconType: 'notification',
    );

    if (hasNewNotifications) {
      return SizedBox(
        width: _iconSize + 6,
        height: _iconSize + 6,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: 0,
              top: 0,
              child: icon,
            ),
            Positioned(
              right: -2,
              top: -2,
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: context.colors.accent,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: context.colors.background,
                    width: 1.5,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return icon;
  }

  Widget _buildWalletIcon(String iconPath, bool isSelected) {
    return _buildIcon(
      iconPath: iconPath,
      iconSelectedPath: 'assets/wallet_fill.svg',
      isSelected: isSelected,
      index: 2,
      iconType: 'wallet',
    );
  }

  Widget _buildExploreIcon(
      String iconPath, String iconSelectedPath, bool isSelected) {
    return _buildIcon(
      iconPath: iconPath,
      iconSelectedPath: iconSelectedPath,
      isSelected: isSelected,
      index: 1,
      iconType: 'explore',
    );
  }

  Widget _buildRegularIcon(Map<String, dynamic> item, bool isSelected) {
    final String iconPath = item['icon'] as String;
    final String iconSelectedPath = item['iconSelected'] as String? ?? iconPath;
    final int index = item['index'] as int;

    return _buildIcon(
      iconPath: iconPath,
      iconSelectedPath: iconSelectedPath,
      isSelected: isSelected,
      index: index,
    );
  }

  Future<void> _handleNavigation(int pageViewIndex) async {
    final themeState = context.themeState;
    final navOrder = themeState?.bottomNavOrder ?? [0, 1, 2, 3];
    final originalIndex = navOrder[pageViewIndex];

    if (originalIndex == 0) {
      if (widget.navigationShell.currentIndex == pageViewIndex) {
        final npub = widget.npub;
        context.go('/home/feed?npub=${Uri.encodeComponent(npub)}');
      } else {
        if (mounted) {
          _iconAnimationController.reset();
          _iconAnimationController.forward();
          widget.navigationShell.goBranch(pageViewIndex);
        }
      }
    } else if (originalIndex == 2) {
      final coinosService = AppDI.get<CoinosService>();
      final tokenResult = await coinosService.getStoredToken();
      final hasToken = tokenResult.isSuccess &&
          tokenResult.data != null &&
          tokenResult.data!.isNotEmpty;
      if (!mounted) return;
      if (!hasToken) {
        context.push(
            '/onboarding-coinos?npub=${Uri.encodeComponent(widget.npub)}');
        return;
      }
      _iconAnimationController.reset();
      _iconAnimationController.forward();
      widget.navigationShell.goBranch(pageViewIndex);
    } else if (originalIndex == 3) {
      final indicatorBloc = AppDI.get<NotificationIndicatorBloc>();
      indicatorBloc.add(const NotificationIndicatorChecked());
      if (widget.navigationShell.currentIndex == pageViewIndex) {
        final npub = widget.npub;
        context.go('/home/notifications?npub=${Uri.encodeComponent(npub)}');
      } else {
        if (mounted) {
          _iconAnimationController.reset();
          _iconAnimationController.forward();
          widget.navigationShell.goBranch(pageViewIndex);
        }
      }
    } else {
      if (mounted) {
        _iconAnimationController.reset();
        _iconAnimationController.forward();
        widget.navigationShell.goBranch(pageViewIndex);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isFirstBuild) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _isFirstBuild = false;
          });
        }
      });
    }

    final indicatorBloc = AppDI.get<NotificationIndicatorBloc>();

    return BlocProvider<NotificationIndicatorBloc>.value(
      value: indicatorBloc,
      child: BlocBuilder<ThemeBloc, ThemeState>(
        builder: (context, themeState) {
          return Scaffold(
            extendBody: true,
            body: PageStorage(
              bucket: PageStorageBucket(),
              child: widget.navigationShell,
            ),
            bottomNavigationBar: BlocBuilder<NotificationIndicatorBloc,
                NotificationIndicatorState>(
              bloc: AppDI.get<NotificationIndicatorBloc>(),
              builder: (context, state) {
                final hasNewNotifications =
                    state is NotificationIndicatorLoaded &&
                        state.hasNewNotifications;
                return _buildCustomBottomBar(hasNewNotifications);
              },
            ),
          );
        },
      ),
    );
  }
}
