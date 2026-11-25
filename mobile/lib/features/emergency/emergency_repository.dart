import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';

class Emergency {
  const Emergency({
    required this.id,
    required this.kind,
    required this.kindLabel,
    required this.raisedByName,
    required this.roleLabel,
    required this.createdAt,
    this.message,
    this.flatNumber,
    this.phone,
    this.resolvedAt,
    this.resolvedByName,
    this.mine = false,
  });

  final int id;
  final String kind;
  final String kindLabel;
  final String? message;
  final String raisedByName;
  final String? flatNumber;
  final String? phone;
  final String roleLabel;
  final DateTime createdAt;
  final DateTime? resolvedAt;
  final String? resolvedByName;
  final bool mine;

  factory Emergency.fromJson(Map<String, dynamic> j) {
    String? str(String k) {
      final v = j[k];
      return v is String && v.trim().isNotEmpty ? v : null;
    }

    DateTime? date(String k) {
      final s = str(k);
      return s == null ? null : DateTime.tryParse(s)?.toLocal();
    }

    return Emergency(
      id: (j['id'] as num).toInt(),
      kind: (j['kind'] as String?) ?? 'other',
      kindLabel: (j['kind_label'] as String?) ?? 'Urgent Help Needed',
      message: str('message'),
      raisedByName: (j['raised_by_name'] as String?) ?? 'A neighbour',
      flatNumber: str('flat_number'),
      phone: str('phone'),
      roleLabel: (j['role_label'] as String?) ?? '',
      createdAt: date('created_at') ?? DateTime.now(),
      resolvedAt: date('resolved_at'),
      resolvedByName: str('resolved_by_name'),
      mine: j['mine'] == true,
    );
  }

  /// "Flat B-202", or the role ("Guard at the gate") when there is no flat.
  String get whereLabel {
    if (flatNumber != null) return 'Flat $flatNumber';
    return roleLabel == 'Guard' ? 'Guard at the gate' : roleLabel;
  }
}

class EmergencyRepository {
  EmergencyRepository(this._dio);
  final Dio _dio;

  Future<Emergency> raise({required String kind, String? message}) async {
    final text = message?.trim();
    final r = await _dio.post('/emergencies', data: {
      'kind': kind,
      if (text != null && text.isNotEmpty) 'message': text,
    });
    return Emergency.fromJson(r.data as Map<String, dynamic>);
  }

  Future<List<Emergency>> active() async {
    final r = await _dio.get('/emergencies/active');
    return (r.data as List).map((e) => Emergency.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Emergency> resolve(int id) async {
    final r = await _dio.post('/emergencies/$id/resolve');
    return Emergency.fromJson(r.data as Map<String, dynamic>);
  }
}

final emergencyRepositoryProvider =
    Provider<EmergencyRepository>((ref) => EmergencyRepository(ref.watch(dioProvider)));

final activeEmergenciesProvider = FutureProvider.autoDispose<List<Emergency>>(
  (ref) => ref.watch(emergencyRepositoryProvider).active(),
);

Future<Emergency> raiseEmergency(WidgetRef ref, {required String kind, String? message}) async {
  final e = await ref.read(emergencyRepositoryProvider).raise(kind: kind, message: message);
  ref.invalidate(activeEmergenciesProvider);
  return e;
}
