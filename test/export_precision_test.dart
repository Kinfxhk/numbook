import 'package:flutter_test/flutter_test.dart';
import 'package:tallynote/data/document.dart';
import 'package:tallynote/engine/engine.dart';
import 'package:tallynote/engine/presentation.dart';
import 'package:tallynote/io/document_io.dart';
void main(){test('all app export rows share selected display precision',(){
 final sheet=Sheet(id:'pdf',title:'precision',content:'1/3');
 final rows=DocumentIo.exportResults(sheet,SheetEngine(),precision:DisplayPrecision.d8);
 expect(rows.single.display,'0.33333333');
 expect(DocumentIo.csv([sheet],SheetEngine(),precision:DisplayPrecision.d8),contains('0.33333333'));
});}
