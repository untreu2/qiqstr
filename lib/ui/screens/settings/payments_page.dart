import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../theme/theme_manager.dart';
import '../../widgets/common/back_button_widget.dart';
import 'package:carbon_icons/carbon_icons.dart';
import '../../widgets/common/title_widget.dart';
import '../../widgets/common/custom_input_field.dart';
import '../../widgets/common/snackbar_widget.dart';
import '../../widgets/common/common_buttons.dart';
import '../../../presentation/blocs/theme/theme_bloc.dart';
import '../../../presentation/blocs/theme/theme_event.dart';
import '../../../presentation/blocs/theme/theme_state.dart';
import '../../../core/di/app_di.dart';
import '../../../data/services/nwc_service.dart';
import '../../../l10n/app_localizations.dart';

class PaymentsPage extends StatefulWidget {
  const PaymentsPage({super.key});

  @override
  State<PaymentsPage> createState() => _PaymentsPageState();
}

class _PaymentsPageState extends State<PaymentsPage> {
  late TextEditingController _amountController;
  late TextEditingController _nwcUriController;
  bool _isEditing = false;
  int _savedAmount = 21;
  bool _hasNwcConnection = false;
  bool _isNwcSaving = false;
  bool _acceptedNwcDisclaimer = false;

  @override
  void initState() {
    super.initState();
    final themeState = context.read<ThemeBloc>().state;
    _savedAmount = themeState.defaultZapAmount;
    _amountController = TextEditingController(text: _savedAmount.toString());
    _nwcUriController = TextEditingController();
    _loadNwcState();
  }

