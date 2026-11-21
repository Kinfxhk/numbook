import 'dart:convert';
import 'dart:io';

import 'engine.dart';
import 'lexer.dart';
import 'values.dart';

/// Converts any engine [Value] into a deterministic JSON map for CLI `--json`
/// and MCP tool responses.
Map<String, Object?>? valueToJson(Value? v) {
  switch (v) {
    case NumValue(:final value, :final unit):
      return {'type': 'number', 'value': value, 'unit': unit?.id};
    case MoneyValue(:final value, :final currency):
      return {'type': 'money', 'value': value, 'currency': currency};
    case PercentValue(:final ratio):
      return {'type': 'percent', 'value': ratio};
    case DateValue(:final date):
      return {'type': 'date', 'value': date.toIso8601String()};
    case DurationValue(:final seconds):
      return {'type': 'duration', 'seconds': seconds};
    case BoolValue(:final value):
      return {'type': 'bool', 'value': value};
    case ListValue(:final items):
      return {'type': 'list', 'value': items.map(valueToJson).toList()};
    case _:
      return null;
  }
}

/// Deterministic, offline Model Context Protocol (MCP) server over JSON-RPC 2.0.
///
/// Implements `docs/agents.md` §2 inside the single pure-Dart `tallynote` binary
/// with zero network calls and zero external dependencies.
class McpServer {
  static const protocolVersion = '2024-11-05';
  final DateTime? fixedNow;

  const McpServer({this.fixedNow});

  /// Handles a single JSON-RPC 2.0 message map. Returns `null` for notifications
  /// (messages without an `id`, such as `notifications/initialized`).
  Map<String, Object?>? handleMessage(Map<String, Object?> msg) {
    final hasId = msg.containsKey('id');
    final id = msg['id'];
    final method = msg['method'];
    if (method is! String) {
      if (!hasId) return null;
      return _error(id, -32600, 'Invalid Request: missing method');
    }
    if (!hasId) {
      // JSON-RPC notification (`notifications/initialized`, `notifications/cancelled`)
      return null;
    }

    final params = (msg['params'] is Map)
        ? Map<String, Object?>.from(msg['params'] as Map)
        : const <String, Object?>{};

    switch (method) {
      case 'initialize':
        return _result(id, {
          'protocolVersion': protocolVersion,
          'capabilities': {
            'tools': {'listChanged': false},
          },
          'serverInfo': {
            'name': 'numbook-tallynote',
            'version': '0.5.3',
          },
        });
      case 'ping':
        return _result(id, const <String, Object?>{});
      case 'tools/list':
        return _result(id, {'tools': _toolDefinitions});
      case 'tools/call':
        return _callTool(id, params);
      default:
        return _error(id, -32601, 'Method not found: $method');
    }
  }

  Map<String, Object?> _callTool(Object? id, Map<String, Object?> params) {
    final name = params['name'];
    final args = (params['arguments'] is Map)
        ? Map<String, Object?>.from(params['arguments'] as Map)
        : const <String, Object?>{};

    if (name is! String) {
      return _error(id, -32602, 'Invalid params: missing tool name');
    }

    final preset = (args['format'] as String?)?.toLowerCase() == 'eu'
        ? 'eu'
        : 'us';
    final yen = (args['yen'] as String?)?.toUpperCase() == 'CNY'
        ? 'CNY'
        : 'JPY';
    final strict = args['strict'] is bool ? args['strict'] as bool : true;
    final dp = args['dp'] is int ? args['dp'] as int : null;
    final fmt = NumberFormat.ofPreset(preset, yen: yen);

    Map<String, double>? customRates;
    if (args['rates'] is Map) {
      customRates = <String, double>{'USD': 1.0};
      (args['rates'] as Map).forEach((k, v) {
        if (k is String && v is num) {
          customRates![k.toUpperCase()] = v.toDouble();
        }
      });
    }

    final engine = SheetEngine(
      strict: strict,
      format: fmt,
      now: fixedNow,
      rates: customRates,
    );

    switch (name) {
      case 'calc':
        final expr = args['expression'];
        if (expr is! String || expr.trim().isEmpty) {
          return _toolResult(
            {'error': 'expression is required'},
            isError: true,
          )..['id'] = id;
        }
        final clean = stripInlineMarkers(expr);
        final r = engine.evaluate([clean]).single;
        final display = r.value != null && !r.engineError && dp != null
            ? formatValue(r.value!, decimals: dp, format: fmt)
            : r.display;
        final payload = {
          'input': expr,
          'display': display,
          'value': valueToJson(r.value),
          'steps': display != null ? engine.explain(clean) : const <String>[],
          'error': r.error,
        };
        return _result(
          id,
          _toolBody(payload, isError: display == null && r.error != null),
        );

      case 'eval_sheet':
        final rawLines = args['lines'];
        final lines = switch (rawLines) {
          List l => l.map((e) => '$e').toList(),
          String s => s.split('\n'),
          _ => null,
        };
        if (lines == null) {
          return _error(id, -32602, 'eval_sheet requires `lines` (string or array)');
        }
        final includeTotal = args['total'] == true;
        final cleanLines = [
          ...lines.map(stripInlineMarkers),
          if (includeTotal) 'grand total',
        ];
        final results = engine.evaluate(cleanLines);
        final rows = <Map<String, Object?>>[];
        for (var i = 0; i < results.length; i++) {
          final r = results[i];
          final display = r.value != null && !r.engineError && dp != null
              ? formatValue(r.value!, decimals: dp, format: fmt)
              : r.display;
          rows.add({
            'line': i + 1,
            'input': i < lines.length ? lines[i] : 'grand total',
            'display': display,
            'value': valueToJson(r.value),
            'error': r.error,
          });
        }
        return _result(id, _toolBody({'lines': rows}));

      case 'convert':
        final amount = args['amount'];
        final to = args['to'];
        if (amount is! String || to is! String || to.trim().isEmpty) {
          return _error(id, -32602, 'convert requires `amount` and `to` strings');
        }
        final expr = '${stripInlineMarkers(amount).trim()} in ${to.trim()}';
        final r = engine.evaluate([expr]).single;
        final display = r.value != null && !r.engineError && dp != null
            ? formatValue(r.value!, decimals: dp, format: fmt)
            : r.display;
        final failed = display == null;
        return _result(
          id,
          _toolBody(
            {
              'expression': expr,
              'display': display,
              'value': valueToJson(r.value),
              'steps': failed ? const <String>[] : engine.explain(expr),
              'error': failed ? (r.error ?? 'unsupported conversion') : null,
            },
            isError: failed,
          ),
        );

      case 'explain':
        final expr = args['expression'];
        if (expr is! String || expr.trim().isEmpty) {
          return _error(id, -32602, 'explain requires `expression`');
        }
        final clean = stripInlineMarkers(expr);
        final r = engine.evaluate([clean]).single;
        return _result(
          id,
          _toolBody({
            'input': expr,
            'display': r.display,
            'steps': engine.explain(clean),
            'error': r.error,
          }, isError: r.display == null && r.error != null),
        );

      default:
        return _error(id, -32601, 'Unknown tool: $name');
    }
  }

