import 'engine.dart';
import 'values.dart';

/// How the app (not the CLI) rounds numbers for display and export snapshots.
enum DisplayPrecision { auto, d2, d4, d8, full }

DisplayPrecision displayPrecisionFrom(String? key) => switch (key) {
  '2' => DisplayPrecision.d2,
  '4' => DisplayPrecision.d4,
  '8' => DisplayPrecision.d8,
  'full' => DisplayPrecision.full,
  _ => DisplayPrecision.auto,
};

String displayPrecisionKey(DisplayPrecision p) => switch (p) {
  DisplayPrecision.d2 => '2',
  DisplayPrecision.d4 => '4',
  DisplayPrecision.d8 => '8',
  DisplayPrecision.full => 'full',
  DisplayPrecision.auto => 'auto',
};

int _moneyDecimals(String currency) =>
    currency == 'JPY' || currency == 'KRW' ? 0 : 2;

/// True when a nonzero magnitude would print as exact zero at [decimals].
bool _vanishesAt(double v, int decimals) {
  if (v == 0) return false;
  final fixed = double.parse(v.toStringAsFixed(decimals));
  return fixed == 0;
}

int? _autoPlainDecimals(double v) {
  if (v == 0) return null;
  // Keep ordinary values compact; tinies go scientific (not fixed-4 → 0.0000).
  if (v.abs() >= 1e15 || v.abs() < 1e-4) return null;
  return 4;
}

int? _decimalsFor(DisplayPrecision precision, Value value) {
  switch (precision) {
    case DisplayPrecision.full:
      return null;
    case DisplayPrecision.d2:
      return 2;
    case DisplayPrecision.d4:
      return 4;
    case DisplayPrecision.d8:
      return 8;
    case DisplayPrecision.auto:
      return switch (value) {
        MoneyValue(:final currency) => _moneyDecimals(currency),
        PercentValue() => 2,
        NumValue(:final unit) when unit != null => 4,
        NumValue(:final value) => _autoPlainDecimals(value),
        _ => null,
      };
  }
}

double? _numericMagnitude(Value value) => switch (value) {
  NumValue(:final value) => value,
  MoneyValue(:final value) => value,
  PercentValue(:final ratio) => ratio * 100,
  _ => null,
};

/// Scientific display when fixed rounding would erase a nonzero value.
String _scientificFallback(
  double v, {
  required NumberFormat format,
  String? unitSuffix,
  String? moneyPrefix,
}) {
  final body = formatNumber(v, format: format);
  final roundedNote = '≈ $body';
  if (moneyPrefix != null) return '$moneyPrefix$roundedNote';
  if (unitSuffix != null) return '$roundedNote $unitSuffix';
  return roundedNote;
}

/// One presentation path for UI answers and app-initiated exports.
String presentValue(
  Value value, {
  DisplayPrecision precision = DisplayPrecision.auto,
  NumberFormat format = NumberFormat.us,
}) {
  if (precision == DisplayPrecision.full) {
    return presentFullValue(value, format: format);
  }
  final decimals = _decimalsFor(precision, value);
  final mag = _numericMagnitude(value);

  // Nonzero tinies must never become a lying exact zero in compact modes.
  if (mag != null &&
      mag != 0 &&
      decimals != null &&
      _vanishesAt(mag, decimals)) {
    return switch (value) {
      NumValue(:final unit) => _scientificFallback(
        mag,
        format: format,
        unitSuffix: unit == null ? null : _unitSuffix(unit.id, mag),
      ),
      MoneyValue(:final currency) => _scientificFallback(
        mag,
        format: format,
        moneyPrefix: currencySymbols[currency] ?? '$currency ',
      ),
      PercentValue() => '${_scientificFallback(mag, format: format)}%',
      _ => formatNumber(mag, format: format),
    };
  }

  if (precision == DisplayPrecision.auto &&
      value is NumValue &&
      value.unit == null) {
    final v = value.value;
    if (v != 0 && (v.abs() >= 1e15 || v.abs() < 1e-4)) {
      return formatNumber(v, format: format);
    }
  }

  return formatValue(
    value,
    decimals: decimals,
    format: format,
    trimFraction:
        precision == DisplayPrecision.auto &&
        (value is NumValue || value is PercentValue),
  );
}

