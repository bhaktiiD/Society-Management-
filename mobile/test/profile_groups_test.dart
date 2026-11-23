import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/profile/profile_groups.dart';
import 'package:mobile/models/models.dart';

Widget _host(bool canApprove) => ProviderScope(
      child: MaterialApp(
        builder: (c, w) => MediaQuery(
          data: MediaQuery.of(c).copyWith(textScaler: const TextScaler.linear(1.4), size: const Size(360, 3000)),
          child: w!,
        ),
        home: Scaffold(body: ListView(children: [ResidentGroups(canApproveGuests: canApprove)])),
      ),
    );

void main() {
  testWidgets('resident groups render expected titles', (t) async {
    await t.pumpWidget(_host(true));
    for (final s in [
      'My bills', 'Payment history', 'Society history', 'Visitors', 'Gate passes',
      'Guest approvals', 'Community', 'Community hall', 'Complaints', 'Polls',
      'Meetings', 'Notices', 'Safety', 'Emergency contacts',
    ]) {
      expect(find.text(s), findsWidgets, reason: s);
    }
    expect(find.text('My bills'), findsNWidgets(2)); // header + row
  });

  testWidgets('guest approvals hidden when not allowed', (t) async {
    await t.pumpWidget(_host(false));
    expect(find.text('Guest approvals'), findsNothing);
    expect(find.text('Gate passes'), findsOneWidget);
  });

  test('residentSummary', () {
    const me = Me(
      fullName: 'A', email: 'a@x', phone: null, avatarVersion: null, isPending: false,
      isSecretary: false, isGuard: false,
      flats: [FlatRole(flatId: 1, flatNumber: 'A-101', kind: 'owner', isResident: true)],
    );
    expect(residentSummary(me), 'Flat A-101 (Owner)');
  });
}
