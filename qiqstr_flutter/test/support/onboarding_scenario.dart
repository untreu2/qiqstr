import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../lib/core/di/app_di.dart';
import '../../lib/core/router/app_router.dart';
import '../../lib/data/services/auth_service.dart';
import '../../lib/l10n/app_localizations.dart';
import '../../lib/main.dart';
import '../../lib/presentation/blocs/welcome/welcome_bloc.dart';
import '../../lib/presentation/blocs/locale/locale_bloc.dart';
import '../../lib/presentation/blocs/locale/locale_event.dart';
import '../../lib/presentation/blocs/theme/theme_bloc.dart';
import '../../lib/ui/screens/auth/login_page.dart';
import '../../lib/ui/screens/auth/signup_page.dart';
import '../../lib/ui/screens/auth/welcome_page.dart';
import '../../lib/ui/screens/settings/keys_info_page.dart';
import '../../lib/ui/widgets/common/back_button_widget.dart';
import '../../lib/ui/widgets/common/common_buttons.dart';

Future<void> runOnboardingScenario(WidgetTester tester) async {
  FlutterSecureStorage.setMockInitialValues({});
  SharedPreferences.setMockInitialValues({});
  GoogleFonts.config.allowRuntimeFetching = false;
  await AuthService.instance.refreshCache();
  await GetIt.instance.reset();
  AppDI.registerLazySingleton<AuthService>(() => AuthService.instance);
  AppDI.registerFactory<WelcomeBloc>(WelcomeBloc.new);
  final localeBloc = LocaleBloc();
  final themeBloc = ThemeBloc();
  addTearDown(() async {
    await localeBloc.close();
    await themeBloc.close();
    await GetIt.instance.reset();
  });
  await tester.pumpWidget(MultiBlocProvider(
    providers: [
      BlocProvider.value(value: localeBloc),
      BlocProvider.value(value: themeBloc),
    ],
    child: const QiqstrApp(),
  ));
  await tester.pumpAndSettle();
  expect(find.byType(WelcomePage), findsOneWidget);

  for (final language in ['tr', 'de', 'en']) {
    localeBloc.add(LocaleChanged(Locale(language)));
    await tester.pumpAndSettle();
    final l10n = AppLocalizations.of(tester.element(find.byType(WelcomePage)))!;
    expect(find.text(l10n.welcomeAlreadyHaveAccount), findsOneWidget);
    expect(tester.takeException(), isNull);
  }

  final l10n = AppLocalizations.of(tester.element(find.byType(WelcomePage)))!;
  await tester.tap(find.byType(PrimaryButton));
  await tester.pumpAndSettle();
  expect(find.text(l10n.acceptanceOfTermsIsRequired), findsOneWidget);
  await tester.tap(find.byType(Checkbox));
  await tester.pumpAndSettle();
  expect(find.text(l10n.acceptanceOfTermsIsRequired), findsNothing);
  await tester.tap(find.text(l10n.welcomeAlreadyHaveAccount));
  await tester.pumpAndSettle();
  expect(find.byType(LoginPage), findsOneWidget);
  await tester.enterText(find.byType(TextField), 'invalid recovery input');
  await tester.tap(find.byType(PrimaryButton));
  await tester.pumpAndSettle();
  expect(find.byType(LoginPage), findsOneWidget);
  expect((await AuthService.instance.isAuthenticated()).data, isFalse);
  expect(tester.takeException(), isNull);
  await tester.tap(find.byType(BackButtonWidget));
  await tester.pumpAndSettle();
  expect(find.byType(WelcomePage), findsOneWidget);
  await tester.tap(find.byType(Checkbox));
  await tester.pumpAndSettle();
  await tester.tap(find.byType(PrimaryButton));
  await tester.pumpAndSettle();
  expect(find.byType(SignupPage), findsOneWidget);
  await tester.tap(find.byType(PrimaryButton));
  await tester.pumpAndSettle();
  expect(find.byType(KeysInfoPage), findsOneWidget);
  final page = tester.widget<KeysInfoPage>(find.byType(KeysInfoPage));
  expect(page.mnemonic.split(' '), hasLength(12));
  expect(page.npub, AuthService.instance.currentUserNpub);
  expect((await AuthService.instance.getStoredAccounts()).single.mnemonic,
      page.mnemonic);
  expect(
      AppRouter.router.routeInformationProvider.value.uri.path, '/keys-info');
  expect(tester.takeException(), isNull);
}
