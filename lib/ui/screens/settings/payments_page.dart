import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../theme/theme_manager.dart';
import '../../widgets/common/back_button_widget.dart';
import 'package:carbon_icons/carbon_icons.dart';
import '../../widgets/common/title_widget.dart';
import '../../widgets/common/custom_input_field.dart';
import '../../widgets/common/snackbar_widget.dart';
import '../../../presentation/blocs/theme/theme_bloc.dart';
import '../../../presentation/blocs/theme/theme_event.dart';
import '../../../presentation/blocs/theme/theme_state.dart';

class PaymentsPage extends StatefulWidget {
  const PaymentsPage({super.key});

  @override
  State<PaymentsPage> createState() => _PaymentsPageState();
}

class _PaymentsPageState extends State<PaymentsPage> {
  late TextEditingController _amountController;
  bool _isEditing = false;
  int _savedAmount = 21;

  @override
  void initState() {
    super.initState();
    final themeState = context.read<ThemeBloc>().state;
    _savedAmount = themeState.defaultZapAmount;
    _amountController = TextEditingController(text: _savedAmount.toString());
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

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
                    _buildPaymentsSection(context, themeState),
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
        title: 'Payments',
        fontSize: 32,
        subtitle: "Manage your payment preferences.",
        padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
      ),
    );
  }

  Widget _buildPaymentsSection(BuildContext context, ThemeState themeState) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          _buildOneTapZapToggleItem(context, themeState),
          const SizedBox(height: 8),
          if (themeState.oneTapZap) ...[
            _buildAmountInputItem(context, themeState),
            const SizedBox(height: 8),
          ],
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildOneTapZapToggleItem(
      BuildContext context, ThemeState themeState) {
    return GestureDetector(
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
                'One Tap Zap',
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

  Widget _buildAmountInputItem(BuildContext context, ThemeState themeState) {
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
                CarbonIcons.money,
                size: 22,
                color: context.colors.textPrimary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Default Zap Amount',
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
                  labelText: 'Amount (sats)',
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
                                context, 'Amount saved successfully');
                          } else {
                            AppSnackbar.error(
                                context, 'Please enter a valid amount');
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
}
