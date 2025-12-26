import 'package:flutter/material.dart';
import '../../theme/theme_manager.dart';
import '../../widgets/common/back_button_widget.dart';
import '../../widgets/common/title_widget.dart';

class ExplorePage extends StatelessWidget {
  const ExplorePage({super.key});

  @override
  Widget build(BuildContext context) {
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
                _buildContent(context),
                const SizedBox(height: 150),
              ],
            ),
          ),
          const BackButtonWidget.floating(),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top + 60),
      child: const TitleWidget(
        title: 'Explore',
        fontSize: 32,
        subtitle: "Discover new content and users.",
        padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Center(
        child: Text(
          'Soon',
          style: TextStyle(
            color: context.colors.textPrimary,
            fontSize: 24,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

