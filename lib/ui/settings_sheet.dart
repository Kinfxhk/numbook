import 'package:flutter/material.dart';

import '../data/rates.dart';
import '../i18n/strings.dart';
import 'cheat_sheet.dart';
import 'feedback.dart';
import 'formatting.dart';
import 'theme.dart';

/// All settings, grouped into tabs. The main screen keeps two buttons, so
/// everything that is a preference rather than an action ends up here.
Future<void> showSettingsSheet({
  required BuildContext context,
  required bool dark,
  required String themeMode,
  required bool answersVisible,
  required bool autoRates,
  required bool steps,
  required bool keyBar,
  required bool haptics,
  required bool signColours,
  required String posName,
  required String negName,
  required bool lineNumbers,
  required bool showTabs,
  required double uiScale,
  required String locale,
  required String numberPreset,
  required String displayPrecision,
  required String paperStyle,
  required bool highlightCurrentLine,
  required ValueChanged<String> onLocale,
  required ValueChanged<String> onNumberPreset,
  required ValueChanged<String> onDisplayPrecision,
  required ValueChanged<String> onPaperStyle,
  required ValueChanged<bool> onHighlightCurrentLine,
  required ValueChanged<bool> onAnswers,
  required ValueChanged<String> onThemeMode,
  required ValueChanged<bool> onHaptics,
  required ValueChanged<bool> onAutoRates,
  required ValueChanged<bool> onSteps,
  required ValueChanged<bool> onKeyBar,
  required ValueChanged<bool> onSignColours,
  required ValueChanged<String> onPosColour,
  required ValueChanged<String> onNegColour,
  required ValueChanged<bool> onLineNumbers,
  required ValueChanged<bool> onShowTabs,
  required ValueChanged<double> onUiScale,
  required Future<bool> Function() onRefreshRates,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _SettingsDialog(
      dark: dark,
      themeMode: themeMode,
      answersVisible: answersVisible,
      autoRates: autoRates,
      steps: steps,
      keyBar: keyBar,
      haptics: haptics,
      signColours: signColours,
      posName: posName,
      negName: negName,
      lineNumbers: lineNumbers,
      showTabs: showTabs,
      uiScale: uiScale,
      locale: locale,
      numberPreset: numberPreset,
      displayPrecision: displayPrecision,
      paperStyle: paperStyle,
      highlightCurrentLine: highlightCurrentLine,
      onNumberPreset: onNumberPreset,
      onDisplayPrecision: onDisplayPrecision,
      onPaperStyle: onPaperStyle,
      onHighlightCurrentLine: onHighlightCurrentLine,
      onLocale: onLocale,
      onAnswers: onAnswers,
      onThemeMode: onThemeMode,
      onHaptics: onHaptics,
      onAutoRates: onAutoRates,
      onSteps: onSteps,
      onKeyBar: onKeyBar,
      onSignColours: onSignColours,
      onPosColour: onPosColour,
      onNegColour: onNegColour,
      onLineNumbers: onLineNumbers,
      onShowTabs: onShowTabs,
      onUiScale: onUiScale,
      onRefreshRates: onRefreshRates,
    ),
  );
}

class _SettingsDialog extends StatefulWidget {
  final bool dark;
  final String themeMode;
  final bool answersVisible;
  final bool autoRates;
  final bool steps;
  final bool keyBar;
  final bool haptics;
  final bool signColours;
  final String posName;
  final String negName;
  final bool lineNumbers;
  final bool showTabs;
  final double uiScale;
  final String locale;
  final String numberPreset;
  final String displayPrecision;
  final String paperStyle;
  final bool highlightCurrentLine;
  final ValueChanged<String> onLocale;
  final ValueChanged<String> onNumberPreset;
  final ValueChanged<String> onDisplayPrecision;
  final ValueChanged<String> onPaperStyle;
  final ValueChanged<bool> onHighlightCurrentLine;
  final ValueChanged<bool> onAnswers;
  final ValueChanged<String> onThemeMode;
  final ValueChanged<bool> onHaptics;
  final ValueChanged<bool> onAutoRates;
  final ValueChanged<bool> onSteps;
  final ValueChanged<bool> onKeyBar;
  final ValueChanged<bool> onSignColours;
  final ValueChanged<String> onPosColour;
  final ValueChanged<String> onNegColour;
  final ValueChanged<bool> onLineNumbers;
  final ValueChanged<bool> onShowTabs;
  final ValueChanged<double> onUiScale;
  final Future<bool> Function() onRefreshRates;

