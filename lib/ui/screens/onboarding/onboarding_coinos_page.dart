import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../theme/theme_manager.dart';
import '../../widgets/common/common_buttons.dart';
import '../../widgets/common/title_widget.dart';
import '../../widgets/wallet/recaptcha_widget.dart';
import '../../../core/di/app_di.dart';
import '../../../l10n/app_localizations.dart';
import '../../../presentation/blocs/onboarding_coinos/onboarding_coinos_bloc.dart';
import '../../../presentation/blocs/onboarding_coinos/onboarding_coinos_event.dart';
import '../../../presentation/blocs/onboarding_coinos/onboarding_coinos_state.dart';

class OnboardingCoinosPage extends StatefulWidget {
  final String npub;

  const OnboardingCoinosPage({
    super.key,
    required this.npub,
  });

  @override
  State<OnboardingCoinosPage> createState() => _OnboardingCoinosPageState();
}

class _OnboardingCoinosPageState extends State<OnboardingCoinosPage> {
  bool _acceptedDisclaimer = false;

  @override
  Widget build(BuildContext context) {
    return BlocProvider<OnboardingCoinosBloc>(
      create: (_) => AppDI.get<OnboardingCoinosBloc>(),
      child: BlocListener<OnboardingCoinosBloc, OnboardingCoinosState>(
        listener: (context, state) {
          if (state is OnboardingCoinosConnected && state.shouldNavigate) {
            _navigateToHome(context);
          } else if (state is OnboardingCoinosSkippedState) {
            _navigateToHome(context);
          }
        },
        child: BlocBuilder<OnboardingCoinosBloc, OnboardingCoinosState>(
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

  Widget _buildBody(BuildContext context, OnboardingCoinosState state) {
    final l10n = AppLocalizations.of(context)!;

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TitleWidget(
                  title: l10n.onboardingCoinosTitle,
                  fontSize: 32,
                  subtitle: l10n.onboardingCoinosSubtitle,
                  useTopPadding: false,
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
                ),
                const SizedBox(height: 32),
                _buildWalletInfo(context, l10n),
                if (state is OnboardingCoinosError) ...[
                  const SizedBox(height: 16),
                  _buildErrorMessage(context, state.message),
                ],
                if (state is OnboardingCoinosConnected) ...[
                  const SizedBox(height: 16),
                  _buildSuccessMessage(context, state.username, l10n),
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
        l10n.onboardingCoinosDisclaimer,
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

  Widget _buildSuccessMessage(
      BuildContext context, String username, AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: context.colors.overlayLight,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(
              Icons.check_circle,
              color: context.colors.success,
              size: 24,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                l10n.onboardingCoinosConnected(username),
                style: TextStyle(
                  fontSize: 15,
                  color: context.colors.textPrimary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomSection(BuildContext context, OnboardingCoinosState state,
      AppLocalizations l10n) {
    final isLoading = state is OnboardingCoinosLoading;
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
              label: l10n.onboardingCoinosConnect,
              onPressed: canConnect ? () => _onConnectPressed(context) : null,
              size: ButtonSize.large,
              isLoading: isLoading,
            ),
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: isLoading
                ? null
                : () {
                    context
                        .read<OnboardingCoinosBloc>()
                        .add(const OnboardingCoinosSkipped());
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

  Future<void> _onConnectPressed(BuildContext context) async {
    final recaptchaToken = await resolveRecaptcha(context);
    if (context.mounted) {
      context.read<OnboardingCoinosBloc>().add(
            OnboardingCoinosConnectRequested(recaptchaToken: recaptchaToken),
          );
    }
  }

  void _navigateToHome(BuildContext context) {
    context.go('/home/feed?npub=${Uri.encodeComponent(widget.npub)}');
  }
}
