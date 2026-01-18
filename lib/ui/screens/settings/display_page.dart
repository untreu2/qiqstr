import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../theme/theme_manager.dart';
import '../../widgets/common/back_button_widget.dart';
import 'package:carbon_icons/carbon_icons.dart';
import '../../widgets/common/title_widget.dart';
import '../../../presentation/blocs/theme/theme_bloc.dart';
import '../../../presentation/blocs/theme/theme_event.dart';
import '../../../presentation/blocs/theme/theme_state.dart';

class DisplayPage extends StatefulWidget {
  const DisplayPage({super.key});

  @override
  State<DisplayPage> createState() => _DisplayPageState();
}

class _DisplayPageState extends State<DisplayPage> {
  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ThemeBloc, ThemeState>(
      builder: (context, themeState) {
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
                    _buildDisplaySection(context, themeState),
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
        title: 'Display',
        fontSize: 32,
        subtitle: "Customize your viewing experience.",
        padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
      ),
    );
  }

  Widget _buildDisplaySection(BuildContext context, ThemeState themeState) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          _buildExpandedNoteModeToggleItem(context, themeState),
          const SizedBox(height: 8),
          _buildThemeToggleItem(context, themeState),
          const SizedBox(height: 8),
          _buildBottomNavOrderSection(context, themeState),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildExpandedNoteModeToggleItem(
      BuildContext context, ThemeState themeState) {
    return GestureDetector(
      onTap: () =>
          context.read<ThemeBloc>().add(const ExpandedNoteModeToggled()),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
        decoration: BoxDecoration(
          color: context.colors.overlayLight,
          borderRadius: BorderRadius.circular(40),
        ),
        child: Row(
          children: [
            Icon(
              themeState.isExpandedNoteMode
                  ? CarbonIcons.expand_all
                  : CarbonIcons.collapse_all,
              size: 22,
              color: context.colors.textPrimary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                themeState.isExpandedNoteMode
                    ? 'Expanded Notes'
                    : 'Normal Notes',
                style: TextStyle(
                  color: context.colors.textPrimary,
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Switch(
              value: themeState.isExpandedNoteMode,
              onChanged: (value) => context
                  .read<ThemeBloc>()
                  .add(const ExpandedNoteModeToggled()),
              activeThumbColor: context.colors.accent,
              inactiveThumbColor: context.colors.textSecondary,
              inactiveTrackColor: context.colors.border,
              activeTrackColor: context.colors.accent.withValues(alpha: 0.3),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildThemeToggleItem(BuildContext context, ThemeState themeState) {
    return GestureDetector(
      onTap: () => context.read<ThemeBloc>().add(const ThemeToggled()),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
        decoration: BoxDecoration(
          color: context.colors.overlayLight,
          borderRadius: BorderRadius.circular(40),
        ),
        child: Row(
          children: [
            Icon(
              themeState.isDarkMode ? CarbonIcons.asleep : CarbonIcons.light,
              size: 22,
              color: context.colors.textPrimary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                themeState.isDarkMode ? 'Dark Mode' : 'Light Mode',
                style: TextStyle(
                  color: context.colors.textPrimary,
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Switch(
              value: themeState.isDarkMode,
              onChanged: (value) =>
                  context.read<ThemeBloc>().add(const ThemeToggled()),
              activeThumbColor: context.colors.accent,
              inactiveThumbColor: context.colors.textSecondary,
              inactiveTrackColor: context.colors.border,
              activeTrackColor: context.colors.accent.withValues(alpha: 0.3),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomNavOrderSection(
      BuildContext context, ThemeState themeState) {
    final navItems = [
      {'index': 0, 'name': 'Home', 'icon': 'assets/house.svg'},
      {'index': 1, 'name': 'Search', 'icon': 'assets/chat.svg'},
      {'index': 2, 'name': 'Wallet', 'icon': 'assets/wallet.svg'},
      {'index': 3, 'name': 'Notifications', 'icon': 'assets/bell.svg'},
    ];

    final currentOrder = themeState.bottomNavOrder;
    final orderedItems = currentOrder.map((index) => navItems[index]).toList();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
      decoration: BoxDecoration(
        color: context.colors.overlayLight,
        borderRadius: BorderRadius.circular(40),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                CarbonIcons.list,
                size: 22,
                color: context.colors.textPrimary,
              ),
              const SizedBox(width: 8),
              Text(
                'Navigation Bar Order',
                style: TextStyle(
                  color: context.colors.textPrimary,
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Press and hold to drag and reorder items',
            style: TextStyle(
              color: context.colors.textSecondary,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: orderedItems.map((item) {
              final originalIndex = item['index'] as int;

              return Expanded(
                child: LongPressDraggable<int>(
                  data: originalIndex,
                  feedback: Material(
                    color: Colors.transparent,
                    child: Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: context.colors.background,
                        shape: BoxShape.circle,
                      ),
                      child: SvgPicture.asset(
                        item['icon'] as String,
                        width: 21,
                        height: 21,
                        colorFilter: ColorFilter.mode(
                          context.colors.textPrimary,
                          BlendMode.srcIn,
                        ),
                      ),
                    ),
                  ),
                  child: DragTarget<int>(
                    onAccept: (draggedIndex) {
                      if (draggedIndex != originalIndex) {
                        final newOrder = List<int>.from(currentOrder);
                        final oldPos = newOrder.indexOf(draggedIndex);
                        final newPos = newOrder.indexOf(originalIndex);
                        newOrder.removeAt(oldPos);
                        newOrder.insert(newPos, draggedIndex);
                        context
                            .read<ThemeBloc>()
                            .add(BottomNavOrderSet(newOrder));
                      }
                    },
                    builder: (context, candidateData, rejectedData) {
                      return Container(
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: context.colors.background,
                          shape: BoxShape.circle,
                          border: candidateData.isNotEmpty
                              ? Border.all(
                                  color: context.colors.accent,
                                  width: 2,
                                )
                              : null,
                        ),
                        child: Center(
                          child: SvgPicture.asset(
                            item['icon'] as String,
                            width: 21,
                            height: 21,
                            colorFilter: ColorFilter.mode(
                              context.colors.textPrimary,
                              BlendMode.srcIn,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
