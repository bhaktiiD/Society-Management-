/// Plain typed models for API responses. Hand-written (no codegen) so the
/// mapping is easy to read and review.
library;

class FlatRole {
  const FlatRole({
    required this.flatId,
    required this.flatNumber,
    required this.kind,
    required this.isResident,
  });

  final int flatId;
  final String flatNumber;
  final String kind; // owner | tenant
  final bool isResident;

  factory FlatRole.fromJson(Map<String, dynamic> j) => FlatRole(
        flatId: j['flat_id'] as int,
        flatNumber: j['flat_number'] as String,
        kind: j['kind'] as String,
        isResident: j['is_resident'] as bool,
      );
}

/// The signed-in person and every role they currently hold.
class Me {
  const Me({
    required this.fullName,
    required this.email,
    required this.phone,
    required this.avatarVersion,
    required this.isPending,
    required this.isSecretary,
    required this.isGuard,
    required this.flats,
  });

  final String fullName;
  final String email;
  final String? phone;

  /// Changes whenever the profile photo changes (null = no photo).
  final int? avatarVersion;
  final bool isPending;
  final bool isSecretary;
  final bool isGuard;
  final List<FlatRole> flats;

  bool get isResident => flats.isNotEmpty;
  bool get isOwner => flats.any((f) => f.kind == 'owner');
  bool get isTenant => flats.any((f) => f.kind == 'tenant');
  bool get canApproveGuests => flats.any((f) => f.isResident);