  Future<void> _loadNwcState() async {
    final nwcService = AppDI.get<NwcService>();
    final hasConnection = await nwcService.hasConnection();
    if (mounted) {
      setState(() {
        _hasNwcConnection = hasConnection;
      });
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    _nwcUriController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
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
                    _buildHeader(context, l10n),
                    const SizedBox(height: 16),
                    _buildContent(context, themeState, l10n),
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

  Widget _buildHeader(BuildContext context, AppLocalizations l10n) {
    return Padding(
      padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top + 60),
      child: TitleWidget(
        title: l10n.paymentsTitle,
        fontSize: 32,
        subtitle: l10n.paymentsSubtitle,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      ),
    );
  }

  Widget _buildContent(
      BuildContext context, ThemeState themeState, AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          _buildOneTapZapToggle(context, themeState, l10n),
          const SizedBox(height: 8),
          if (themeState.oneTapZap) ...[
            _buildDefaultAmountItem(context, themeState, l10n),
          ],
          const SizedBox(height: 24),
          _hasNwcConnection
              ? _buildNwcConnectedItem(context, l10n)
              : _buildNwcInputItem(context, l10n),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              l10n.nwcDescription,
              style: TextStyle(
                fontSize: 13,
                color: context.colors.textSecondary,
                height: 1.4,
              ),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildOneTapZapToggle(
      BuildContext context, ThemeState themeState, AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () =>
              context.read<ThemeBloc>().add(OneTapZapSet(!themeState.oneTapZap)),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              color: context.colors.overlayLight,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Row(
              children: [
                Icon(
                  CarbonIcons.flash,
                  size: 22,
                  color: context.colors.textPrimary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.oneTapZap,
                    style: TextStyle(
                      color: context.colors.textPrimary,
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Switch(
                  value: themeState.oneTapZap,
                  onChanged: (value) =>
                      context.read<ThemeBloc>().add(OneTapZapSet(value)),
                  activeThumbColor: context.colors.switchActive,
                  inactiveThumbColor: context.colors.textSecondary,
                  inactiveTrackColor: context.colors.border,
                  activeTrackColor:
                      context.colors.switchActive.withValues(alpha: 0.3),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            l10n.oneTapZapDescription,
            style: TextStyle(
              fontSize: 13,
              color: context.colors.textSecondary,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDefaultAmountItem(
      BuildContext context, ThemeState themeState, AppLocalizations l10n) {
    final currentAmount = int.tryParse(_amountController.text.trim()) ?? 0;
    final hasChanges = currentAmount != _savedAmount && currentAmount > 0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: context.colors.overlayLight,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                CarbonIcons.hashtag,
                size: 22,
                color: context.colors.textPrimary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.defaultZapAmount,
                  style: TextStyle(
                    color: context.colors.textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: CustomInputField(
                  controller: _amountController,
                  keyboardType: TextInputType.number,
                  labelText: l10n.amountSats,
                  fillColor: context.colors.inputFill,
                  enabled: true,
                  readOnly: !_isEditing,
                  onTap: () {
                    if (!_isEditing) {
                      setState(() {
                        _isEditing = true;
                      });
                    }
                  },
                  onChanged: (value) {
                    setState(() {});
                  },
                ),
              ),
              if (_isEditing) ...[
                const SizedBox(width: 12),
                IconButton(
                  icon: Icon(
                    CarbonIcons.checkmark,
                    size: 24,
                    color: hasChanges
                        ? context.colors.accent
                        : context.colors.textSecondary,
                  ),
                  onPressed: hasChanges
                      ? () {
                          final amount =
                              int.tryParse(_amountController.text.trim());
                          if (amount != null && amount > 0) {
                            context
                                .read<ThemeBloc>()
                                .add(DefaultZapAmountSet(amount));
                            setState(() {
                              _savedAmount = amount;
                              _isEditing = false;
                            });
                            AppSnackbar.success(
                                context, l10n.amountSavedSuccessfully);
                          } else {
                            AppSnackbar.error(
                                context, l10n.pleaseEnterValidAmount);
                          }
                        }
                      : null,
                ),
                const SizedBox(width: 4),
                IconButton(
                  icon: Icon(
                    CarbonIcons.close,
                    size: 24,
                    color: context.colors.textSecondary,
                  ),
                  onPressed: () {
                    _amountController.text = _savedAmount.toString();
                    setState(() {
                      _isEditing = false;
                    });
                  },
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNwcConnectedItem(BuildContext context, AppLocalizations l10n) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: context.colors.overlayLight,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          Icon(
            CarbonIcons.checkmark_filled,
            size: 22,
            color: context.colors.switchActive,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              l10n.nwcConnected,
              style: TextStyle(
                color: context.colors.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          GestureDetector(
            onTap: () async {
              final nwcService = AppDI.get<NwcService>();
              final message = l10n.nwcDisconnected;
              await nwcService.clearConnection();
              if (mounted) {
                setState(() {
                  _hasNwcConnection = false;
                });
                AppSnackbar.info(this.context, message);
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: context.colors.overlayLight,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    CarbonIcons.close,
                    size: 16,
                    color: context.colors.textPrimary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    l10n.nwcRemove,
                    style: TextStyle(
                      color: context.colors.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNwcInputItem(BuildContext context, AppLocalizations l10n) {
    final canConnect = _acceptedNwcDisclaimer && !_isNwcSaving;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: context.colors.overlayLight,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                CarbonIcons.connection_signal,
                size: 22,
                color: context.colors.textPrimary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.nwcTitle,
                  style: TextStyle(
                    color: context.colors.textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          CustomInputField(
            controller: _nwcUriController,
            labelText: l10n.nwcConnectionString,
            fillColor: context.colors.inputFill,
            enabled: !_isNwcSaving,
          ),
          const SizedBox(height: 16),
          Text(
            l10n.nwcDisclaimer,
            style: TextStyle(
              fontSize: 13,
              color: context.colors.textSecondary,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: GestureDetector(
              onTap: () => setState(
                  () => _acceptedNwcDisclaimer = !_acceptedNwcDisclaimer),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                SizedBox(
                  width: 24,
                  height: 24,
                  child: Checkbox(
                    value: _acceptedNwcDisclaimer,
                    onChanged: (value) => setState(
                        () => _acceptedNwcDisclaimer = value ?? false),
                    activeColor: context.colors.textPrimary,
                    checkColor: context.colors.background,
                    side: BorderSide(color: context.colors.textSecondary),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  l10n.nwcAccept,
                  style: TextStyle(
                    color: context.colors.textSecondary,
                    fontSize: 14,
                  ),
                ),
              ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: SecondaryButton(
              label: l10n.nwcConnect,
              onPressed: canConnect ? _saveNwcConnection : null,
              isLoading: _isNwcSaving,
              size: ButtonSize.large,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _saveNwcConnection() async {
    final l10n = AppLocalizations.of(context)!;
    final uri = _nwcUriController.text.trim();
    if (uri.isEmpty) {
      AppSnackbar.error(context, l10n.nwcPleaseEnterConnectionString);
      return;
    }

    setState(() => _isNwcSaving = true);

    final nwcService = AppDI.get<NwcService>();
    final result = await nwcService.saveConnectionUri(uri);

    if (!mounted) return;

    setState(() => _isNwcSaving = false);

    result.fold(
      (_) {
        setState(() {
          _hasNwcConnection = true;
          _nwcUriController.clear();
        });
        AppSnackbar.success(context, l10n.nwcConnectionSaved);
      },
      (error) {
        AppSnackbar.error(context, l10n.nwcInvalidConnectionString);
      },
    );
  }
}
