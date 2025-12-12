import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../theme/theme_manager.dart';
import '../../widgets/common/back_button_widget.dart';
import 'package:carbon_icons/carbon_icons.dart';
import '../../widgets/common/title_widget.dart';

class DisplayPage extends StatefulWidget {
  const DisplayPage({super.key});

  @override
  State<DisplayPage> createState() => _DisplayPageState();
}

class _DisplayPageState extends State<DisplayPage> {
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
                    _buildDisplaySection(context, themeManager),
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
    return TitleWidget(
      title: 'Display',
      fontSize: 32,
      subtitle: "Customize your viewing experience.",
      useTopPadding: true,
    );
  }

  Widget _buildDisplaySection(BuildContext context, ThemeManager themeManager) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          _buildExpandedNoteModeToggleItem(context, themeManager),
          const SizedBox(height: 8),
          _buildThemeToggleItem(context, themeManager),
          const SizedBox(height: 8),
          _buildBottomNavOrderSection(context, themeManager),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildExpandedNoteModeToggleItem(BuildContext context, ThemeManager themeManager) {
    return GestureDetector(
      onTap: () => themeManager.toggleExpandedNoteMode(),
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
              themeManager.isExpandedNoteMode ? CarbonIcons.expand_all : CarbonIcons.collapse_all,
              size: 22,
              color: context.colors.textPrimary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                themeManager.isExpandedNoteMode ? 'Expanded Notes' : 'Normal Notes',
                style: TextStyle(
                  color: context.colors.textPrimary,
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Switch(
              value: themeManager.isExpandedNoteMode,
              onChanged: (value) => themeManager.toggleExpandedNoteMode(),
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

  Widget _buildThemeToggleItem(BuildContext context, ThemeManager themeManager) {
    return GestureDetector(
      onTap: () => themeManager.toggleTheme(),
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
              themeManager.isDarkMode ? CarbonIcons.asleep : CarbonIcons.light,
              size: 22,
              color: context.colors.textPrimary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                themeManager.isDarkMode ? 'Dark Mode' : 'Light Mode',
                style: TextStyle(
                  color: context.colors.textPrimary,
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Switch(
              value: themeManager.isDarkMode,
              onChanged: (value) => themeManager.toggleTheme(),
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

  Widget _buildBottomNavOrderSection(BuildContext context, ThemeManager themeManager) {
    final navItems = [
      {'index': 0, 'name': 'Home', 'icon': CarbonIcons.home},
      {'index': 1, 'name': 'Search', 'icon': CarbonIcons.send_alt},
      {'index': 2, 'name': 'Wallet', 'icon': CarbonIcons.wallet},
      {'index': 3, 'name': 'Notifications', 'icon': CarbonIcons.notification},
    ];

    final currentOrder = themeManager.bottomNavOrder;
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
                      child: Icon(
                        item['icon'] as IconData,
                        size: 24,
                        color: context.colors.textPrimary,
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
                        themeManager.setBottomNavOrder(newOrder);
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
                        child: Icon(
                          item['icon'] as IconData,
                          size: 24,
                          color: context.colors.textPrimary,
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

