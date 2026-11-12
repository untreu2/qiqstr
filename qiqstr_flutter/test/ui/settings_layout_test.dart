import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../lib/l10n/app_localizations.dart';
import '../../lib/presentation/blocs/locale/locale_bloc.dart';
import '../../lib/presentation/blocs/theme/theme_bloc.dart';
import '../../lib/ui/screens/settings/display_page.dart';
import '../../lib/ui/screens/settings/settings_page.dart';

void main() {
  for (final language in ['en', 'tr', 'de']) {
    for (final scale in [1.0, 1.3]) {
      for (final page in [const SettingsPage(), const DisplayPage()]) {
        testWidgets(
          '${page.runtimeType} fits a narrow phone in $language at $scale',
          (tester) async {
            SharedPreferences.setMockInitialValues({});
            GoogleFonts.config.allowRuntimeFetching = false;
            tester.view.physicalSize = const Size(320, 800);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            final theme = ThemeBloc();
            final locale = LocaleBloc();
            addTearDown(theme.close);
            addTearDown(locale.close);
            await tester.pumpWidget(
              MultiBlocProvider(
                providers: [
                  BlocProvider.value(value: theme),
                  BlocProvider.value(value: locale),
                ],
                child: MaterialApp(
                  locale: Locale(language),
                  localizationsDelegates:
                      AppLocalizations.localizationsDelegates,
                  supportedLocales: AppLocalizations.supportedLocales,
                  builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(
                      context,
                    ).copyWith(textScaler: TextScaler.linear(scale)),
                    child: child!,
                  ),
                  home: page,
                ),
              ),
            );
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            await tester.drag(
              find.byType(Scrollable).first,
              const Offset(0, -400),
            );
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox.shrink());
          },
        );
      }
    }
  }
}
