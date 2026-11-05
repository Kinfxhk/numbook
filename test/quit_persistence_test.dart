import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tallynote/main.dart';
import 'package:tallynote/ui/editor_view.dart';

void main() {
  testWidgets('native prepareQuit persists the last editor keystroke before acknowledgement', (tester) async {
    SharedPreferences.setMockInitialValues({'tallynote.autoRates': false});
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const TallynoteApp());
    await tester.pumpAndSettle();
    final field = find.descendant(of: find.byType(EditorView), matching: find.byType(TextField));
    await tester.enterText(field, 'last edit immediately before quit');
    final codec = const StandardMethodCodec();
    Object? answer;
    var acknowledged = false;
    tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      'app.numbook/lifecycle', codec.encodeMethodCall(const MethodCall('prepareQuit')),
      (data) { answer = data == null ? null : codec.decodeEnvelope(data); acknowledged = true; },
    );
    await tester.pump();
    await tester.pump();
    expect(acknowledged, isTrue);
    expect(answer, isTrue);
    final prefs = await SharedPreferences.getInstance();
    final doc = jsonDecode(prefs.getString('tallynote.sheets.v1')!) as Map;
    expect((doc['sheets'] as List).first['content'], 'last edit immediately before quit');
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
