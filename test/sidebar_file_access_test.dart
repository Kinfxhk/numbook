import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tallynote/main.dart';
import 'package:tallynote/i18n/strings.dart';

void main() {
  testWidgets('wide non-Mac sidebar keeps File actions reachable', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    SharedPreferences.setMockInitialValues({
      'tallynote.autoRates': false,
      'tallynote.locale': 'en',
    });
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const TallynoteApp());
    await tester.pumpAndSettle();
    final button = find.byTooltip(T.of('en', 'file'));
    expect(button, findsOneWidget);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.text(T.of('en', 'fileOpen')), findsOneWidget);
    expect(find.text(T.of('en', 'exportCsv')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 600));
    debugDefaultTargetPlatformOverride = null;
  });
}
