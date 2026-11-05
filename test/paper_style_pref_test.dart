import 'package:flutter_test/flutter_test.dart';
import 'package:tallynote/ui/editor_paper.dart';

void main() {
  test('paperStyleFrom defaults plain and rejects unknown keys', () {
    expect(paperStyleFrom(null), PaperStyle.plain);
    expect(paperStyleFrom(''), PaperStyle.plain);
    expect(paperStyleFrom('bogus'), PaperStyle.plain);
    expect(paperStyleFrom('plain'), PaperStyle.plain);
    expect(paperStyleFrom('single'), PaperStyle.single);
    expect(paperStyleFrom('double'), PaperStyle.double);
  });

  test('paperStyleKey round-trips storage keys', () {
    for (final style in PaperStyle.values) {
      expect(paperStyleFrom(paperStyleKey(style)), style);
    }
  });
}
