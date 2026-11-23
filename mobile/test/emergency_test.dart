import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/emergency/emergency_repository.dart';
import 'package:mobile/features/emergency/sos_sheet.dart';

void main() {
  test('Emergency.fromJson handles nullable fields', () {
    final e = Emergency.fromJson({
      'id': 7,
      'kind': 'fire',
      'kind_label': 'Fire',
      'message': null,
      'raised_by_name': 'Asha',
      'flat_number': null,
      'phone': null,
      'role_label': 'Guard',
      'created_at': '2026-11-23T10:00:00Z',
      'resolved_at': null,
      'resolved_by_name': null,
      'mine': true,
    });
    expect(e.id, 7);
    expect(e.message, isNull);
    expect(e.flatNumber, isNull);
    expect(e.phone, isNull);
    expect(e.resolvedAt, isNull);
    expect(e.mine, isTrue);
    expect(e.whereLabel, 'Guard at the gate');
  });

  test('Emergency.fromJson reads flat and phone', () {
    final e = Emergency.fromJson({
      'id': 1,
      'kind': 'medical',
      'kind_label': 'Medical',
      'message': 'Chest pain',
      'raised_by_name': 'Ravi',
      'flat_number': 'B-202',
      'phone': '+911234567890',
      'role_label': 'Owner',
      'created_at': '2026-11-23T10:00:00Z',
    });
    expect(e.whereLabel, 'Flat B-202');
    expect(e.phone, '+911234567890');
    expect(e.mine, isFalse);
  });

  testWidgets('SOS sheet shows four kinds and send button', (tester) async {
    await tester.pumpWidget(const ProviderScope(
      child: MaterialApp(home: Scaffold(body: SosSheet())),
    ));
    for (final t in ['Fire', 'Medical', 'Security', 'Other help', 'Send alert now']) {
      expect(find.text(t), findsOneWidget);
    }
    expect(find.text('Send emergency alert'), findsOneWidget);
  });
}