  const _SettingsDialog({
    required this.dark,
    required this.themeMode,
    required this.answersVisible,
    required this.autoRates,
    required this.steps,
    required this.keyBar,
    required this.haptics,
    required this.signColours,
    required this.posName,
    required this.negName,
    required this.lineNumbers,
    required this.showTabs,
    required this.uiScale,
    required this.locale,
    required this.numberPreset,
    required this.displayPrecision,
    required this.paperStyle,
    required this.highlightCurrentLine,
    required this.onLocale,
    required this.onNumberPreset,
    required this.onDisplayPrecision,
    required this.onPaperStyle,
    required this.onHighlightCurrentLine,
    required this.onAnswers,
    required this.onThemeMode,
    required this.onHaptics,
    required this.onAutoRates,
    required this.onSteps,
    required this.onKeyBar,
    required this.onSignColours,
    required this.onPosColour,
    required this.onNegColour,
    required this.onLineNumbers,
    required this.onShowTabs,
    required this.onUiScale,
    required this.onRefreshRates,
  });

  @override
  State<_SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<_SettingsDialog> {
  late bool dark = widget.dark;
  late String themeMode = widget.themeMode;
  late bool answers = widget.answersVisible;
  late bool autoRates = widget.autoRates;
  late bool steps = widget.steps;
  late bool keyBar = widget.keyBar;
  late bool haptics = widget.haptics;
  late bool signColours = widget.signColours;
  late String pos = widget.posName;
  late String neg = widget.negName;
  late bool lineNumbers = widget.lineNumbers;
  late bool showTabs = widget.showTabs;
  late double scale = widget.uiScale;
  late String locale = widget.locale;
  late String preset = widget.numberPreset;
  late String precision = widget.displayPrecision;
  late String paper = widget.paperStyle;
  late bool highlightLine = widget.highlightCurrentLine;
  String? rateError;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Palette.bg(dark),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 560),
        child: DefaultTabController(
          length: 4,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TabBar(
                labelColor: Palette.answer(dark),
                unselectedLabelColor: Palette.faint(dark),
                indicatorColor: Palette.answer(dark),
                labelStyle: const TextStyle(fontSize: 12.5),
                tabs: [
                  Tab(text: T.of(locale, 'appearance')),
                  Tab(text: T.of(locale, 'editor')),
                  Tab(text: T.of(locale, 'data')),
                  Tab(text: T.of(locale, 'cheatSheet')),
                ],
              ),
              Flexible(
                child: TabBarView(
                  children: [
                    _appearance(),
                    _editor(),
                    _data(),
                    CheatSheetView(dark: dark, locale: locale),
                  ],
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(0, 4, 12, 8),
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(
                      T.of(locale, 'done'),
                      style: TextStyle(color: Palette.answer(dark)),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---- tabs ----------------------------------------------------------------

  Widget _appearance() => ListView(
    padding: const EdgeInsets.symmetric(vertical: 8),
    children: [
      _languageRow(),
      _row(
        T.of(locale, 'theme'),
        T.of(locale, 'themeHint'),
        _threeWay(
          const ['system', 'light', 'dark'],
          themeMode,
          (v) {
            setState(() {
              themeMode = v;
              // the dialog's own colours follow, previewing the choice
              dark = v == 'dark' ||
                  (v == 'system' &&
                      MediaQuery.platformBrightnessOf(context) ==
                          Brightness.dark);
            });
            widget.onThemeMode(v);
          },
          id: 'theme',
        ),
      ),
      _row(
        T.of(locale, 'answers'),
        T.of(locale, 'answersHint'),
        _switch(answers, (v) {
          setState(() => answers = v);
          widget.onAnswers(v);
        }, 'answers'),
      ),
      _row(
        T.of(locale, 'signColours'),
        T.of(locale, 'signColoursHint'),
        _switch(signColours, (v) {
          setState(() => signColours = v);
          widget.onSignColours(v);
        }, 'sign'),
      ),
      if (signColours) ...[
        _colourRow(T.of(locale, 'positive'), pos, (name) {
          setState(() => pos = name);
          widget.onPosColour(name);
        }),
        _colourRow(T.of(locale, 'negative'), neg, (name) {
          setState(() => neg = name);
          widget.onNegColour(name);
        }),
      ],
      _row(
        T.of(locale, 'paperStyle'),
        T.of(locale, 'paperStyleHint'),
        _paperStylePicker(),
      ),
      _row(
        T.of(locale, 'highlightCurrentLine'),
        T.of(locale, 'highlightCurrentLineHint'),
        _switch(highlightLine, (v) {
          setState(() => highlightLine = v);
          widget.onHighlightCurrentLine(v);
        }, 'switch-current-line'),
      ),
    ],
  );

  Widget _editor() => ListView(
    padding: const EdgeInsets.symmetric(vertical: 8),
    children: [
      _row(
        T.of(locale, 'textSize'),
        T.of(locale, 'textSizeHint'),
        _scaleButtons(),
      ),
      _row(
        T.of(locale, 'displayPrecision'),
        T.of(locale, 'displayPrecisionHint'),
        Wrap(
          spacing: 2,
          children: [
            for (final entry in const [
              ('auto', 'Auto'),
              ('2', '2'),
              ('4', '4'),
              ('8', '8'),
              ('full', 'Full'),
            ])
              TextButton(
                onPressed: () {
                  setState(() => precision = entry.$1);
                  widget.onDisplayPrecision(entry.$1);
                },
                style: TextButton.styleFrom(
                  minimumSize: const Size(36, 28),
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  foregroundColor: precision == entry.$1
                      ? Palette.answer(dark)
                      : Palette.faint(dark),
                ),
                child: Text(
                  entry.$2,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: precision == entry.$1
                        ? FontWeight.w700
                        : FontWeight.w400,
                  ),
                ),
              ),
          ],
        ),
      ),
      _row(
        'Number format',
        'US 1,234.56 · EU 1.234,56',
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final p in const ['us', 'eu'])
              TextButton(
                onPressed: () {
                  setState(() => preset = p);
                  widget.onNumberPreset(p);
                },
                style: TextButton.styleFrom(
                  minimumSize: const Size(40, 28),
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  foregroundColor: preset == p
                      ? Palette.answer(dark)
                      : Palette.faint(dark),
                ),
                child: Text(
                  p.toUpperCase(),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: preset == p ? FontWeight.w700 : FontWeight.w400,
                  ),
                ),
              ),
          ],
        ),
      ),
      _row(
        T.of(locale, 'lineNumbers'),
        T.of(locale, 'lineNumbersHint'),
        _switch(lineNumbers, (v) {
          setState(() => lineNumbers = v);
          widget.onLineNumbers(v);
        }),
      ),
      _row(
        T.of(locale, 'tabBar'),
        T.of(locale, 'tabBarHint'),
        _switch(showTabs, (v) {
          setState(() => showTabs = v);
          widget.onShowTabs(v);
        }),
      ),
      _row(
        T.of(locale, 'stepChevrons'),
        T.of(locale, 'stepChevronsHint'),
        _switch(steps, (v) {
          setState(() => steps = v);
          widget.onSteps(v);
        }),
      ),
      _row(
        T.of(locale, 'keyBar'),
        T.of(locale, 'keyBarHint'),
        _switch(keyBar, (v) {
          setState(() => keyBar = v);
          widget.onKeyBar(v);
        }, 'keyBar'),
      ),
      _row(
        T.of(locale, 'haptics'),
        T.of(locale, 'hapticsHint'),
        _switch(haptics, (v) {
          setState(() => haptics = v);
          widget.onHaptics(v);
        }, 'haptics'),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
        child: Text(
          T.of(locale, 'shortcuts'),
          style: TextStyle(
            fontSize: 11,
            height: 1.5,
            color: Palette.faint(dark),
          ),
        ),
      ),
    ],
  );

  Widget _data() => ListView(
    padding: const EdgeInsets.symmetric(vertical: 8),
    children: [
      _row(
        T.of(locale, 'autoRates'),
        T.of(locale, 'autoRatesHint'),
        _switch(autoRates, (v) {
          setState(() => autoRates = v);
          widget.onAutoRates(v);
        }),
      ),
      _row(
        T.of(locale, 'exchangeRates'),
        rateError ??
            (Rates.updatedDate == null
                ? T.of(locale, 'ratesTable')
                : T.format(locale, 'ratesUpdated', {
                    'date': '${Rates.updatedDate}',
                  })),
        TextButton(
          onPressed: () async {
            final ok = await widget.onRefreshRates();
            if (!mounted) return;
            setState(() => rateError = ok ? null : T.of(locale, 'offline'));
          },
          child: Text(
            T.of(locale, 'refresh'),
            style: TextStyle(fontSize: 13, color: Palette.answer(dark)),
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
        child: Text(
          T.of(locale, 'displayPrecisionHint'),
          style: TextStyle(
            fontSize: 11,
            height: 1.5,
            color: Palette.faint(dark),
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
        child: Text(
          T.of(locale, 'privacy'),
          style: TextStyle(
            fontSize: 11,
            height: 1.5,
            color: Palette.faint(dark),
          ),
        ),
      ),
    ],
  );

  // ---- rows ----------------------------------------------------------------

  Widget _languageRow() => _row(
    T.of(locale, 'language'),
    T.of(locale, 'languageHint'),
    Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final entry in T.supported.entries)
          TextButton(
            onPressed: () {
              setState(() => locale = entry.key);
              widget.onLocale(entry.key);
            },
            style: TextButton.styleFrom(
              minimumSize: const Size(34, 28),
              padding: const EdgeInsets.symmetric(horizontal: 6),
              foregroundColor: locale == entry.key
                  ? Palette.answer(dark)
                  : Palette.faint(dark),
            ),
            child: Text(
              T.switchLabel[entry.key] ?? entry.key,
              style: TextStyle(
                fontSize: 11,
                fontWeight: locale == entry.key
                    ? FontWeight.w700
                    : FontWeight.w400,
              ),
            ),
          ),
      ],
    ),
  );

  Widget _paperStylePicker() {
    Widget preview(String key, String label) {
      final selected = paper == key;
      return Semantics(
        button: true,
        selected: selected,
        label: label,
        child: InkWell(
          key: ValueKey('paper-$key'),
          onTap: () {
            setState(() => paper = key);
            widget.onPaperStyle(key);
          },
          borderRadius: BorderRadius.circular(6),
          child: Container(
            width: 52,
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            decoration: BoxDecoration(
              border: Border.all(
                color: selected
                    ? Palette.answer(dark)
                    : Palette.hairline(dark),
                width: selected ? 1.5 : 1,
              ),
              borderRadius: BorderRadius.circular(6),
              color: Palette.bg(dark),
            ),
            child: CustomPaint(
              painter: _PaperPreviewPainter(
                dark: dark,
                style: key,
              ),
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 8.5,
                    color: selected
                        ? Palette.answer(dark)
                        : Palette.faint(dark),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        preview('plain', T.of(locale, 'paperPlain')),
        preview('single', T.of(locale, 'paperSingle')),
        preview('double', T.of(locale, 'paperDouble')),
      ],
    );
  }

  /// A settings row. A phone cannot hold a five-button control beside its
  /// label, so under 380dp the control goes underneath instead of overflowing.
  Widget _row(String label, String hint, Widget trailing) {
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 13.5, color: Palette.fg(dark))),
        const SizedBox(height: 2),
        Text(hint, style: TextStyle(fontSize: 11, color: Palette.faint(dark))),
      ],
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: LayoutBuilder(
        builder: (context, box) => box.maxWidth < 380
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [text, const SizedBox(height: 8), trailing],
              )
            : Row(children: [Expanded(child: text), trailing]),
      ),
    );
  }

  Widget _colourRow(String label, String current, ValueChanged<String> pick) =>
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 2, 20, 2),
        child: Row(
          children: [
            SizedBox(
              width: 96,
              child: Text(
                label,
                style: TextStyle(fontSize: 13, color: Palette.fg(dark)),
              ),
            ),
            for (final entry in Fmt.colours.entries)
              Pressable(
                onTap: () => pick(entry.key),
                padding: const EdgeInsets.all(6),
                child: Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: entry.value,
                    shape: BoxShape.circle,
                    border: entry.key == current
                        ? Border.all(color: Palette.fg(dark), width: 2)
                        : null,
                  ),
                ),
              ),
          ],
        ),
      );

  /// A row of short choices, like the language one: the theme has three.
  Widget _threeWay(
    List<String> values,
    String current,
    ValueChanged<String> pick, {
    required String id,
  }) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (final v in values)
        TextButton(
          key: ValueKey('$id-$v'),
          onPressed: () => pick(v),
          style: TextButton.styleFrom(
            minimumSize: const Size(30, 28),
            padding: const EdgeInsets.symmetric(horizontal: 5),
            foregroundColor: current == v
                ? Palette.answer(dark)
                : Palette.faint(dark),
          ),
          child: Text(
            switch (v) {
              'system' => T.of(locale, 'followSystem'),
              'light' => T.of(locale, 'light'),
              _ => T.of(locale, 'dark'),
            },
            maxLines: 1,
            style: TextStyle(
              fontSize: 11,
              fontWeight: current == v ? FontWeight.w700 : FontWeight.w400,
            ),
          ),
        ),
    ],
  );

  Widget _switch(bool value, ValueChanged<bool> onChanged, [String? id]) =>
      Switch(
        key: id == null ? null : ValueKey('switch-$id'),
        value: value,
        onChanged: onChanged,
        activeThumbColor: Palette.answer(dark),
      );

  Widget _scaleButtons() {
    const presets = [1.0, 1.25, 1.5, 1.75, 2.0];
    // a Wrap, so a narrow dialog flows five presets onto a second line
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final p in presets)
          Pressable(
            onTap: () {
              setState(() => scale = p);
              widget.onUiScale(p);
            },
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(3),
                border: Border.all(
                  color: (scale - p).abs() < 0.01
                      ? Palette.answer(dark)
                      : Palette.hairline(dark),
                ),
              ),
              child: Text(
                '${(p * 100).round()}%',
                style: TextStyle(
                  fontSize: 10.5,
                  color: (scale - p).abs() < 0.01
                      ? Palette.answer(dark)
                      : Palette.faint(dark),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _PaperPreviewPainter extends CustomPainter {
  const _PaperPreviewPainter({required this.dark, required this.style});

  final bool dark;
  final String style;

  @override
  void paint(Canvas canvas, Size size) {
    if (style == 'plain') return;
    final paint = Paint()
      ..color = Palette.hairline(dark)
      ..strokeWidth = 1;
    const rows = 3;
    final step = size.height / (rows + 1);
    for (var i = 1; i <= rows; i++) {
      final y = step * i;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
      if (style == 'double') {
        canvas.drawLine(Offset(0, y - 3), Offset(size.width, y - 3), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _PaperPreviewPainter oldDelegate) {
    return dark != oldDelegate.dark || style != oldDelegate.style;
  }
}
