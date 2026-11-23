import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';

class SocietyContact {
  const SocietyContact({
    required this.id,
    required this.name,
    required this.label,
    required this.phone,
    required this.category,
    required this.sortOrder,
  });

  final int id;
  final String name;
  final String? label;
  final String phone;
  final String category; // emergency | staff | service
  final int sortOrder;

  factory SocietyContact.fromJson(Map<String, dynamic> j) => SocietyContact(
        id: j['id'] as int,
        name: j['name'] as String,
        label: j['label'] as String?,
        phone: j['phone'] as String,
        category: j['category'] as String,
        sortOrder: (j['sort_order'] as int?) ?? 0,
      );
}

class ContactsRepository {
  ContactsRepository(this._dio);
  final Dio _dio;

  Future<List<SocietyContact>> list() async {
    final r = await _dio.get('/contacts');
    return (r.data as List)
        .map((e) => SocietyContact.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Map<String, dynamic> _body(String name, String? label, String phone, String category) => {
        'name': name,
        'label': (label == null || label.isEmpty) ? null : label,
        'phone': phone,
        'category': category,
      };

  Future<void> create({
    required String name,
    String? label,
    required String phone,
    required String category,
  }) =>
      _dio.post('/secretary/contacts', data: _body(name, label, phone, category));

  Future<void> update(
    int id, {
    required String name,
    String? label,
    required String phone,
    required String category,
    int sortOrder = 0,
  }) =>
      _dio.put('/secretary/contacts/$id',
          data: {..._body(name, label, phone, category), 'sort_order': sortOrder});

  Future<void> delete(int id) => _dio.delete('/secretary/contacts/$id');
}

final contactsRepositoryProvider =
    Provider<ContactsRepository>((ref) => ContactsRepository(ref.watch(dioProvider)));

final contactsProvider = FutureProvider.autoDispose<List<SocietyContact>>(
  (ref) => ref.watch(contactsRepositoryProvider).list(),
);
