import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../theme/theme_manager.dart';
import '../../widgets/common/title_widget.dart';
import '../../widgets/common/top_action_bar_widget.dart';
import '../../widgets/common/common_buttons.dart';
import '../../widgets/qr_scanner_widget.dart';
import '../../../data/services/auth_service.dart';
import '../../../l10n/app_localizations.dart';

class ShareProfileScreen extends StatefulWidget {
  final Map<String, dynamic> user;
  final String npub;

  const ShareProfileScreen({
    super.key,
    required this.user,
    required this.npub,
  });

  @override
  State<ShareProfileScreen> createState() => _ShareProfileScreenState();
}

class _ShareProfileScreenState extends State<ShareProfileScreen> {
  late final ScrollController _scrollController;
  final ValueNotifier<bool> _showTitleBubble = ValueNotifier(false);

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController()..addListener(_scrollListener);
  }

  void _scrollListener() {
    if (_scrollController.hasClients) {
      final shouldShow = _scrollController.offset > 100;
      if (_showTitleBubble.value != shouldShow) {
        _showTitleBubble.value = shouldShow;
      }
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _showTitleBubble.dispose();
    super.dispose();
  }

  void _navigateToScannedProfile(String scannedValue) {
    String raw = scannedValue.trim();
    if (raw.startsWith('nostr:')) raw = raw.substring(6);

    String npub = '';
    String pubkeyHex = '';

    if (raw.startsWith('npub1')) {
      npub = raw;
      try {
        pubkeyHex = AuthService.instance.npubToHex(raw) ?? '';
      } catch (_) {
        return;
      }
    } else if (raw.startsWith('nprofile1')) {
      try {
        final decoded = AuthService.instance.decodeTlvBech32(raw) ?? {};
        pubkeyHex = decoded['pubkey'] as String? ?? '';
      } catch (_) {
        return;
      }
    } else if (RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(raw)) {
      pubkeyHex = raw;
    } else {
      return;
    }

    if (pubkeyHex.isEmpty) return;

    final router = GoRouter.of(context);
    final currentLocation = GoRouterState.of(context).matchedLocation;
    final basePath = currentLocation.startsWith('/home/feed')
        ? '/home/feed'
        : currentLocation.startsWith('/home/notifications')
            ? '/home/notifications'
            : '';

    final profileRoute =
        '$basePath/profile?npub=${Uri.encodeComponent(npub)}&pubkey=${Uri.encodeComponent(pubkeyHex)}';

    Navigator.of(context).pop();
    router.push(profileRoute);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.colors;
    final npub = widget.npub;
    final name = widget.user['name'] as String? ?? '';
    final nip05 = widget.user['nip05'] as String? ?? '';
    final displayName = name.isNotEmpty
        ? name
        : (nip05.isNotEmpty ? nip05.split('@').first : l10n.anonymous);
    final pageTitle = "$displayName's Profile";

    return Scaffold(
      backgroundColor: colors.background,
      body: Stack(
        children: [
          CustomScrollView(
            controller: _scrollController,
            slivers: [
              SliverToBoxAdapter(
                child: SizedBox(
                  height: MediaQuery.of(context).padding.top + 60,
                ),
              ),
              SliverToBoxAdapter(
                child: TitleWidget(
                  title: pageTitle,
                  fontSize: 32,
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                ),
              ),
              SliverToBoxAdapter(
                child: const SizedBox(height: 24),
              ),
              SliverToBoxAdapter(
                child: Center(
                  child: Column(
                    children: [
                      Builder(
                        builder: (context) {
                          final qrSize = MediaQuery.of(context).size.width - 80;
                          return Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(24),
                            ),
                            child: QrImageView(
                              data: npub,
                              version: QrVersions.auto,
                              size: qrSize,
                              backgroundColor: Colors.white,
                              eyeStyle: const QrEyeStyle(
                                eyeShape: QrEyeShape.square,
                                color: Colors.black,
                              ),
                              dataModuleStyle: const QrDataModuleStyle(
                                dataModuleShape: QrDataModuleShape.square,
                                color: Colors.black,
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 24),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: Text(
                          npub,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: colors.textSecondary,
                            letterSpacing: 0.5,
                            height: 1.5,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: SizedBox(
                          width: double.infinity,
                          child: PrimaryButton(
                            label: l10n.scanQRCode,
                            icon: Icons.qr_code_scanner,
                            size: ButtonSize.large,
                            onPressed: () {
                              Navigator.of(context, rootNavigator: true).push(
                                MaterialPageRoute(
                                  builder: (_) => QrScannerWidget(
                                    onScanComplete: (value) {
                                      _navigateToScannedProfile(value);
                                    },
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 150),
                    ],
                  ),
                ),
              ),
            ],
          ),
          TopActionBarWidget(
            onBackPressed: () => Navigator.of(context).pop(),
            showShareButton: false,
            centerBubble: Text(
              pageTitle,
              style: TextStyle(
                color: colors.background,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            centerBubbleVisibility: _showTitleBubble,
            onCenterBubbleTap: () {
              _scrollController.animateTo(
                0,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut,
              );
            },
          ),
        ],
      ),
    );
  }
}
