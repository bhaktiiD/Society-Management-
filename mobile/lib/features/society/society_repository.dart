import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';

class MonthSummary {
  const MonthSummary({
    required this.month,
    required this.billedPaise,
    required this.collectedPaise,
    required this.flatsBilled,
    required this.flatsFullyPaid,
  });
  final String month; // YYYY-MM
  final int billedPaise;
  final int collectedPaise;
  final int flatsBilled;
  final int flatsFullyPaid;

  factory MonthSummary.fromJson(Map<String, dynamic> j) => MonthSummary(
        month: (j['month'] ?? '') as String,
        billedPaise: (j['billed_paise'] ?? 0) as int,
        collectedPaise: (j['collected_paise'] ?? 0) as int,
        flatsBilled: (j['flats_billed'] ?? 0) as int,
        flatsFullyPaid: (j['flats_fully_paid'] ?? 0) as int,
      );
}

class SocietyCharge {
  const SocietyCharge({
    required this.id,
    required this.title,
    required this.kind,
    required this.amountPerFlatPaise,
    required this.dueDate,
    required this.createdAt,
    required this.flatsBilled,
    required this.flatsPaid,
  });
  final int id;
  final String title;
  final String kind;
  final int amountPerFlatPaise;
  final String dueDate;
  final String createdAt;
  final int flatsBilled;
  final int flatsPaid;

  factory SocietyCharge.fromJson(Map<String, dynamic> j) => SocietyCharge(
        id: j['id'] as int,
        title: (j['title'] ?? '') as String,
        kind: (j['kind'] ?? '') as String,
        amountPerFlatPaise: (j['amount_per_flat_paise'] ?? 0) as int,
        dueDate: (j['due_date'] ?? '') as String,
        createdAt: (j['created_at'] ?? '') as String,
        flatsBilled: (j['flats_billed'] ?? 0) as int,
        flatsPaid: (j['flats_paid'] ?? 0) as int,
      );
}

class SocietySummary {
  const SocietySummary({
    required this.societyName,
    required this.flatCount,
    required this.months,
    required this.societyCharges,
    required this.collectedAllTimePaise,
    required this.billedAllTimePaise,
  });
  final String societyName;
  final int flatCount;
  final List<MonthSummary> months;
  final List<SocietyCharge> societyCharges;
  final int collectedAllTimePaise;
  final int billedAllTimePaise;

  factory SocietySummary.fromJson(Map<String, dynamic> j) {
    final totals = (j['totals'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
    return SocietySummary(
      societyName: (j['society_name'] ?? '') as String,
      flatCount: (j['flat_count'] ?? 0) as int,
      months: ((j['months'] as List?) ?? const [])
          .map((e) => MonthSummary.fromJson(e as Map<String, dynamic>))
          .toList(),
      societyCharges: ((j['society_charges'] as List?) ?? const [])
          .map((e) => SocietyCharge.fromJson(e as Map<String, dynamic>))
          .toList(),
      collectedAllTimePaise: (totals['collected_all_time_paise'] ?? 0) as int,
      billedAllTimePaise: (totals['billed_all_time_paise'] ?? 0) as int,
    );
  }
}

class SocietyRepository {
  SocietyRepository(this._dio);
  final Dio _dio;

  Future<SocietySummary> summary() async {
    final r = await _dio.get('/society/summary');
    return SocietySummary.fromJson(r.data as Map<String, dynamic>);
  }
}

final societyRepositoryProvider =
    Provider<SocietyRepository>((ref) => SocietyRepository(ref.watch(dioProvider)));

final societySummaryProvider = FutureProvider.autoDispose<SocietySummary>(
  (ref) => ref.watch(societyRepositoryProvider).summary(),
);
