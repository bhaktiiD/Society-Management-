import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/models/models.dart';

Map<String, dynamic> _meJson({
  String status = 'active',
  List<Map<String, dynamic>> flats = const [],
}) =>
    {
      'full_name': 'Asha Rao',
      'email': 'asha@example.com',
      'phone': null,
      'status': status,
      'is_secretary': false,
      'is_guard': false,
      'roles': {'flats': flats},
    };

Map<String, dynamic> _flat(String kind, {bool resident = true}) => {
      'flat_id': 7,
      'flat_number': 'A-101',
      'kind': kind,
      'is_resident': resident,
    };

void main() {
  group('Me.fromJson', () {
    test('owner resident', () {
      final me = Me.fromJson(_meJson(flats: [_flat('owner')]));
      expect(me.fullName, 'Asha Rao');
      expect(me.phone, isNull);
      expect(me.isPending, isFalse);
      expect(me.isResident, isTrue);
      expect(me.isOwner, isTrue);
      expect(me.isTenant, isFalse);
      expect(me.canApproveGuests, isTrue);
      expect(me.flats.single.flatNumber, 'A-101');
    });

    test('tenant', () {
      final me = Me.fromJson(_meJson(flats: [_flat('tenant')]));
      expect(me.isTenant, isTrue);
      expect(me.isOwner, isFalse);
    });

    test('non-resident owner cannot approve guests', () {
      final me = Me.fromJson(_meJson(flats: [_flat('owner', resident: false)]));
      expect(me.isOwner, isTrue);
      expect(me.canApproveGuests, isFalse);
    });

    test('pending user with no flats', () {
      final me = Me.fromJson(_meJson(status: 'pending'));
      expect(me.isPending, isTrue);
      expect(me.isResident, isFalse);
      expect(me.canApproveGuests, isFalse);
    });
  });

  test('Charge.fromJson', () {
    final c = Charge.fromJson({
      'id': 1,
      'title': 'Maintenance',
      'charge_type': 'maintenance',
      'flat_number': null,
      'amount_paise': 250000,
      'paid_paise': 100000,
      'balance_paise': 150000,
      'status': 'partial',
      'due_date': '2026-11-24',
      'overdue': true,
    });
    expect(c.flatNumber, isNull);
    expect(c.balancePaise, 150000);
    expect(c.isPaid, isFalse);
    expect(c.overdue, isTrue);
  });

  group('Collections.fromJson', () {
    Map<String, dynamic> json(List<Map<String, dynamic>> defaulters) => {
          'flat_count': 10,
          'member_count': 18,
          'pending_invites': 2,
          'billed_paise': 1000000,
          'collected_paise': 600000,
          'outstanding_paise': 400000,
          'maintenance': {'billed_paise': 800000, 'collected_paise': 500000, 'outstanding_paise': 300000},
          'counts': {'paid': 5, 'partial': 2, 'outstanding': 3},
          'defaulters': defaulters,
        };

    test('with defaulters', () {
      final c = Collections.fromJson(json([
        {'flat_id': 2, 'flat_number': 'B-2', 'owner_name': 'Asha', 'overdue_paise': 5000},
        {'flat_id': 3, 'flat_number': null, 'owner_name': null, 'overdue_paise': 100},
      ]));
      expect(c.paid, 5);
      expect(c.outstandingPaise, 400000);
      expect(c.defaulters, hasLength(2));
      expect(c.defaulters.first.flatNumber, 'B-2');
      expect(c.defaulters.last.flatNumber, isNull);
      expect(c.defaulters.first.ownerName, 'Asha');
      expect(c.maintCollectedPaise, 500000);
    });

    test('empty defaulters', () {
      expect(Collections.fromJson(json([])).defaulters, isEmpty);
    });
  });

  group('FlatInfo.fromJson', () {
    test('members and invites with null phone and name', () {
      final f = FlatInfo.fromJson({
        'id': 3,
        'flat_number': 'C-3',
        'flat_type': null,
        'members': [
          {
            'membership_id': 11,
            'name': 'Ravi',
            'email': 'r@example.com',
            'phone': null,
            'kind': 'tenant',
            'is_resident': true,
          },
        ],
        'pending_invites': [
          {'id': 5, 'email': 'new@example.com', 'role': 'owner', 'full_name': null, 'phone': null},
        ],
      });
      expect(f.flatType, isNull);
      expect(f.members.single.phone, isNull);
      expect(f.members.single.kind, 'tenant');
      final inv = f.pendingInvites.single;
      expect(inv.fullName, isNull);
      expect(inv.phone, isNull);
      expect(inv.accepted, isFalse);
    });

    test('PendingInvite reads accepted and optional fields', () {
      final inv = PendingInvite.fromJson({
        'id': 1,
        'email': 'g@example.com',
        'role': 'guard',
        'accepted': true,
        'full_name': 'Gopal',
        'phone': '9999999999',
      });
      expect(inv.accepted, isTrue);
      expect(inv.fullName, 'Gopal');
      expect(inv.phone, '9999999999');
    });
  });

  group('BillingSettings.fromJson', () {
    test('unset rates', () {
      final b = BillingSettings.fromJson({
        'due_day': 5,
        'untyped_flats': 4,
        'plans': [
          {'flat_type': '1RK', 'amount_paise': null, 'penalty_paise': null},
        ],
      });
      expect(b.dueDay, 5);
      expect(b.untypedFlats, 4);
      expect(b.plans.single.isSet, isFalse);
      expect(b.anyRateSet, isFalse);
    });

    test('some rates set', () {
      final b = BillingSettings.fromJson({
        'due_day': 10,
        'untyped_flats': 0,
        'plans': [
          {'flat_type': '1RK', 'amount_paise': null, 'penalty_paise': null},
          {'flat_type': '2BHK', 'amount_paise': 300000, 'penalty_paise': 50000},
        ],
      });
      expect(b.plans.first.isSet, isFalse);
      expect(b.plans.last.isSet, isTrue);
      expect(b.plans.last.penaltyPaise, 50000);
      expect(b.anyRateSet, isTrue);
    });
  });
}
