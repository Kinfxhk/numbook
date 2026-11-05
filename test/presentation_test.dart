import 'package:flutter_test/flutter_test.dart';
import 'package:tallynote/engine/engine.dart';
import 'package:tallynote/engine/presentation.dart';
import 'package:tallynote/engine/values.dart';

void main() {
  group('formatNumber scientific sign', () {
    test('negative tiny values use one minus sign', () {
      expect(formatNumber(-1e-10), '-1e-10');
      expect(formatNumber(-1e-16), '-1e-16');
    });

    test('negative huge values use one minus sign', () {
      expect(formatNumber(-1e16), '-1e+16');
    });

    test('signed zero displays as zero', () {
      expect(formatNumber(-0.0), '0');
    });
  });

  group('DisplayPrecision auto', () {
    final format = NumberFormat.us;

    test('ordinary numbers show about four decimal places', () {
      expect(
        presentValue(const NumValue(1 / 3), precision: DisplayPrecision.auto, format: format),
        '0.3333',
      );
    });

    test('money keeps conventional decimals', () {
      expect(
        presentValue(const MoneyValue(12.3, 'USD'), precision: DisplayPrecision.auto, format: format),
        r'$12.30',
      );
    });

    test('percentages show about two decimals', () {
      expect(
        presentValue(const PercentValue(0.125), precision: DisplayPrecision.auto, format: format),
        '12.5%',
      );
    });

    test('nonzero tiny values stay scientific, not zero', () {
      final s = presentValue(
        const NumValue(-1e-10),
        precision: DisplayPrecision.auto,
        format: format,
      );
      expect(s, contains('e'));
      expect(s, isNot('0'));
    });
  });

  group('precision preference end-to-end', () {
    test('a = 1/3 then a*3 keeps full value but display can read 1', () {
      final engine = SheetEngine(now: DateTime(2026, 10, 30, 9));
      final raw = engine.evaluate(['a = 1/3', 'a * 3']);
      final shown = presentLine(raw[1], DisplayPrecision.auto, NumberFormat.us);
      expect(raw[1].value, isA<NumValue>());
      expect((raw[1].value as NumValue).value, closeTo(1.0, 1e-12));
      expect(shown.display, '1');
    });

    test('fixed four decimals mode', () {
      expect(
        presentValue(const NumValue(1 / 3), precision: DisplayPrecision.d4, format: NumberFormat.us),
        '0.3333',
      );
    });

    test('full mode keeps engine-grade tail', () {
      final engine = SheetEngine(now: DateTime(2026, 10, 30, 9));
      final raw = engine.evaluate(['1/3']).first;
      final full = presentLine(raw, DisplayPrecision.full, NumberFormat.us);
      expect(full.display!.length, greaterThan(6));
      expect(raw.value, isA<NumValue>());
    });
  });

  group('presentFullValue', () {
    test('copy number uses double toString not display rounding', () {
      const v = NumValue(1.234567890123);
      final full = presentFullValue(v, format: NumberFormat.us);
      expect(full, contains('890123'));
      expect(
        presentValue(v, precision: DisplayPrecision.d2, format: NumberFormat.us),
        isNot(full),
      );
    });

    test('money full copy keeps currency and raw magnitude', () {
      const v = MoneyValue(1234.5678, 'USD');
      final full = presentFullValue(v, format: NumberFormat.us);
      expect(full, startsWith(r'$'));
      expect(full, contains('5678'));
    });
  });

  group('displayPrecisionFrom', () {
    test('persists keys round-trip', () {
      for (final p in DisplayPrecision.values) {
        expect(displayPrecisionFrom(displayPrecisionKey(p)), p);
      }
    });
  });
}
