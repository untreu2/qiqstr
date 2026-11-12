import 'package:flutter_test/flutter_test.dart';

import '../../../../lib/data/services/auth_service.dart';
import '../../../../lib/data/services/validation_service.dart';
import '../../../../lib/presentation/blocs/auth/auth_bloc.dart';
import '../../../../lib/presentation/blocs/auth/auth_event.dart';
import '../../../../lib/presentation/blocs/auth/auth_state.dart';

void main() {
  test('clearing invalid input removes its validation error', () async {
    final bloc = AuthBloc(
      authService: AuthService.instance,
      validationService: ValidationService.instance,
    );
    addTearDown(bloc.close);
    final invalid = bloc.stream.first;
    bloc.add(const NsecInputChanged('invalid'));
    expect((await invalid as AuthInputState).validationError, isNotNull);
    final cleared = bloc.stream.first;
    bloc.add(const NsecInputChanged(''));
    expect((await cleared as AuthInputState).validationError, isNull);
  });
}
