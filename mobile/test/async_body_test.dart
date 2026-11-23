import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/widgets.dart';

Widget _host(AsyncValue<String> value, {VoidCallback? onRetry}) => MaterialApp(
      theme: ThemeData(),
      home: Scaffold(
        body: AsyncBody<String>(
          value: value,
          onRetry: onRetry ?? () {},
          builder: (d) => Text('data:$d'),
        ),
      ),
    );

void main() {
  group('AsyncBody', () {
    testWidgets('shows AppLoader while loading', (tester) async {
      await tester.pumpWidget(_host(const AsyncLoading()));
      expect(find.byType(AppLoader), findsOneWidget);
      await tester.pumpWidget(const SizedBox()); // dispose repeating animation
    });

    testWidgets('error shows plain message and retry works', (tester) async {
      var retries = 0;
      await tester.pumpWidget(_host(
        AsyncError(Exception('internal boom'), StackTrace.empty),
        onRetry: () => retries++,
      ));
      expect(find.text('Something went wrong. Please try again.'), findsOneWidget);
      expect(find.textContaining('Exception'), findsNothing);
      await tester.tap(find.text('Try again'));
      expect(retries, 1);
    });

    testWidgets('DioException error never leaks Exception text', (tester) async {
      final err = DioException(
        requestOptions: RequestOptions(path: '/x'),
        type: DioExceptionType.connectionError,
      );
      await tester.pumpWidget(_host(AsyncError(err, StackTrace.empty)));
      expect(find.textContaining('Exception'), findsNothing);
      expect(find.byType(ErrorState), findsOneWidget);
    });

    testWidgets('renders builder output on data', (tester) async {
      await tester.pumpWidget(_host(const AsyncData('hello')));
      expect(find.text('data:hello'), findsOneWidget);
    });
  });
}
