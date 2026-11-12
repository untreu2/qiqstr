import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../lib/l10n/app_localizations.dart';
import '../../lib/presentation/blocs/dm/dm_bloc.dart';
import '../../lib/presentation/blocs/dm/dm_event.dart';
import '../../lib/presentation/blocs/dm_indicator/dm_indicator_bloc.dart';
import '../../lib/presentation/blocs/dm_indicator/dm_indicator_event.dart';
import '../../lib/presentation/blocs/dm_indicator/dm_indicator_state.dart';
import '../../lib/presentation/blocs/notification_indicator/notification_indicator_bloc.dart';
import '../../lib/presentation/blocs/notification_indicator/notification_indicator_event.dart';
import '../../lib/presentation/blocs/notification_indicator/notification_indicator_state.dart';
import '../../lib/presentation/blocs/theme/theme_bloc.dart';
import '../../lib/presentation/blocs/theme/theme_event.dart';
import '../../lib/ui/screens/home_navigator.dart';

class _Notifications implements NotificationIndicatorBloc {
  @override
  NotificationIndicatorState get state => const NotificationIndicatorInitial();

  @override
  Stream<NotificationIndicatorState> get stream => const Stream.empty();

  @override
  void add(NotificationIndicatorEvent event) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _DmIndicator implements DmIndicatorBloc {
  @override
  DmIndicatorState get state => const DmIndicatorInitial();

  @override
  Stream<DmIndicatorState> get stream => const Stream.empty();

  @override
  void add(DmIndicatorEvent event) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Messages implements DmBloc {
  @override
  void add(DmEvent event) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    GetIt.instance
        .registerSingleton<NotificationIndicatorBloc>(_Notifications());
    GetIt.instance.registerSingleton<DmIndicatorBloc>(_DmIndicator());
    GetIt.instance.registerSingleton<DmBloc>(_Messages());
  });
  tearDown(() => GetIt.instance.reset());

  for (final order in [
    [0, 1, 2, 3],
    [2, 3, 1, 0],
    [3, 2, 0, 1],
  ]) {
    testWidgets('tabs retain their destination after reordering to $order',
        (tester) async {
      final theme = ThemeBloc()..add(BottomNavOrderSet(order));
      final paths = [
        '/home/feed',
        '/home/dm',
        '/home/wallet',
        '/home/notifications'
      ];
      final router = GoRouter(
        initialLocation: paths.first,
        routes: [
          StatefulShellRoute.indexedStack(
            builder: (context, state, shell) => HomeNavigator(
              npub: 'test-account',
              navigationShell: shell,
            ),
            branches: [
              for (var index = 0; index < paths.length; index++)
                StatefulShellBranch(routes: [
                  GoRoute(
                    path: paths[index],
                    builder: (context, state) => Text('branch $index'),
                  ),
                ]),
            ],
          ),
        ],
      );
      addTearDown(theme.close);
      addTearDown(router.dispose);
      await tester.pumpWidget(BlocProvider.value(
        value: theme,
        child: MaterialApp.router(
          routerConfig: router,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
        ),
      ));
      await tester.pumpAndSettle();

      for (final index in order) {
        await tester.tap(find.byKey(ValueKey('navigation-$index')));
        await tester.pumpAndSettle();
        expect(router.routeInformationProvider.value.uri.path, paths[index]);
        expect(find.text('branch $index'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }

      await tester.tap(find.byKey(const ValueKey('navigation-1')));
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, paths.first);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