String _unitSuffix(String id, double value) {
  const symbols = {'C': '°C', 'F': '°F'};
  const plurals = {
    'day': 'days',
    'week': 'weeks',
    'month': 'months',
    'year': 'years',
  };
  final symbol = symbols[id];
  if (symbol != null) return symbol;
  final plural = plurals[id];
  if (plural != null && value != 1) return plural;
  return id;
}

/// Full numeric text for copy/detail; does not change stored [Value].
///
/// Uses the platform double's own `toString` for the mantissa so Copy Number
/// is not silently re-rounded to 12 significant digits or money's 2 dp.
String presentFullValue(
  Value value, {
  NumberFormat format = NumberFormat.us,
}) {
  switch (value) {
    case NumValue(:final value, :final unit):
      final n = _fullNumber(value, format);
      if (unit == null) return n;
      return '$n ${_unitSuffix(unit.id, value)}';
    case MoneyValue(:final value, :final currency):
      final sym = currencySymbols[currency] ?? '$currency ';
      final sign = value < 0 ? '-' : '';
      return '$sign$sym${_fullNumber(value.abs(), format)}';
    case PercentValue(:final ratio):
      return '${_fullNumber(ratio * 100, format)}%';
    case ListValue(:final items):
      return items.map((e) => presentFullValue(e, format: format)).join(', ');
    default:
      return formatValue(value, format: format);
  }
}

String _fullNumber(double v, NumberFormat format) {
  if (v.isNaN) return 'NaN';
  if (v.isInfinite) return v > 0 ? '∞' : '-∞';
  if (v == 0) return '0';
  // Preserve the double's own decimal/scientific form, then localize separators.
  final raw = v.toString();
  if (raw.contains('e') || raw.contains('E')) {
    return format.decimal == '.' ? raw : raw.replaceFirst('.', format.decimal);
  }
  final neg = raw.startsWith('-');
  final body = neg ? raw.substring(1) : raw;
  final parts = body.split('.');
  final intPart = parts[0];
  final frac = parts.length > 1 ? parts[1] : '';
  final buf = StringBuffer();
  for (var i = 0; i < intPart.length; i++) {
    if (i > 0 && (intPart.length - i) % 3 == 0) buf.write(format.group);
    buf.write(intPart[i]);
  }
  final out = frac.isEmpty
      ? buf.toString()
      : '${buf.toString()}${format.decimal}$frac';
  return neg ? '-$out' : out;
}

/// Multi-line detail for the answer menu / tooltip.
String presentDetails(
  Value value, {
  DisplayPrecision precision = DisplayPrecision.auto,
  NumberFormat format = NumberFormat.us,
}) {
  final shown = presentValue(value, precision: precision, format: format);
  final full = presentFullValue(value, format: format);
  if (shown == full) return full;
  return 'Displayed: $shown\nFull: $full';
}

LineResult presentLine(
  LineResult line,
  DisplayPrecision precision,
  NumberFormat format,
) {
  if (line.engineError || line.display == null || line.value == null) {
    return line;
  }
  return LineResult(
    text: line.text,
    value: line.value,
    display: presentValue(line.value!, precision: precision, format: format),
    error: line.error,
    engineError: line.engineError,
    isComment: line.isComment,
    isHeading: line.isHeading,
    tag: line.tag,
  );
}

List<LineResult> presentResults(
  List<LineResult> lines,
  DisplayPrecision precision,
  NumberFormat format,
) => lines.map((l) => presentLine(l, precision, format)).toList(growable: false);
