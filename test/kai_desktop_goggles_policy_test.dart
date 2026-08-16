import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:homecoming_app/services/core/kai_surface_context.dart';

void main() {
  test('desktop Homecoming is a permanent goggles-on workbench', () {
    final desktop =
        File('lib/screens/kai_desktop_shell.dart').readAsStringSync();

    expect(KaiSurfaceContext.desktop.goggles, KaiGoggles.on);
    expect(KaiSurfaceContext.desktop.allowsTechnicalConversation, isTrue);
    expect(KaiSurfaceContext.desktop.allowsGeneralTools, isTrue);

    expect(desktop, contains('static const bool _gogglesOn = true'));
    expect(
      desktop,
      contains(
        'KaiSurfaceContext get _desktopSurfaceContext => '
        'KaiSurfaceContext.desktop',
      ),
    );
    // The badge that tells Sadeq the state is permanent must still be shown.
    //
    // This used to assert the literal lowercase phrase `'goggles on'`, which
    // was a copy-edit tripwire, not a policy one: rewording the tooltip broke
    // the build while the policy itself never moved. Assert that the badge is
    // built and rendered instead — the wording is free to change.
    expect(desktop, contains('Widget _gogglesBadge()'));
    expect(desktop, contains('_gogglesBadge()'));

    // Nothing may reintroduce a way to turn them off: no persisted key, no
    // setter, no loader. These are the real invariant.
    expect(desktop, isNot(contains('kai_desktop_goggles_on')));
    expect(desktop, isNot(contains('_setGoggles(')));
    expect(desktop, isNot(contains('_loadGogglesState(')));
    expect(desktop, isNot(contains('_gogglesOn =\n')),
        reason:
            'the flag is a const; any reassignment is a toggle in disguise');
  });

  test('Messenger remains a goggles-off friend lane', () {
    expect(KaiSurfaceContext.messenger.goggles, KaiGoggles.off);
    expect(KaiSurfaceContext.messenger.allowsTechnicalConversation, isFalse);
    expect(KaiSurfaceContext.messenger.allowsGeneralTools, isFalse);
  });
}
