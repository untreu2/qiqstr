import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../theme/theme_manager.dart';
import '../../widgets/common/back_button_widget.dart';
import 'package:carbon_icons/carbon_icons.dart';
import '../../widgets/common/title_widget.dart';
import '../../widgets/common/custom_input_field.dart';
import '../../widgets/common/snackbar_widget.dart';

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
    final themeManager = Provider.of<ThemeManager>(context, listen: false);
    _savedAmount = themeManager.defaultZapAmount;
    _amountController = TextEditingController(text: _savedAmount.toString());
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

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
                    _buildPaymentsSection(context, themeManager),
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

  Widget _buildPaymentsSection(BuildContext context, ThemeManager themeManager) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          _buildOneTapZapToggleItem(context, themeManager),
          const SizedBox(height: 8),
          if (themeManager.oneTapZap) ...[
            _buildAmountInputItem(context, themeManager),
            const SizedBox(height: 8),
          ],
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildOneTapZapToggleItem(BuildContext context, ThemeManager themeManager) {
    return GestureDetector(
      onTap: () => themeManager.setOneTapZap(!themeManager.oneTapZap),
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
              value: themeManager.oneTapZap,
              onChanged: (value) => themeManager.setOneTapZap(value),
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

  Widget _buildAmountInputItem(BuildContext context, ThemeManager themeManager) {
    final currentAmount = int.tryParse(_amountController.text.trim()) ?? 0;
    final hasChanges = currentAmount != _savedAmount && currentAmount > 0;

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
                    color: hasChanges ? context.colors.accent : context.colors.textSecondary,
                  ),
                  onPressed: hasChanges
                      ? () {
                          final amount = int.tryParse(_amountController.text.trim());
                          if (amount != null && amount > 0) {
                            themeManager.setDefaultZapAmount(amount);
                            setState(() {
                              _savedAmount = amount;
                              _isEditing = false;
                            });
                            AppSnackbar.success(context, 'Amount saved successfully');
                          } else {
                            AppSnackbar.error(context, 'Please enter a valid amount');
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

