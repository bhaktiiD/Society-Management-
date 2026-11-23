import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';

class Complaint {
  const Complaint({
    required this.id,
    required this.category,
    required this.title,
    required this.description,
    required this.status,
    required this.createdAt,
    this.adminNote,
    this.flatNumber,
    this.resolvedAt,
    this.creatorName,
    this.creatorEmail,
  });

  final int id;
  final String category;
  final String title;
  final String description;
  final String status; // open | in_progress | resolved
  final String? adminNote;
  final String? flatNumber;
  final String createdAt;
  final String? resolvedAt;
  final String? creatorName; // admin list only
  final String? creatorEmail; // admin list only

  factory Complaint.fromJson(Map<String, dynamic> j) => Complaint(
        id: j['id'] as int,
        category: j['category'] as String,
        title: j['title'] as String,
        description: j['description'] as String,
        status: j['status'] as String,
        adminNote: j['admin_note'] as String?,
        flatNumber: j['flat_number'] as String?,
        createdAt: j['created_at'] as String,
        resolvedAt: j['resolved_at'] as String?,
        creatorName: j['created_by_name'] as String?,
        creatorEmail: j['created_by_email'] as String?,
      );
}

class ComplaintsRepository {
  ComplaintsRepository(this._dio);
  final Dio _dio;

  List<Complaint> _parse(Response r) =>
      (r.data as List).map((e) => Complaint.fromJson(e as Map<String, dynamic>)).toList();

  Future<List<Complaint>> mine() async => _parse(await _dio.get('/complaints'));

  Future<List<Complaint>> all({String? status}) async => _parse(await _dio.get(
        '/secretary/complaints',
        queryParameters: {'status': ?status},
      ));

  Future<void> create({
    required String category,
    required String title,
    required String description,
  }) =>
      _dio.post('/complaints',
          data: {'category': category, 'title': title, 'description': description});

  Future<void> update(int id, {required String status, String? note}) =>
      _dio.patch('/secretary/complaints/$id',
          data: {'status': status, 'admin_note': ?note});
}

final complaintsRepositoryProvider =
    Provider<ComplaintsRepository>((ref) => ComplaintsRepository(ref.watch(dioProvider)));

final myComplaintsProvider = FutureProvider.autoDispose<List<Complaint>>(
  (ref) => ref.watch(complaintsRepositoryProvider).mine(),
);

/// Admin list; the family argument is the status filter (null = all).
final adminComplaintsProvider =
    FutureProvider.autoDispose.family<List<Complaint>, String?>(
  (ref, status) => ref.watch(complaintsRepositoryProvider).all(status: status),
);
