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
}

