import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/bookings/booking_pickers.dart';
import 'package:mobile/features/bookings/booking_planner.dart';
import 'package:mobile/features/bookings/bookings_repository.dart';

void main() {
  test('hm parse/format and labels', () {
    expect(parseHm('21:30'), 1290);
    expect(parseHm('bad'), isNull);
    expect(formatHm(540), '09:00');
    expect(timeText(21 * 60), '9 PM');
    expect(timeText(9 * 60 + 30), '9:30 AM');
    expect(timeText(12 * 60), '12 PM');
    expect(timeTextFull(21 * 60), '9:00 PM');
    expect(durationText(60), '1 hour');
    expect(durationText(150), '2 hr 30 min');
    expect(const TimeRange(21 * 60, 22 * 60).label, '9 PM - 10 PM');
  });

  test('overlap is end-exclusive', () {
    const a = TimeRange(600, 660);
    expect(a.overlaps(const TimeRange(660, 720)), isFalse);
    expect(a.overlaps(const TimeRange(630, 700)), isTrue);
    expect(overlapsAny(a, const [TimeRange(0, 100), TimeRange(650, 700)]), isTrue);
  });

  test('snap, min and max rules', () {
    expect(snapStep(14 * 60 + 14), 14 * 60);
    expect(snapStep(14 * 60 + 16), 14 * 60 + 30);
    expect(snapStep(5 * 60), kOpenMin);
    const old = TimeRange(18 * 60, 19 * 60);
    expect(adjustRange(old, 18 * 60 + 30, 19 * 60), const TimeRange(18 * 60 + 30, 19 * 60 + 30));
    expect(adjustRange(old, 18 * 60, 18 * 60 + 30), const TimeRange(17 * 60 + 30, 18 * 60 + 30));
    expect(adjustRange(old, 8 * 60, 19 * 60), const TimeRange(8 * 60, 16 * 60));
    expect(adjustRange(old, 21 * 60 + 30, 19 * 60), const TimeRange(21 * 60, 22 * 60));
  });

  test('full day and free window', () {
    expect(fullyBooked(const [TimeRange(480, 800), TimeRange(800, 1320)]), isTrue);
    expect(fullyBooked(const [TimeRange(480, 800), TimeRange(810, 1320)]), isFalse);
    expect(firstFreeWindow(const [TimeRange(480, 600)]), const TimeRange(600, 660));
    expect(firstFreeWindow(const [], from: 20 * 60 + 15), const TimeRange(20 * 60 + 30, 21 * 60 + 30));
    expect(firstFreeWindow(const [TimeRange(480, 1320)]), isNull);
  });

  test('DayAvailability.fromJson parses busy ranges', () {
    final d = DayAvailability.fromJson({
      'date': '2026-11-28',
      'busy': [
        {'start': '09:00', 'end': '10:30'},
        {'start': 'x', 'end': '12:00'},
      ],
      'open': '08:00',
      'close': '22:00',
    });
    expect(d.busy, [const TimeRange(540, 630)]);
    expect(d.open, 480);
    expect(d.isFree, isFalse);
    expect(DayAvailability.fromJson({'date': '2026-11-29', 'busy': []}).isFree, isTrue);
  });

  test('HallBooking time label with fallback', () {
    final b = HallBooking.fromJson({
      'id': 1, 'date': '2026-11-28', 'status': 'pending', 'start_time': '21:00', 'end_time': '22:00',
    });
    expect(b.displayTime, '9 PM - 10 PM');
  });

  test('purpose compose/split', () {
    expect(composePurpose('Birthday', ' cake '), 'Birthday: cake');
    expect(composePurpose('Meeting', ''), 'Meeting');
    expect(splitPurpose('Birthday: cake'), ('Birthday', 'cake'));
    expect(splitPurpose('Just text'), (null, 'Just text'));
  });

  testWidgets('planner defaults to free hour and submits draft; busy disables send', (tester) async {
    tester.view.physicalSize = const Size(360, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    BookingDraft? sent;
    final now = DateTime(2026, 11, 27, 10, 10);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: BookingPlanner(
            clock: () => now,
            days: [
              DayAvailability(date: '2026-11-27', busy: const [TimeRange(630, 720)]),
              DayAvailability(date: '2026-11-28'),
            ],
            onSubmit: (d) async => sent = d,
          ),
        ),
      ),
    ));
    expect(find.textContaining('Fri, 27 Nov - Today'), findsWidgets);
    expect(find.text('Morning'), findsOneWidget);
    await tester.tap(find.text('Evening'));
    await tester.pump();
    await tester.ensureVisible(find.text('Send request'));
    await tester.tap(find.text('Send request'));
    await tester.pump();
    expect(sent?.start, '16:00');
    expect(sent?.end, '20:00');

    // Morning is already partly booked/passed today: shown but not selectable.
    expect(find.text('Not available'), findsWidgets);
  });
}
