import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
// Inject real backend write failures, not a mocked DocumentStore.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:tallynote/data/document.dart';

class _FailingActiveWrite extends InMemorySharedPreferencesStore {
  _FailingActiveWrite() : super.empty();
  bool fail = true;
  bool returnFalse = false;

  @override
  Future<bool> setValue(String type, String key, Object value) async {
    if (fail && key.endsWith('tallynote.active.v1')) {
      if (returnFalse) return false;
      throw StateError('simulated active-key disk failure');
    }
    return super.setValue(type, key, value);
  }
}

void main() {
  test(
    'active-key false result blocks quit and next successful save recovers',
    () async {
      SharedPreferences.setMockInitialValues({});
      final backend = _FailingActiveWrite()..returnFalse = true;
      SharedPreferencesStorePlatform.instance = backend;
      final store = DocumentStore();
      await store.load();
      await expectLater(store.flush(), throwsStateError);
      expect(store.saveFailed, isTrue);
      backend.fail = false;
      await store.flush();
      expect(store.saveFailed, isFalse);
      store.dispose();
    },
  );

  test('document save retries after active-key backend exception', () async {
    SharedPreferences.setMockInitialValues({});
    final backend = _FailingActiveWrite();
    SharedPreferencesStorePlatform.instance = backend;
    final store = DocumentStore();
    await store.load();
    store.sheets.first.content = 'first attempt';
    await expectLater(store.flush(), throwsStateError);
    backend.fail = false;
    store.sheets.first.content = 'latest content after recovery';
    await store.flush();
    expect(store.saveFailed, isFalse);
    final raw = (await SharedPreferences.getInstance()).getString(
      'tallynote.sheets.v1',
    )!;
    expect(
      (jsonDecode(raw)['sheets'] as List).single['content'],
      'latest content after recovery',
    );
    final reload = DocumentStore();
    await reload.load();
    expect(reload.active!.content, 'latest content after recovery');
    store.dispose();
    reload.dispose();
  });
}
