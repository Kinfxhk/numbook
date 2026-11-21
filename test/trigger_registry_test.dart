import 'package:flutter_test/flutter_test.dart';
import 'package:tallynote/engine/engine.dart';
import 'package:tallynote/engine/triggers.dart';

void main() {
  group('Trigger Registry — One meaning, one trigger', () {
    test('rule IDs are unique and tiers are ordered monotonically', () {
      final seenIds = <String>{};
      var prevTier = 0;
      for (final rule in triggerRegistry) {
        expect(
          seenIds.add(rule.id),
          isTrue,
          reason: 'Duplicate trigger rule id: ${rule.id}',
        );
        expect(
          rule.tier >= prevTier,
          isTrue,
          reason:
              'Rule ${rule.id} (tier ${rule.tier}) breaks ladder order after tier $prevTier',
        );
        expect(
          rule.triggers,
          isNotEmpty,
          reason: 'Rule ${rule.id} must declare at least one canonical trigger',
        );
        prevTier = rule.tier;
      }
    });

    test('no two rules claim the same normalized trigger signature', () {
      final ownerByTrigger = <String, String>{};
      for (final rule in triggerRegistry) {
        for (final raw in rule.triggers) {
          final norm = raw.trim().toLowerCase();
          final existing = ownerByTrigger[norm];
          expect(
            existing,
            isNull,
            reason:
                'Trigger collision on "$norm": claimed by both "$existing" and "${rule.id}"',
          );
          ownerByTrigger[norm] = rule.id;
        }
      }
    });

    test('every rule satisfies its positive and negative engine contracts', () {
      final engine = SheetEngine(
        now: DateTime(2026, 10, 31, 9),
        rates: const {'USD': 1, 'HKD': 7.8},
      );

      for (final rule in triggerRegistry) {
        final lines = [...rule.contextLines, rule.positiveExample];
        final res = engine.evaluate(lines).last;
        expect(
          res.display,
          rule.expectedDisplay,
          reason:
              'Positive example failed for rule "${rule.id}": "${rule.positiveExample}"',
        );

        if (rule.negativeExample != null) {
          final neg = engine.evaluate([rule.negativeExample!]).single;
          expect(
            neg.display,
            isNull,
            reason:
                'Negative guard violated for rule "${rule.id}": "${rule.negativeExample}" answered "${neg.display}"',
          );
        }
      }
    });

    test('user-defined variables always override built-in aggregate triggers', () {
      final engine = SheetEngine(now: DateTime(2026, 10, 31, 9));
      for (final kw in const ['total', 'subtotal', 'sum', 'average', '小計', '合共']) {
        final results = engine.evaluate(['100', '200', '$kw = 42', kw]);
        expect(
          results.last.display,
          '42',
          reason: 'User variable "$kw = 42" must shadow built-in aggregate "$kw"',
        );
      }
    });
  });
}
