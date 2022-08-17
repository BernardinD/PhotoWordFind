import 'dart:async';

import 'package:PhotoWordFind/main.dart';
import 'package:PhotoWordFind/utils/MyProgressDialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';


MyProgressDialog pr;
final GlobalKey<NavigatorState> navigatorKey = new GlobalKey<NavigatorState>();

MaterialApp _buildAppWithDialog({ ThemeData theme, double textScaleFactor = 1.0 }) {
  return MaterialApp(
    theme: theme,
    navigatorKey: navigatorKey,
    home: Material(
      child: Builder(
        builder: (BuildContext context) {
          pr = MyProgressDialog(context, navigatorKey);
          return Center(
            child: Column(
              children: [
                ElevatedButton(
                  child: const Text('Start'),
                  onPressed: pr.show,
                ),
                ElevatedButton(
                  child: const Text('Stop'),
                  onPressed: pr.show,
                ),
              ],
            ),
          );
        },
      ),
    ),
  );
}

void main(){
  setUp((){

  });

  _stopTimer() async{
    await pr.hide();
  }

  testWidgets("Test General Process completion", (tester) async{
    await tester.pumpWidget(_buildAppWithDialog());
    var processWait = find.text('Keep waiting...');
    var testStart = find.text('Start');

    expect(pr.isShowing(), false);

    await tester.tap(testStart);
    await tester.pumpAndSettle();

    expect(pr.isShowing(), true);

    await tester.pump(Duration(seconds: 7));
    expect(processWait, findsNothing);

    pr.hide();

    await tester.pump();
    expect(pr.isShowing(), false);
  });

  testWidgets("Test Wait on process", (tester) async {
    await tester.pumpWidget(_buildAppWithDialog());
    var processWait = find.text('Keep waiting...');
    var testStart = find.text('Start');

    expect(pr.isShowing(), false);

    await tester.tap(testStart);
    await tester.pumpAndSettle();

    expect(pr.isShowing(), true);

    await tester.pump(Duration(seconds: 8));
    expect(processWait, findsOneWidget);

    await tester.tap(processWait);
    await tester.pump();

    expect(pr.isShowing(), true);
    expect(processWait, findsNothing);

    pr.hide();
    await tester.pump();
    expect(pr.isShowing(), false);
    expect(processWait, findsNothing);
  });

  testWidgets("Test Stop process", (tester) async {
    await tester.pumpWidget(_buildAppWithDialog());

    expect(pr.isShowing(), false);


    expect(pr.isShowing(), true);

    await tester.pump(Duration(seconds: 8));

    await tester.tap(find.text('Stop...'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isInstanceOf<TimeoutException>());

    await _stopTimer();
  });

  testWidgets("Test process finishes soon after message appears", (tester) async {
    await tester.pumpWidget(_buildAppWithDialog());
    var processWait = find.text('Keep waiting...');
    var testStart = find.text('Start');

    expect(pr.isShowing(), false);

    await tester.tap(testStart);
    await tester.pumpAndSettle();

    expect(pr.isShowing(), true);

    await tester.pump(Duration(milliseconds: 8100));
    expect(processWait, findsOneWidget);

    pr.hide();
    await tester.pump();

    expect(pr.isShowing(), false);
    expect(processWait, findsNothing);


  });
}