  Map<String, Object?> _toolBody(
    Map<String, Object?> payload, {
    bool isError = false,
  }) => {
    'content': [
      {'type': 'text', 'text': jsonEncode(payload)},
    ],
    if (isError) 'isError': true,
  };

  Map<String, Object?> _toolResult(
    Map<String, Object?> payload, {
    bool isError = false,
  }) => {
    'jsonrpc': '2.0',
    'result': _toolBody(payload, isError: isError),
  };

  Map<String, Object?> _result(Object? id, Map<String, Object?> result) => {
    'jsonrpc': '2.0',
    'id': id,
    'result': result,
  };

  Map<String, Object?> _error(Object? id, int code, String message) => {
    'jsonrpc': '2.0',
    'id': id,
    'error': {'code': code, 'message': message},
  };

  /// Runs the newline-delimited JSON-RPC stdio loop until stdin closes.
  Future<void> serveStdio({Stdin? input, IOSink? output}) async {
    final stream = (input ?? stdin)
        .transform(utf8.decoder)
        .transform(const LineSplitter());
    final out = output ?? stdout;
    await for (final line in stream) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      try {
        final decoded = jsonDecode(trimmed);
        if (decoded is! Map) {
          out.writeln(jsonEncode(_error(null, -32600, 'Invalid Request')));
          continue;
        }
        final resp = handleMessage(Map<String, Object?>.from(decoded));
        if (resp != null) out.writeln(jsonEncode(resp));
      } on FormatException catch (e) {
        out.writeln(jsonEncode(_error(null, -32700, 'Parse error: ${e.message}')));
      }
    }
  }

  static const List<Map<String, Object?>> _toolDefinitions = [
    {
      'name': 'calc',
      'description':
          'Deterministically evaluate a single mathematical, financial, unit, date, percentage, or single-unknown (`?`) expression offline.',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'expression': {
            'type': 'string',
            'description': 'Expression to evaluate, e.g. "? * 30% = 1290" or "480 加一"',
          },
          'strict': {'type': 'boolean', 'default': true},
          'format': {
            'type': 'string',
            'enum': ['us', 'eu'],
            'default': 'us',
          },
          'yen': {
            'type': 'string',
            'enum': ['JPY', 'CNY'],
            'default': 'JPY',
          },
          'dp': {'type': 'integer', 'description': 'Optional fixed decimal places'},
        },
        'required': ['expression'],
      },
    },
    {
      'name': 'eval_sheet',
      'description':
          'Evaluate a multi-line calculation sheet top-to-bottom with variables, labels, tags (`#tag`), `subtotal`, and `grand total`.',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'lines': {
            'oneOf': [
              {'type': 'string'},
              {
                'type': 'array',
                'items': {'type': 'string'},
              },
            ],
          },
          'total': {'type': 'boolean', 'default': false},
          'strict': {'type': 'boolean', 'default': false},
          'format': {
            'type': 'string',
            'enum': ['us', 'eu'],
            'default': 'us',
          },
          'dp': {'type': 'integer'},
        },
        'required': ['lines'],
      },
    },
    {
      'name': 'convert',
      'description':
          'Convert a quantity with physical units, data sizes, temperatures, or ISO currencies offline.',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'amount': {'type': 'string', 'description': 'Source value, e.g. "5 kg" or "100 USD"'},
          'to': {'type': 'string', 'description': 'Target unit or currency, e.g. "lb" or "HKD"'},
          'dp': {'type': 'integer'},
        },
        'required': ['amount', 'to'],
      },
    },
    {
      'name': 'explain',
      'description':
          'Return the deterministic step-by-step breakdown for an expression.',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'expression': {'type': 'string'},
          'format': {
            'type': 'string',
            'enum': ['us', 'eu'],
            'default': 'us',
          },
        },
        'required': ['expression'],
      },
    },
  ];
}
