import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tallynote/main.dart';
import 'package:tallynote/ui/editor_pane.dart';
import 'package:tallynote/ui/sidebar.dart';
import 'package:tallynote/engine/presentation.dart';

void main(){
 Future<void> boot(WidgetTester t,Map<String,Object> prefs)async{
 SharedPreferences.setMockInitialValues({'tallynote.autoRates':false,...prefs});t.view.physicalSize=const Size(1440,900);t.view.devicePixelRatio=1;addTearDown(t.view.reset);await t.pumpWidget(const TallynoteApp());await t.pumpAndSettle();
 }
 testWidgets('new split pane adopts selected precision',(t)async{
  await boot(t,{'tallynote.displayPrecision':'8'});
  await t.tap(find.byIcon(Icons.vertical_split));await t.pumpAndSettle();
  expect(find.byType(EditorPane),findsNWidgets(2));
  for(final e in find.byType(EditorPane).evaluate()){expect((e.widget as EditorPane).pane.displayPrecision,DisplayPrecision.d8);}
 });
 testWidgets('restored sidebar clamps to resized viewport',(t)async{
  await boot(t,{'tallynote.sidebarWidth':640.0});
  t.view.physicalSize=const Size(740,900);await t.pumpAndSettle();
  expect(t.getSize(find.byType(Sidebar)).width,lessThanOrEqualTo(333));expect(t.takeException(),isNull);
 });
 testWidgets('answer width callback saves resized pane not another focused pane',(t)async{
  await boot(t,{'tallynote.split':true,'tallynote.splitSheet':'b','tallynote.splitPrimary':'a','tallynote.active.v1':'a','tallynote.sheets.v1':jsonEncode({'v':2,'folders':[],'sheets':[for(final id in ['a','b']){'id':id,'title':id,'content':'1/3','customTitle':true,'pinned':false,'updated':'2026-11-05T00:00:00.000'}]})});
  final b=t.widget<EditorPane>(find.byType(EditorPane).at(1));b.pane.setAnswerWidth(350);b.onAnswerWidth(350);await t.pumpAndSettle();
  final prefs=await SharedPreferences.getInstance();expect(prefs.getDouble('tallynote.answerWidth'),350);
 });
}