  factory Me.fromJson(Map<String, dynamic> j) {
    final roles = j['roles'] as Map<String, dynamic>;
    return Me(
      fullName: j['full_name'] as String,
      email: j['email'] as String,
      phone: j['phone'] as String?,
      avatarVersion: j['avatar_version'] as int?,
      isPending: j['status'] == 'pending',
      isSecretary: j['is_secretary'] as bool,
      isGuard: j['is_guard'] as bool,
      flats: (roles['flats'] as List)
          .map((e) => FlatRole.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

class Charge {
  const Charge({
    required this.id,
    required this.title,
    required this.chargeType,
    required this.flatNumber,
    required this.amountPaise,
    required this.paidPaise,
    required this.balancePaise,
    required this.status,
    required this.dueDate,
    required this.overdue,
  });

  final int id;
  final String title;
  final String chargeType;
  final String? flatNumber;
  final int amountPaise;
  final int paidPaise;
  final int balancePaise;
  final String status; // outstanding | partial | paid
  final String dueDate;
  final bool overdue;

  bool get isPaid => status == 'paid';

  factory Charge.fromJson(Map<String, dynamic> j) => Charge(
        id: j['id'] as int,
        title: j['title'] as String,
        chargeType: j['charge_type'] as String,
        flatNumber: j['flat_number'] as String?,
        amountPaise: j['amount_paise'] as int,
        paidPaise: j['paid_paise'] as int,
        balancePaise: j['balance_paise'] as int,
        status: j['status'] as String,
        dueDate: j['due_date'] as String,
        overdue: j['overdue'] as bool,
      );
}

class PaymentIntent {
  const PaymentIntent({
    required this.intentId,
    required this.orderId,
    required this.amountPaise,
    required this.keyId,
  });

  final int intentId;
  final String orderId;
  final int amountPaise;
  final String keyId;

  factory PaymentIntent.fromJson(Map<String, dynamic> j) => PaymentIntent(
        intentId: j['intent_id'] as int,
        orderId: j['order_id'] as String,
        amountPaise: j['amount_paise'] as int,
        keyId: j['key_id'] as String,
      );
}

class Notice {
  const Notice({
    required this.id,
    required this.title,
    required this.body,
    required this.pinned,
    required this.createdAt,
  });

  final int id;
  final String title;
  final String body;
  final bool pinned;
  final String createdAt;

  factory Notice.fromJson(Map<String, dynamic> j) => Notice(
        id: j['id'] as int,
        title: j['title'] as String,
        body: j['body'] as String,
        pinned: j['pinned'] as bool,
        createdAt: j['created_at'] as String,
      );
}

class GuestRequest {
  const GuestRequest({
    required this.id,
    required this.flatNumber,
    required this.guestName,
    required this.guestPhone,
    required this.purpose,
    required this.status,
    required this.createdAt,
    required this.expiresAt,
  });

  final int id;
  final String? flatNumber;
  final String guestName;
  final String? guestPhone;
  final String? purpose;
  final String status; // pending | approved | denied | expired | checked_in | checked_out
  final String createdAt;
  final String expiresAt;

  factory GuestRequest.fromJson(Map<String, dynamic> j) => GuestRequest(
        id: j['id'] as int,
        flatNumber: j['flat_number'] as String?,
        guestName: j['guest_name'] as String,
        guestPhone: j['guest_phone'] as String?,
        purpose: j['purpose'] as String?,
        status: j['status'] as String,
        createdAt: j['created_at'] as String,
        expiresAt: j['expires_at'] as String,
      );
}

class Defaulter {
  const Defaulter({
    required this.flatId,
    required this.flatNumber,
    required this.ownerName,
    required this.overduePaise,
  });
  final int flatId;
  final String? flatNumber;
  final String? ownerName;
  final int overduePaise;

  factory Defaulter.fromJson(Map<String, dynamic> j) => Defaulter(
        flatId: j['flat_id'] as int,
        flatNumber: j['flat_number'] as String?,
        ownerName: j['owner_name'] as String?,
        overduePaise: j['overdue_paise'] as int,
      );
}

class Collections {
  const Collections({
    required this.flatCount,
    required this.memberCount,
    required this.pendingInvites,
    required this.billedPaise,
    required this.collectedPaise,
    required this.outstandingPaise,
    required this.maintBilledPaise,
    required this.maintCollectedPaise,
    required this.maintOutstandingPaise,
    required this.paid,
    required this.partial,
    required this.outstanding,
    required this.defaulters,
  });

  final int flatCount;
  final int memberCount;
  final int pendingInvites;
  final int billedPaise;
  final int collectedPaise;
  final int outstandingPaise;

  /// Monthly maintenance bills (incl. their late fees) only.
  final int maintBilledPaise;
  final int maintCollectedPaise;
  final int maintOutstandingPaise;
  final int paid;
  final int partial;
  final int outstanding;
  final List<Defaulter> defaulters;

  factory Collections.fromJson(Map<String, dynamic> j) {
    final counts = j['counts'] as Map<String, dynamic>;
    final maint = j['maintenance'] as Map<String, dynamic>;
    return Collections(
      flatCount: j['flat_count'] as int,
      memberCount: j['member_count'] as int,
      pendingInvites: j['pending_invites'] as int,
      billedPaise: j['billed_paise'] as int,
      collectedPaise: j['collected_paise'] as int,
      outstandingPaise: j['outstanding_paise'] as int,
      maintBilledPaise: maint['billed_paise'] as int,
      maintCollectedPaise: maint['collected_paise'] as int,
      maintOutstandingPaise: maint['outstanding_paise'] as int,
      paid: counts['paid'] as int,
      partial: counts['partial'] as int,
      outstanding: counts['outstanding'] as int,
      defaulters: (j['defaulters'] as List)
          .map((e) => Defaulter.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

class FlatMember {
  const FlatMember({
    required this.membershipId,
    required this.name,
    required this.email,
    required this.phone,
    required this.kind,
    required this.isResident,
  });
  final int membershipId;
  final String name;
  final String email;
  final String? phone;
  final String kind;
  final bool isResident;

  factory FlatMember.fromJson(Map<String, dynamic> j) => FlatMember(
        membershipId: j['membership_id'] as int,
        name: j['name'] as String,
        email: j['email'] as String,
        phone: j['phone'] as String?,
        kind: j['kind'] as String,
        isResident: j['is_resident'] as bool,
      );
}

/// A pre-registered email that has not signed up yet (or a staff invite).
class PendingInvite {
  const PendingInvite({
    required this.id,
    required this.email,
    required this.role,
    this.accepted = false,
    this.fullName,
    this.phone,
  });
  final int id;
  final String email;
  final String? fullName;
  final String? phone;
  final String role; // owner | tenant | guard | secretary
  final bool accepted;

  factory PendingInvite.fromJson(Map<String, dynamic> j) => PendingInvite(
        id: j['id'] as int,
        email: j['email'] as String,
        role: j['role'] as String,
        accepted: (j['accepted'] as bool?) ?? false,
        fullName: j['full_name'] as String?,
        phone: j['phone'] as String?,
      );
}

class FlatInfo {
  const FlatInfo({
    required this.id,
    required this.flatNumber,
    required this.flatType,
    required this.members,
    required this.pendingInvites,
  });
  final int id;
  final String flatNumber;
  final String? flatType; // 1RK | 1BHK | 2BHK, null until the admin sets it
  final List<FlatMember> members;
  final List<PendingInvite> pendingInvites;

  factory FlatInfo.fromJson(Map<String, dynamic> j) => FlatInfo(
        id: j['id'] as int,
        flatNumber: j['flat_number'] as String,
        flatType: j['flat_type'] as String?,
        members: (j['members'] as List)
            .map((e) => FlatMember.fromJson(e as Map<String, dynamic>))
            .toList(),
        pendingInvites: (j['pending_invites'] as List)
            .map((e) => PendingInvite.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

/// Standing monthly rate + late fee for one flat type. Amounts are null until
/// the admin sets them for the first time.
class PlanRate {
  const PlanRate({required this.flatType, this.amountPaise, this.penaltyPaise});
  final String flatType;
  final int? amountPaise;
  final int? penaltyPaise;

  bool get isSet => amountPaise != null;

  factory PlanRate.fromJson(Map<String, dynamic> j) => PlanRate(
        flatType: j['flat_type'] as String,
        amountPaise: j['amount_paise'] as int?,
        penaltyPaise: j['penalty_paise'] as int?,
      );
}

class BillingSettings {
  const BillingSettings({
    required this.dueDay,
    required this.untypedFlats,
    required this.plans,
  });
  final int dueDay;
  final int untypedFlats;
  final List<PlanRate> plans;

  bool get anyRateSet => plans.any((p) => p.isSet);

  factory BillingSettings.fromJson(Map<String, dynamic> j) => BillingSettings(
        dueDay: j['due_day'] as int,
        untypedFlats: j['untyped_flats'] as int,
        plans: (j['plans'] as List)
            .map((e) => PlanRate.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
