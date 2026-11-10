import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
// The quit path has to be held at the real preferences backend. A fake
// DocumentStore would skip the race this test exists to catch.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:tallynote/data/document.dart';
import 'package:tallynote/main.dart';

const _storedLibrary = '''
{"v":2,"folders":[{"id":"f1","name":"Home"}],"sheets":[{"id":"s1","title":"Rent","content":"1200 rent","folderId":"f1","pinned":true,"customTitle":true,"updated":"2026-01-01T00:00:00.000"}]}
''';

/// Holds the first preferences read so a quit can land while the in-memory
/// sheet list is still empty.
class _HoldReads extends InMemorySharedPreferencesStore {
  _HoldReads(super.data) : super.withData();

  Future<void>? _hold;

  void hold() {
    final gate = Completer<void>();
    _hold = gate.future;
    _release = gate;
  }

  Completer<void>? _release;

  void release() {
    final gate = _release;
    _hold = null;
    _release = null;
    if (gate != null && !gate.isCompleted) gate.complete();
  }

  @override
  Future<Map<String, Object>> getAll() async {
    final pending = _hold;
    if (pending != null) await pending;
    return super.getAll();
  }
}

void main() {
  final stored = jsonEncode(jsonDecode(_storedLibrary));

  tearDown(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('flush before load does not replace the stored library', () async {
    SharedPreferences.setMockInitialValues({
      'tallynote.sheets.v1': stored,
      'tallynote.active.v1': 's1',
    });
    // The cache is already warm during startup: _boot reads settings before
    // load(), so a quit in that gap can write without waiting on disk.
    await SharedPreferences.getInstance();
    final store = DocumentStore();
    expect(store.loaded, isFalse);
    expect(store.sheets, isEmpty);

    await expectLater(store.flush(), throwsA(isA<StateError>()));

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('tallynote.sheets.v1'), stored);
    await store.load();
    expect(store.sheets.single.content, '1200 rent');
    expect(store.folders.single.name, 'Home');
    expect(store.activeId, 's1');

    store.sheets.single.content = '1200 rent + 30';
    await store.flush();
    final again = DocumentStore();
    await again.load();
    expect(again.sheets.single.content, '1200 rent + 30');
    store.dispose();
    again.dispose();
  });

  test('a save queued before load does not erase stored sheets', () async {
    SharedPreferences.setMockInitialValues({
      'tallynote.sheets.v1': stored,
      'tallynote.active.v1': 's1',
    });
    await SharedPreferences.getInstance();
    final store = DocumentStore();
    store.sheets.add(Sheet(id: 'temp', title: 'Temp', content: 'scratch'));
    store.update('temp', content: 'scratch');
    await pumpEventQueue();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('tallynote.sheets.v1'), stored);
    await store.load();
    expect(store.sheets.single.content, '1200 rent');
    expect(store.sheets.any((s) => s.id == 'temp'), isFalse);
    store.dispose();
  });

  test('flush during load writes the library it just read', () async {
    SharedPreferences.setMockInitialValues({});
    final backend = _HoldReads({
      'flutter.tallynote.sheets.v1': stored,
      'flutter.tallynote.active.v1': 's1',
    })..hold();
    SharedPreferencesStorePlatform.instance = backend;
    addTearDown(backend.release);

    final store = DocumentStore();
    final loading = store.load();
    final flushing = store.flush();
    await pumpEventQueue();
    expect(store.loaded, isFalse);

    backend.release();
    await flushing;
    await loading;

    expect(store.loaded, isTrue);
    expect(store.sheets.single.content, '1200 rent');
    expect(store.folders.single.name, 'Home');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('tallynote.sheets.v1'), contains('1200 rent'));
    expect(prefs.getString('tallynote.sheets.v1'), contains('Home'));
    store.dispose();
  });

  testWidgets(
    'prepareQuit during startup keeps the saved library and still acknowledges',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final backend = _HoldReads({
        'flutter.tallynote.sheets.v1': stored,
        'flutter.tallynote.active.v1': 's1',
        'flutter.tallynote.autoRates': false,
      })..hold();
      SharedPreferencesStorePlatform.instance = backend;
      addTearDown(backend.release);

      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(const TallynoteApp());
      final codec = const StandardMethodCodec();
      Object? answer;
      var acknowledged = false;
      tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        'app.numbook/lifecycle',
        codec.encodeMethodCall(const MethodCall('prepareQuit')),
        (data) {
          answer = data == null ? null : codec.decodeEnvelope(data);
          acknowledged = true;
        },
      );
      await tester.pump();
      expect(acknowledged, isFalse, reason: 'load is still held');

      backend.release();
      for (var i = 0; i < 30 && !acknowledged; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }

      expect(acknowledged, isTrue);
      expect(answer, isTrue);
      final prefs = await SharedPreferences.getInstance();
      final doc = jsonDecode(prefs.getString('tallynote.sheets.v1')!) as Map;
      final sheets = doc['sheets'] as List;
      expect(sheets, isNotEmpty);
      expect(sheets.first['content'], '1200 rent');
      expect(sheets.first['title'], 'Rent');
      expect((doc['folders'] as List).first['name'], 'Home');
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
