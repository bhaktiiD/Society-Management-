import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';

class Meeting {
  const Meeting({
    required this.id,
    required this.title,
    required this.scheduledAt,
    required this.audience,
    required this.status,
    required this.invitedCount,
    this.agenda,
    this.location,
  });

  final int id;
  final String title;
  final String? agenda;
  final String? location;
  final DateTime scheduledAt; // UTC instant; use .toLocal() to show
  final String audience; // everyone | owners
  final String status; // upcoming | past | cancelled
  final int invitedCount;

  bool get isUpcoming => status == 'upcoming';
  bool get isCancelled => status == 'cancelled';
  bool get ownersOnly => audience == 'owners';

  factory Meeting.fromJson(Map<String, dynamic> j) => Meeting(
        id: j['id'] as int,
        title: j['title'] as String,
        agenda: j['agenda'] as String?,
        location: j['location'] as String?,
        scheduledAt: DateTime.parse(j['scheduled_at'] as String),
        audience: (j['audience'] as String?) ?? 'everyone',
        status: j['status'] as String,
        invitedCount: (j['invited_count'] as num?)?.toInt() ?? 0,
      );
}

class MeetingsRepository {
  MeetingsRepository(this._dio);
  final Dio _dio;

  List<Meeting> _parse(Response r) =>
      (r.data as List).map((e) => Meeting.fromJson(e as Map<String, dynamic>)).toList();

  Future<List<Meeting>> mine() async => _parse(await _dio.get('/meetings'));
  Future<List<Meeting>> all() async => _parse(await _dio.get('/secretary/meetings'));

  Future<void> create({
    required String title,
    String? agenda,
    String? location,
    required DateTime scheduledAt,
    required String audience,
  }) =>
      _dio.post('/secretary/meetings', data: {
        'title': title,
        'agenda': ?agenda,
        'location': ?location,
        'scheduled_at': scheduledAt.toUtc().toIso8601String(),
        'audience': audience,
      });

  Future<void> cancel(int id) => _dio.post('/secretary/meetings/$id/cancel');
}

final meetingsRepositoryProvider =
    Provider<MeetingsRepository>((ref) => MeetingsRepository(ref.watch(dioProvider)));

final meetingsProvider = FutureProvider.autoDispose<List<Meeting>>(
  (ref) => ref.watch(meetingsRepositoryProvider).mine(),
);

final adminMeetingsProvider = FutureProvider.autoDispose<List<Meeting>>(
  (ref) => ref.watch(meetingsRepositoryProvider).all(),
);
