import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../theme/theme_manager.dart';
import '../../widgets/common/common_buttons.dart';
import '../../widgets/common/title_widget.dart';
import '../../../core/di/app_di.dart';
import '../../../l10n/app_localizations.dart';
import '../../../presentation/blocs/onboarding_spark/onboarding_spark_bloc.dart';
import '../../../presentation/blocs/onboarding_spark/onboarding_spark_event.dart';
import '../../../presentation/blocs/onboarding_spark/onboarding_spark_state.dart';
import '../../../core/di/modules/services_module.dart';
import 'restore_wallet_page.dart';

class OnboardingSparkPage extends StatefulWidget {
  final String npub;

  const OnboardingSparkPage({
    super.key,
    required this.npub,
  });

  @override
  State<OnboardingSparkPage> createState() => _OnboardingSparkPageState();
}

class _OnboardingSparkPageState extends State<OnboardingSparkPage> {
  bool _acceptedDisclaimer = false;

  @override
  Widget build(BuildContext context) {
    return BlocProvider<OnboardingSparkBloc>(
      create: (_) => AppDI.get<OnboardingSparkBloc>(),
      child: BlocListener<OnboardingSparkBloc, OnboardingSparkState>(
        listener: (context, state) {
          if (state is OnboardingSparkReady && state.shouldNavigate) {
            _navigateToHome(context);
          } else if (state is OnboardingSparkSkippedState) {
            _navigateToHome(context);
          }
        },
        child: BlocBuilder<OnboardingSparkBloc, OnboardingSparkState>(
          builder: (context, state) {
            return Scaffold(
              backgroundColor: context.colors.background,
              body: SafeArea(
                child: _buildBody(context, state),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, OnboardingSparkState state) {
    final l10n = AppLocalizations.of(context)!;

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TitleWidget(
                  title: l10n.onboardingSparkTitle,
                  fontSize: 32,
                  subtitle: l10n.onboardingSparkSubtitle,
                  useTopPadding: false,
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
                ),
                const SizedBox(height: 32),
                _buildWalletInfo(context, l10n),
                if (state is OnboardingSparkError) ...[
                  const SizedBox(height: 16),
                  _buildErrorMessage(context, state.message),
                ],
              ],
            ),
          ),
        ),
        _buildDisclaimer(context, l10n),
        const SizedBox(height: 20),
        _buildAcceptCheckbox(context, l10n),
        const SizedBox(height: 72),
        _buildBottomSection(context, state, l10n),
      ],
    );
  }

  Widget _buildWalletInfo(BuildContext context, AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          _buildFeatureItem(
            context,
            Icons.bolt,
            l10n.onboardingCoinosFeatureSend,
          ),
          const SizedBox(height: 24),
          _buildFeatureItem(
            context,
            Icons.call_received,
            l10n.onboardingCoinosFeatureReceive,
          ),
          const SizedBox(height: 24),
          _buildFeatureItem(
            context,
            Icons.favorite,
            l10n.onboardingCoinosFeatureZap,
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureItem(
      BuildContext context, IconData icon, String description) {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: context.colors.overlayLight,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            icon,
            color: context.colors.textPrimary,
            size: 20,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            description,
            style: TextStyle(
              fontSize: 16,
              color: context.colors.textPrimary,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDisclaimer(BuildContext context, AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Text(
        l10n.onboardingSparkDisclaimer,
        style: TextStyle(
          fontSize: 13,
          color: context.colors.textSecondary,
          height: 1.5,
        ),
      ),
    );
  }

  Widget _buildAcceptCheckbox(BuildContext context, AppLocalizations l10n) {
    return Center(
      child: GestureDetector(
        onTap: () => setState(() => _acceptedDisclaimer = !_acceptedDisclaimer),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: Checkbox(
                value: _acceptedDisclaimer,
                onChanged: (value) =>
                    setState(() => _acceptedDisclaimer = value ?? false),
                activeColor: context.colors.textPrimary,
                checkColor: context.colors.background,
                side: BorderSide(color: context.colors.textSecondary),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              l10n.onboardingCoinosAccept,
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

  Widget _buildErrorMessage(BuildContext context, String message) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Text(
        message,
        style: TextStyle(
          color: context.colors.error,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildBottomSection(BuildContext context, OnboardingSparkState state,
      AppLocalizations l10n) {
    final isLoading = state is OnboardingSparkLoading;
    final canConnect = _acceptedDisclaimer && !isLoading;

    return Padding(
      padding: const EdgeInsets.only(
        bottom: 16,
        left: 24,
        right: 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: double.infinity,
            child: PrimaryButton(
              label: l10n.onboardingSparkSetup,
              onPressed: canConnect
                  ? () => context
                      .read<OnboardingSparkBloc>()
                      .add(const OnboardingSparkWalletSetupRequested())
                  : null,
              size: ButtonSize.large,
              isLoading: isLoading,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: SecondaryButton(
              label: l10n.restoreWallet,
              onPressed: isLoading
                  ? null
                  : () => _openRestorePage(context),
              size: ButtonSize.large,
            ),
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: isLoading
                ? null
                : () {
                    context
                        .read<OnboardingSparkBloc>()
                        .add(const OnboardingSparkSkipped());
                  },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                l10n.skip,
                style: TextStyle(
                  fontSize: 16,
                  color: context.colors.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _navigateToHome(BuildContext context) async {
    await ServicesModule.reinitializeForAccountSwitch();
    if (context.mounted) {
      context.go('/home/feed?npub=${Uri.encodeComponent(widget.npub)}');
    }
  }

  void _openRestorePage(BuildContext context) {
    final bloc = context.read<OnboardingSparkBloc>();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BlocProvider.value(
          value: bloc,
          child: BlocListener<OnboardingSparkBloc, OnboardingSparkState>(
            listener: (ctx, state) {
              if (state is OnboardingSparkReady && state.shouldNavigate) {
                Navigator.of(ctx).pop();
                _navigateToHome(context);
              }
            },
            child: const RestoreWalletPage(),
          ),
        ),
      ),
    );
  }
}
