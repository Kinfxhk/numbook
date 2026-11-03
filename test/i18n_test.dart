import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tallynote/i18n/strings.dart';
import 'package:tallynote/main.dart';
import 'package:tallynote/ui/cheat_sheet.dart';

void main() {
  const locales = ['en', 'zh_Hant', 'zh_Hans', 'ja', 'ko'];

  test('five locales have the same keys as English', () {
    expect(T.supported.keys, orderedEquals(locales));
    expect(T.switchLabel.keys, orderedEquals(locales));
    expect(T.tables.keys, orderedEquals(locales));

    final en = T.tables['en']!;
    final enKeys = en.keys.toSet();
    expect(enKeys, isNotEmpty);
    final placeholder = RegExp(r'\{[A-Za-z0-9_]+\}');

    for (final locale in locales) {
      final table = T.tables[locale]!;
      expect(table.keys.toSet(), enKeys, reason: '$locale keys');
      for (final entry in en.entries) {
        final value = table[entry.key]!;
        expect(value.trim(), isNotEmpty, reason: '$locale.${entry.key}');
        expect(
          placeholder.allMatches(value).map((m) => m[0]).toSet(),
          placeholder.allMatches(entry.value).map((m) => m[0]).toSet(),
          reason: '$locale.${entry.key} placeholders',
        );
      }
    }
  });

  test('lookups and placeholders', () {
    expect(T.of('en', 'newSheet'), 'New sheet');
    expect(T.of('zh_Hant', 'newSheet'), '新記事');
    expect(T.of('zh_Hans', 'newSheet'), '新笔记');
    expect(T.of('ja', 'newSheet'), '新しいシート');
    expect(T.of('ko', 'newSheet'), '새 시트');
    expect(
      T.format('zh_Hant', 'linesAnswers', {'lines': '3', 'answers': '2'}),
      '3 行 · 2 個答案',
    );
    expect(
      T.format('ja', 'linesAnswers', {'lines': '3', 'answers': '2'}),
      '3 行 · 2 個の答え',
    );
    expect(
      T.format('ko', 'linesAnswers', {'lines': '3', 'answers': '2'}),
      '3줄 · 답 2개',
    );
    // unknown keys fall back to the key itself rather than crashing
    expect(T.of('en', 'nope'), 'nope');
    expect(T.of('ja', 'nope'), 'nope');
  });

  test('cheat sheet titles are translated; examples stay engine language', () {
    final kana = RegExp('[ぁ-んァ-ン]');
    final hangul = RegExp('[가-힣]');
    for (final group in cheatSheet) {
      expect(group.titleKey, startsWith('cheat'));
      for (final locale in locales) {
        final title = T.of(locale, group.titleKey);
        expect(
          title,
          isNot(group.titleKey),
          reason: '$locale ${group.titleKey}',
        );
        expect(title.trim(), isNotEmpty);
      }
      for (final row in group.rows) {
        expect(kana.hasMatch(row.input), isFalse, reason: row.input);
        expect(hangul.hasMatch(row.input), isFalse, reason: row.input);
      }
    }
  });

  testWidgets('switching language changes the sidebar', (tester) async {
    SharedPreferences.setMockInitialValues({'tallynote.locale': 'en'});
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const TallynoteApp());
    await tester.pump(const Duration(milliseconds: 60));
    expect(find.text('New sheet'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.tune).first);
    await tester.pumpAndSettle();
    for (final label in T.switchLabel.values) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    await tester.tap(find.text('繁'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(TextButton).last); // Done
    await tester.pumpAndSettle();

    expect(find.text('新記事'), findsOneWidget);
    expect(find.text('New sheet'), findsNothing);
  });

  testWidgets('a Japanese system locale uses ja', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.platformDispatcher.localeTestValue = const Locale('ja');
    addTearDown(tester.platformDispatcher.clearLocaleTestValue);
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const TallynoteApp());
    await tester.pump(const Duration(milliseconds: 60));
    expect(find.text('新しいシート'), findsOneWidget);
  });

  testWidgets('a Korean system locale uses ko', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.platformDispatcher.localeTestValue = const Locale('ko');
    addTearDown(tester.platformDispatcher.clearLocaleTestValue);
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const TallynoteApp());
    await tester.pump(const Duration(milliseconds: 60));
    expect(find.text('새 시트'), findsOneWidget);
  });
}
