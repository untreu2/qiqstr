import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../lib/presentation/blocs/theme/theme_bloc.dart';
import '../../../../lib/presentation/blocs/theme/theme_event.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('system brightness follows changes until an explicit theme is selected',
      () async {
    SharedPreferences.setMockInitialValues({});
    final bloc = ThemeBloc(systemIsDark: true);
    addTearDown(bloc.close);
    expect(bloc.state.isDarkMode, isTrue);
    var changed = bloc.stream.first;
    bloc.add(const ThemeSystemBrightnessChanged(false));
    expect((await changed).isDarkMode, isFalse);
    changed = bloc.stream.first;
    bloc.add(const ThemeSetDark(true));
    expect((await changed).isDarkMode, isTrue);
    changed = bloc.stream.first;
    bloc.add(const ThemeSetSystem());
    expect((await changed).isDarkMode, isFalse);
  });

  test('theme toggling uses the current system brightness', () async {
    SharedPreferences.setMockInitialValues({});
    final bloc = ThemeBloc(systemIsDark: true);
    addTearDown(bloc.close);
    final changed = bloc.stream.first;
    bloc.add(const ThemeToggled());
    expect((await changed).isDarkModeOverride, isFalse);
  });
  for (final order in [
    ['bad', '1', '2', '3'],
    ['0', '0', '2', '3'],
    ['1', '2', '3', '4'],
  ]) {
    test('recovers from corrupt navigation preference $order', () async {
      SharedPreferences.setMockInitialValues({'bottom_nav_order': order});
      final bloc = ThemeBloc();
      addTearDown(bloc.close);
      final loaded = bloc.stream.first;
      bloc.add(const ThemeInitialized());
      expect((await loaded).bottomNavOrder, [0, 1, 2, 3]);
    });
  }

  test('accepts a valid permutation and ignores out-of-range tab IDs',
      () async {
    SharedPreferences.setMockInitialValues({});
    final bloc = ThemeBloc();
    addTearDown(bloc.close);
    final changed = bloc.stream.first;
    bloc.add(const BottomNavOrderSet([3, 2, 1, 0]));
    expect((await changed).bottomNavOrder, [3, 2, 1, 0]);
    bloc.add(const BottomNavOrderSet([4, 5, 6, 7]));
    await Future<void>.delayed(Duration.zero);
    expect(bloc.state.bottomNavOrder, [3, 2, 1, 0]);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('bottom_nav_order'), ['3', '2', '1', '0']);
  });
}
