import 'dart:convert';
import 'dart:io';

import 'package:tallynote/engine/engine.dart';
import 'package:tallynote/engine/lexer.dart';
import 'package:tallynote/engine/mcp_server.dart';
import 'package:tallynote/engine/values.dart';

const _version = '0.5.3';

const _usage = '''
Tallynote (Numbook CLI) — the notepad that adds up, from the command line.

Usage:
  tallynote <expression>              evaluate one line
  tallynote -f <file>                 evaluate a note, one line at a time
  echo "2+2" | tallynote              read from stdin
  tallynote mcp                       run offline JSON-RPC MCP server over stdio

Options:
  -e, --eval <text>    expression to evaluate
  -f, --file <path>    note file (- for stdin)
  -j, --json           structured output, one JSON object per line
  -s, --steps          include the step breakdown
      --total          print the grand total of all lines
      --dp <n>         decimal places for numbers
      --format <p>     number preset: us (1,234.56) or eu (1.234,56)
      --yen <code>     currency for ¥: JPY or CNY
      --strict         exit 1 if any line fails
  -h, --help           this text
      --version        version

Examples:
  tallynote "5 kg + 3 lb"
  tallynote "? * 30% = 1290" --steps
  tallynote -f budget.txt --json --total
  tallynote mcp
''';

Future<void> main(List<String> argv) async {
  final args = List<String>.from(argv);
  if (args.isNotEmpty && args.first == 'mcp') {
    await const McpServer().serveStdio();
    return;
  }

  String? file;
  String? eval;
  var json = false;
  var steps = false;
  var total = false;
  var strict = false;
  var preset = 'us';
  var yen = 'JPY';
  int? dp;

  final positional = <String>[];

  for (var i = 0; i < args.length; i++) {
    final a = args[i];
    switch (a) {
      case '-h' || '--help':
        stdout.writeln(_usage);
        return;
      case '--version':
        stdout.writeln('tallynote $_version');
        return;
      case '-j' || '--json':
        json = true;
      case '-s' || '--steps':
        steps = true;
      case '--total':
        total = true;
      case '--strict':
        strict = true;
      case '-e' || '--eval':
        if (i + 1 >= args.length) _die('missing value for $a');
        eval = args[++i];
      case '-f' || '--file':
        if (i + 1 >= args.length) _die('missing value for $a');
        file = args[++i];
      case '--dp':
        if (i + 1 >= args.length) _die('missing value for --dp');
        dp = int.tryParse(args[++i]);
        if (dp == null || dp < 0 || dp > 15) _die('--dp needs 0..15');
      case '--format':
        if (i + 1 >= args.length) _die('missing value for --format');
        final v = args[++i].toLowerCase();
        if (v != 'us' && v != 'eu') _die('--format expects us or eu');
        preset = v;
      case '--yen':
        if (i + 1 >= args.length) _die('missing value for --yen');
        final v = args[++i].toUpperCase();
        if (v != 'JPY' && v != 'CNY') _die('--yen expects JPY or CNY');
        yen = v;
      default:
        if (a.startsWith('-') && a != '-') _die('unknown option $a');
        positional.add(a);
    }
  }

  final fmt = NumberFormat.ofPreset(preset, yen: yen);
  final engine = SheetEngine(strict: strict, format: fmt);

  List<String> rawLines;
  if (file != null) {
    if (file == '-') {
      final text = _readAll();
      rawLines = text.isEmpty ? <String>[] : text.trimRight().split('\n');
    } else {
      rawLines = File(file).readAsLinesSync();
    }
  } else if (eval != null) {
    rawLines = [eval];
  } else if (positional.isNotEmpty) {
    rawLines = [positional.join(' ')];
  } else if (!stdin.hasTerminal) {
    final text = _readAll();
    rawLines = text.isEmpty ? <String>[] : text.trimRight().split('\n');
  } else {
    stdout.writeln(_usage);
    exit(64);
  }

  if (total) rawLines.add('grand total');

  final cleanLines = rawLines.map(stripInlineMarkers).toList();
  final results = engine.evaluate(cleanLines);
  var failed = 0;
  final out = StringBuffer();

  for (var i = 0; i < results.length; i++) {
    final r = results[i];
    final inputText = rawLines[i];
    if (r.error != null) failed++;
    final display = (r.value != null && !r.engineError && dp != null)
        ? formatValue(r.value!, decimals: dp, format: fmt)
        : r.display;

    if (json) {
      out.writeln(
        jsonEncode({
          'line': i + 1,
          'input': inputText,
          'display': display,
          'error': r.error,
          'value': valueToJson(r.value),
          if (steps && display != null && r.error == null)
            'steps': engine.explain(cleanLines[i]),
        }),
      );
    } else {
      final answer = display ?? '';
      out.writeln(answer.isEmpty ? inputText : '$inputText\t$answer');
      if (steps && display != null && r.error == null) {
        for (final s in engine.explain(cleanLines[i])) {
          out.writeln('    $s');
        }
      }
    }
  }

  stdout.write(out.toString());
  if (strict && failed > 0) exit(1);
}

String _readAll() {
  final buf = StringBuffer();
  while (true) {
    final line = stdin.readLineSync(encoding: utf8);
    if (line == null) break;
    buf.writeln(line);
  }
  return buf.toString();
}

Never _die(String message) {
  stderr.writeln('tallynote: $message');
  stderr.writeln('try --help');
  exit(64);
}
