import 'package:PhotoWordFind/main.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
// import 'package:test/test.dart';

// @GenerateMocks([FilePicker])

class MockFilePicker extends Mock implements FilePicker {}

void main(){
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    mockFilePicker();
  });

  testWidgets("Test Move button disabled", (tester) async{
    await tester.pumpWidget(MyApp(title: 'Flutter Test Home Page'));
    // await tester.pumpAndSettle();

    var move = find.byKey(ValueKey("Move"));
    expect(move, findsOneWidget);

    expect(tester.widget<ElevatedButton>(move).enabled, false);
    await tester.tap(move);
    await tester.pump();

    expect(tester.widget<ElevatedButton>(move).enabled, false);

  });

  testWidgets("Test Move button enabled", (tester) async{
    await tester.pumpWidget(MyApp(title: 'Flutter Test Home Page'));
    // await tester.pumpAndSettle(Duration(seconds: 60));
    // await tester.pumpAndSettle();
    // await tester.pump(Duration(minutes: 100));

    var move = find.byKey(ValueKey("Move"));
    expect(move, findsOneWidget);
    expect(tester.widget<ElevatedButton>(move).enabled, false);


    expect(MyApp.gallery, isNotNull);

    MyApp.gallery.selected.add("Test");

    await tester.tap(move);
    await tester.pump();

    tester.state(find.byType(MyHomePage)).setState(() {});
    await tester.pump();
    await tester.pump();


    expect(move, findsOneWidget);
    var display = find.byKey(ValueKey("Display"));
    expect(display, findsOneWidget);
    expect(MyApp.gallery.selected.isNotEmpty, true);
    expect(tester.widget<ElevatedButton>(display).enabled, true);
    expect(tester.widget<ElevatedButton>(move).enabled, true);

  });


  testWidgets("Test Move button invalid path", (tester) async{
    await tester.pumpWidget(MyApp(title: 'Flutter Test Home Page'));

    var move =
    find.byKey(ValueKey("Move"));
    // find.widgetWithText(ElevatedButton, "Move");
    expect(move, findsOneWidget);
    expect(tester.widget<ElevatedButton>(move).enabled, false);


    expect(MyApp.gallery, isNotNull);

    MyApp.gallery.selected.add("Test");

    const channel = MethodChannel('miguelruivo.flutter.plugins.filepicker');
    handler(MethodCall methodCall) async {
      print("Came in");
      if (methodCall.method == 'getDirectoryPath') {
        return "Test";
      }
      return null;
    }
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, handler);

    // when(FilePicker.platform.getDirectoryPath).thenReturn(({String dialogTitle, String initialDirectory, bool lockParentWindow}) async => "test");
    // await expect(FilePicker.platform.getDirectoryPath, "test");
    await tester.tap(move);
    await tester.pump();
    tester.state(find.byType(MyHomePage)).setState(() {});
    await tester.pump();
    await tester.pump();



    expect(move, findsOneWidget);
    var display = find.widgetWithText(ElevatedButton, "Display");
    expect(display, findsOneWidget);
    expect(MyApp.gallery.selected.isNotEmpty, true);
    expect(tester.widget<ElevatedButton>(display).enabled, true);
    expect(tester.widget<ElevatedButton>(move).enabled, true);

    await tester.tap(move);
  });


  test("Placeholder", () {
    // await tester.pumpWidget(MyHomePage(title: 'Flutter Test Home Page'));


    var state = new MyHomePage().createState();
    expect(() => state.move(), throwsA(isA<Error>()));


    // find.byType(type);
  },
  skip: true);

  testWidgets("Placeholder2", (tester) async{
    await tester.pumpWidget(MyApp(title: 'Flutter Test Home Page'));
    //
    MyHomePage page = tester.widget(find.byType(MyHomePage));
    var state = page.createState();
    final type = state.runtimeType;
    // var s = tester.state(find.byType(MyHomePage)) as type;

    // var page = MyHomePage(title: "Test");
    // var state = page.createState();
    // state.initState();
    expect(() => state.move(), throwsA(isA<Exception>()));
    for(var e in tester.allElements){
      debugPrint(e.toString());
    }
    // expect(() => state.move(), returnsNormally);
    // expect

  });

  testWidgets("Test Mocking FilePicker", (tester) async{
    await tester.pumpWidget(MyApp(title: 'Flutter Test Home Page'));


    var move =
    find.byKey(ValueKey("Move"));
    // find.widgetWithText(ElevatedButton, "Move");
    expect(move, findsOneWidget);
    expect(tester.widget<ElevatedButton>(move).enabled, false);


    expect(MyApp.gallery, isNotNull);

    MyApp.gallery.selected.add("Test");

    // final filePicker = new MockFilePicker();

    // when(FilePicker.platform).thenReturn(filePicker);
    // when(filePicker.getDirectoryPath()).thenReturn(new Future(() => "Test"));

    // expect(FilePicker.platform.getDirectoryPath, "test");
    await tester.tap(move);
    await tester.pump();
    tester.state(find.byType(MyHomePage)).setState(() {});
    await tester.pump();
    await tester.pump();



    expect(move, findsOneWidget);
    var display = find.widgetWithText(ElevatedButton, "Display");
    expect(display, findsOneWidget);
    expect(MyApp.gallery.selected.isNotEmpty, true);
    expect(tester.widget<ElevatedButton>(display).enabled, true);
    expect(tester.widget<ElevatedButton>(move).enabled, true);

    await tester.tap(move);

  });
}
mockFilePicker() {
  const MethodChannel channel =
  MethodChannel('miguelruivo.flutter.plugins.filepicker');
  channel.setMockMethodCallHandler((MethodCall methodCall) async {
    print("MockMethodChannel run");

    final filePickerResult = [{'name': "test"}];
    return filePickerResult;
  });
}