import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';

String _s(dynamic v) => v?.toString() ?? '';
String? _n(dynamic v) {
  final s = v?.toString().trim();
  return (s == null || s.isEmpty) ? null : s;
}

class GatePass {
  const GatePass({
    required this.id,
    required this.visitorName,
    required this.visitorPhone,
    required this.visitorEmail,
    this.purpose,
    this.vehicleNumber,
    required this.visitDate,
    required this.validUntil,
    required this.validDays,
    this.passCode,
    required this.status,
    this.flatNumber,
    this.createdByName,
    this.createdAt,
    this.usedAt,
    this.ownerNames = const [],
  });

  final int id;
  final String visitorName;
  final String visitorPhone;
  final String visitorEmail;
  final String? purpose;
  final String? vehicleNumber;
  final String visitDate; // YYYY-MM-DD
  final String validUntil;
  final int validDays;
  final String? passCode;
  final String status;
  final String? flatNumber;
  final String? createdByName;
  final String? createdAt;
  final String? usedAt;
  final List<String> ownerNames;

  bool get isActive => status == 'active';

  factory GatePass.fromJson(Map<String, dynamic> j) => GatePass(
        id: (j['id'] as num?)?.toInt() ?? 0,
        visitorName: _s(j['visitor_name']),
        visitorPhone: _s(j['visitor_phone']),
        visitorEmail: _s(j['visitor_email']),
        purpose: _n(j['purpose']),
        vehicleNumber: _n(j['vehicle_number']),
        visitDate: _s(j['visit_date']),
        validUntil: _s(j['valid_until']),
        validDays: (j['valid_days'] as num?)?.toInt() ?? 1,
        passCode: _n(j['pass_code']),
        status: _s(j['status']),
        flatNumber: _n(j['flat_number']),
        createdByName: _n(j['created_by_name']),
        createdAt: _n(j['created_at']),
        usedAt: _n(j['used_at']),
        ownerNames: ((j['owner_names'] as List?) ?? const []).map((e) => '$e').toList(),
      );
}

class PassVerification {
  const PassVerification({required this.pass, required this.valid, this.reason});
  final GatePass pass;
  final bool valid;
  final String? reason;

  factory PassVerification.fromJson(Map<String, dynamic> j) => PassVerification(
        pass: GatePass.fromJson(j['pass'] as Map<String, dynamic>),
        valid: j['valid'] == true,
        reason: _n(j['reason']),
      );
}

List<GatePass> _list(dynamic data) =>
    (data as List).map((e) => GatePass.fromJson(e as Map<String, dynamic>)).toList();

/// "K7M29XQP" -> "K7M2 9XQP".
String formatPassCode(String code) {
  final c = code.replaceAll(RegExp(r'\s'), '');
  return c.length > 4 ? '${c.substring(0, 4)} ${c.substring(4)}' : c;
}

const _wd = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _mo = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// "2026-11-28" -> "Sat 28 Nov". Falls back to the input when unparsable.
String formatPassDate(String iso) {
  final d = DateTime.tryParse(iso);
  if (d == null) return iso;
  return '${_wd[d.weekday - 1]} ${d.day} ${_mo[d.month - 1]}';
}

String validityText(int days) => 'valid $days ${days == 1 ? 'day' : 'days'}';

class GatePassRepository {
  GatePassRepository(this._dio);
  final Dio _dio;

  Future<List<GatePass>> list() async => _list((await _dio.get('/passes')).data);

  Future<GatePass> create({
    required String name,
    required String phone,
    required String email,
    String? purpose,
    String? vehicle,
    required DateTime visitDate,
    required int validDays,
  }) async {
    final d = '${visitDate.year.toString().padLeft(4, '0')}-'
        '${visitDate.month.toString().padLeft(2, '0')}-${visitDate.day.toString().padLeft(2, '0')}';
    final r = await _dio.post('/passes', data: {
      'visitor_name': name,
      'visitor_phone': phone,
      'visitor_email': email,
      'purpose': purpose,
      'vehicle_number': vehicle,
      'visit_date': d,
      'valid_days': validDays,
    });
    return GatePass.fromJson(r.data as Map<String, dynamic>);
  }

  Future<GatePass> cancel(int id) async =>
      GatePass.fromJson((await _dio.post('/passes/$id/cancel')).data as Map<String, dynamic>);

  // ---- guard
  Future<PassVerification> verify(String code) async => PassVerification.fromJson(
      (await _dio.post('/guard/passes/verify', data: {'code': code})).data as Map<String, dynamic>);

  Future<GatePass> checkIn(int id) async => GatePass.fromJson(
      (await _dio.post('/guard/passes/$id/check-in')).data as Map<String, dynamic>);

  Future<List<GatePass>> today() async => _list((await _dio.get('/guard/passes/today')).data);
}

final gatePassRepositoryProvider =
    Provider<GatePassRepository>((ref) => GatePassRepository(ref.watch(dioProvider)));

final gatePassesProvider = FutureProvider.autoDispose<List<GatePass>>(
  (ref) => ref.watch(gatePassRepositoryProvider).list(),
);

final guardPassesTodayProvider = FutureProvider.autoDispose<List<GatePass>>(
  (ref) => ref.watch(gatePassRepositoryProvider).today(),
);
