import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import 'booking_time.dart';

export 'booking_time.dart';

class Amenity {
  Amenity({required this.id, required this.name, this.description});
  final int id;
  final String name;
  final String? description;

  factory Amenity.fromJson(Map<String, dynamic> j) =>
      Amenity(id: j['id'] as int, name: j['name'] as String, description: j['description'] as String?);
}

class DayAvailability {
  DayAvailability({
    required this.date,
    this.busy = const [],
    this.open = kOpenMin,
    this.close = kCloseMin,
  });
  final String date; // YYYY-MM-DD
  final List<TimeRange> busy; // confirmed bookings only
  final int open;
  final int close;

  factory DayAvailability.fromJson(Map<String, dynamic> j) => DayAvailability(
        date: j['date'] as String,
        busy: [
          for (final b in (j['busy'] as List? ?? const []))
            ?TimeRange.tryParse((b as Map)['start'], b['end']),
        ],
        open: parseHm(j['open'] as String?) ?? kOpenMin,
        close: parseHm(j['close'] as String?) ?? kCloseMin,
      );

  bool get isFull => fullyBooked(busy, open: open, close: close);
  bool get isFree => busy.isEmpty;
}

class HallBooking {
  HallBooking({
    required this.id,
    required this.date,
    required this.status,
    this.startTime,
    this.endTime,
    this.timeLabel,
    this.purpose,
    this.amenityName,
    this.flatNumber,
    this.bookerName,
    this.bookerKind,
    this.bookerPhone,
    this.adminNote,
    this.createdAt,
    this.slotTaken = false,
  });
  final int id;
  final String date;
  final String? startTime; // HH:MM
  final String? endTime;
  final String? timeLabel;
  final String status;
  final String? purpose;
  final String? amenityName;
  final String? flatNumber;
  final String? bookerName;
  final String? bookerKind; // 'owner' | 'tenant' | null
  final String? bookerPhone;
  final String? adminNote;
  final String? createdAt;
  final bool slotTaken;

  bool get confirmed => status == 'confirmed';
  bool get isPending => status == 'pending';
  bool get needsReschedule => status == 'reschedule';

  /// Server label, or one built from start/end when it is missing.
  String get displayTime {
    final l = (timeLabel ?? '').trim();
    if (l.isNotEmpty) return l;
    return TimeRange.tryParse(startTime, endTime)?.label ?? '';
  }

  factory HallBooking.fromJson(Map<String, dynamic> j) => HallBooking(
        id: j['id'] as int,
        date: j['date'] as String,
        startTime: j['start_time'] as String?,
        endTime: j['end_time'] as String?,
        timeLabel: j['time_label'] as String?,
        status: j['status'] as String,
        purpose: j['purpose'] as String?,
        amenityName: j['amenity_name'] as String?,
        flatNumber: j['flat_number'] as String?,
        bookerName: j['booker_name'] as String?,
        bookerKind: j['booker_kind'] as String?,
        bookerPhone: j['booker_phone'] as String?,
        adminNote: j['admin_note'] as String?,
        createdAt: j['created_at'] as String?,
        slotTaken: j['slot_taken'] == true,
      );
}

class BookingsRepository {
  BookingsRepository(this._dio);
  final Dio _dio;

  Future<Amenity> hall() async {
    final r = await _dio.get('/amenities');
    final list = (r.data as List).map((e) => Amenity.fromJson(e as Map<String, dynamic>)).toList();
    if (list.isEmpty) throw StateError('No hall available');
    return list.first;
  }

  Future<List<DayAvailability>> availability(int amenityId, {int days = 14}) async {
    final r = await _dio.get('/amenities/$amenityId/availability', queryParameters: {'days': days});
    return (r.data as List).map((e) => DayAvailability.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<HallBooking>> mine() async {
    final r = await _dio.get('/bookings/mine');
    return (r.data as List).map((e) => HallBooking.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<HallBooking>> adminUpcoming() async {
    final r = await _dio.get('/secretary/bookings');
    return (r.data as List).map((e) => HallBooking.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> book({
    required int amenityId,
    required String date,
    required String startTime,
    required String endTime,
    String? purpose,
    int? replacesBookingId,
  }) =>
      _dio.post('/bookings', data: {
        'amenity_id': amenityId,
        'date': date,
        'start_time': startTime,
        'end_time': endTime,
        if (purpose != null && purpose.isNotEmpty) 'purpose': purpose,
        'replaces_booking_id': ?replacesBookingId,
      });

  Future<void> cancelMine(int id) => _dio.delete('/bookings/$id');

  Future<void> adminCancel(int id) => _dio.post('/secretary/bookings/$id/cancel');

  Future<void> approve(int id) => _dio.post('/secretary/bookings/$id/approve');

  Future<void> reschedule(int id, {String? note}) => _dio.post('/secretary/bookings/$id/reschedule',
      data: {if (note != null && note.trim().isNotEmpty) 'note': note.trim()});

  Future<void> decline(int id, String reason) =>
      _dio.post('/secretary/bookings/$id/decline', data: {'reason': reason.trim()});
}

final bookingsRepositoryProvider =
    Provider<BookingsRepository>((ref) => BookingsRepository(ref.watch(dioProvider)));

final hallProvider = FutureProvider.autoDispose<Amenity>(
  (ref) => ref.watch(bookingsRepositoryProvider).hall(),
);

final availabilityProvider = FutureProvider.autoDispose<List<DayAvailability>>((ref) async {
  final hall = await ref.watch(hallProvider.future);
  return ref.watch(bookingsRepositoryProvider).availability(hall.id);
});

final myBookingsProvider = FutureProvider.autoDispose<List<HallBooking>>(
  (ref) => ref.watch(bookingsRepositoryProvider).mine(),
);

final adminBookingsProvider = FutureProvider.autoDispose<List<HallBooking>>(
  (ref) => ref.watch(bookingsRepositoryProvider).adminUpcoming(),
);
