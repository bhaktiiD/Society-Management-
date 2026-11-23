import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/widgets.dart';

Widget _app(Widget child, {bool disableAnimations = false}) => MaterialApp(
      theme: ThemeData(),
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: disableAnimations),
        child: Scaffold(body: child),
      ),
    );

void main() {
  group('AppLoader', () {
    testWidgets('animates without exceptions', (tester) async {
      await tester.pumpWidget(_app(const AppLoader()));
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 300));
      }
      expect(tester.takeException(), isNull);
      expect(find.byIcon(Icons.apartment_rounded), findsOneWidget);
    });

    testWidgets('shows label when given', (tester) async {
      await tester.pumpWidget(_app(const AppLoader(label: 'Fetching bills')));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Fetching bills'), findsOneWidget);
    });

    testWidgets('with animations disabled it settles', (tester) async {
      await tester.pumpWidget(_app(const AppLoader(label: 'Loading'), disableAnimations: true));
      await tester.pumpAndSettle();
      expect(find.text('Loading'), findsOneWidget);
    });

    testWidgets('dotsOnly has no building icon', (tester) async {
      await tester.pumpWidget(_app(const AppLoader(dotsOnly: true)));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byIcon(Icons.apartment_rounded), findsNothing);
    });
  });
}
