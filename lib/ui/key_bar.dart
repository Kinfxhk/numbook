import 'package:flutter/material.dart';

import 'marked_controller.dart';
import 'feedback.dart';
import 'theme.dart';

/// The phone's IME (Cangjie quick, a Chinese keyboard) cannot type `+ − × ÷`
/// or a currency code: it composes `rent = 2500` into `Rrente00`. These chips
/// write straight into the editor's controller, so an expression can be typed
/// on any IME. Shown only while a soft keyboard is up (see `main.dart`), so a
/// desktop never sees it.
class KeyBar extends StatefulWidget {
  final MarkedController controller;
  final bool dark;

  const KeyBar({super.key, required this.controller, required this.dark});

  @override
  State<KeyBar> createState() => _KeyBarState();
}

const _symbols = [
  '+',
  '−',
  '×',
  '÷',
  '(',
  ')',
  '=',
  '%',
  '.',
  ',',
  '#',
  '⌫',
  '↵',
];

const _wordKeys = [
  // `to` / `兌` make a conversion typeable without the IME ever leaving
  // Chinese: a Chinese keyboard composes latin into hanzi before it lands.
  'to',
  '兌',
  'usd',
  'hkd',
  'cny',
  'jpy',
  'total',
  'sum',
  'count',
  'prev',
  'line',
  '打八折',
  '分帳',
];

class _KeyBarState extends State<KeyBar> {
  bool _wordPage = false;

  void _press(String key) {
    if (key == '⌫') {
      widget.controller.deleteBack();
      return;
    }
    // a word chip ends in a space: `5000` `usd` `to` `hkd` must read
    // "5000usd to hkd", or the engine sees one word called usdtohkd
    final word = _wordPage && key.length > 1;
    widget.controller.insertAtCaret(
      key == '↵' ? '\n' : (word ? '$key ' : key),
    );
  }

  @override
  Widget build(BuildContext context) {
    final keys = _wordPage ? _wordKeys : _symbols;
    return TextFieldTapRegion(
      // a tap here is a tap on the field: the keyboard must stay up
      child: SizedBox(
        height: 44,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Palette.bg(widget.dark),
            border: Border(
              top: BorderSide(color: Palette.hairline(widget.dark)),
            ),
          ),
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 2),
            children: [
              _chip(_wordPage ? '123' : 'A', () {
                setState(() => _wordPage = !_wordPage);
              }),
              for (final key in keys) ...[_divider(), _chip(key, () {
                _press(key);
              })],
            ],
          ),
        ),
      ),
    );
  }

  Widget _chip(String label, VoidCallback onTap) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: () {
      tapFeedback();
      onTap();
    },
    child: Container(
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 11),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: monoFamily,
          fontSize: 14.5,
          color: Palette.faint(widget.dark),
        ),
      ),
    ),
  );

  Widget _divider() => Center(
    child: Container(width: 1, height: 16, color: Palette.hairline(widget.dark)),
  );
}
