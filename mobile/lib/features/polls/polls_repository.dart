import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';

class PollOption {
  const PollOption({required this.id, required this.text, this.votes});
  final int id;
  final String text;
  final int? votes; // null until the caller has voted or the poll is closed

  factory PollOption.fromJson(Map<String, dynamic> j) => PollOption(
        id: j['id'] as int,
        text: j['text'] as String,
        votes: j['votes'] as int?,
      );
}

class Poll {
  const Poll({
    required this.id,
    required this.title,
    this.description,
    required this.audience,
    required this.status,
    required this.createdAt,
    required this.closesAt,
    this.closedAt,
    required this.eligible,
    required this.canVote,
    required this.hasVoted,
    this.myOptionId,
    required this.totalVotes,
    required this.eligibleCount,
    required this.options,
  });

  final int id;
  final String title;
  final String? description;
  final String audience; // everyone | owners
  final String status; // open | closed
  final String createdAt;
  final String closesAt;
  final String? closedAt;
  final bool eligible;
  final bool canVote;
  final bool hasVoted;
  final int? myOptionId;
  final int totalVotes;
  final int eligibleCount;
  final List<PollOption> options;

  bool get isOpen => status == 'open';
  bool get ownersOnly => audience == 'owners';
  bool get hasResults => options.isNotEmpty && options.every((o) => o.votes != null);

  factory Poll.fromJson(Map<String, dynamic> j) => Poll(
        id: j['id'] as int,
        title: j['title'] as String,
        description: j['description'] as String?,
        audience: (j['audience'] as String?) ?? 'everyone',
        status: j['status'] as String,
        createdAt: (j['created_at'] as String?) ?? '',
        closesAt: j['closes_at'] as String,
        closedAt: j['closed_at'] as String?,
        eligible: (j['eligible'] as bool?) ?? false,
        canVote: (j['can_vote'] as bool?) ?? false,
        hasVoted: (j['has_voted'] as bool?) ?? false,
        myOptionId: j['my_option_id'] as int?,
        totalVotes: (j['total_votes'] as int?) ?? 0,
        eligibleCount: (j['eligible_count'] as int?) ?? 0,
        options: ((j['options'] as List?) ?? const [])
            .map((e) => PollOption.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

/// "Closes in 2 days" / "Closes today" / "Closed 3 days ago".
String pollTimeText(Poll p, [DateTime? now]) {
  final today = now ?? DateTime.now();
  final iso = p.isOpen ? p.closesAt : (p.closedAt ?? p.closesAt);
  final d = DateTime.tryParse(iso)?.toLocal();
  if (d == null) return p.isOpen ? 'Open' : 'Closed';
  final days = DateTime.utc(d.year, d.month, d.day)
      .difference(DateTime.utc(today.year, today.month, today.day))
      .inDays;
  if (p.isOpen) {
    if (days <= 0) return 'Closes today';
    if (days == 1) return 'Closes tomorrow';
    return 'Closes in $days days';
  }
  final ago = -days;
  if (ago <= 0) return 'Closed today';
  if (ago == 1) return 'Closed yesterday';
  return 'Closed $ago days ago';
}

class PollsRepository {
  PollsRepository(this._dio);
  final Dio _dio;

  List<Poll> _parse(Response r) =>
      (r.data as List).map((e) => Poll.fromJson(e as Map<String, dynamic>)).toList();

  Future<List<Poll>> mine() async => _parse(await _dio.get('/polls'));
  Future<List<Poll>> all() async => _parse(await _dio.get('/secretary/polls'));

  Future<Poll> vote(int pollId, int optionId) async {
    final r = await _dio.post('/polls/$pollId/vote', data: {'option_id': optionId});
    return Poll.fromJson(r.data as Map<String, dynamic>);
  }

  Future<Poll> create({
    required String title,
    String? description,
    required String audience,
    required List<String> options,
    required String closesAtUtcIso,
  }) async {
    final r = await _dio.post('/secretary/polls', data: {
      'title': title,
      'description': ?description,
      'audience': audience,
      'options': options,
      'closes_at': closesAtUtcIso,
    });
    return Poll.fromJson(r.data as Map<String, dynamic>);
  }

  Future<Poll> close(int id) async {
    final r = await _dio.post('/secretary/polls/$id/close');
    return Poll.fromJson(r.data as Map<String, dynamic>);
  }
}

final pollsRepositoryProvider =
    Provider<PollsRepository>((ref) => PollsRepository(ref.watch(dioProvider)));

final pollsProvider = FutureProvider.autoDispose<List<Poll>>(
  (ref) => ref.watch(pollsRepositoryProvider).mine(),
);

final adminPollsProvider = FutureProvider.autoDispose<List<Poll>>(
  (ref) => ref.watch(pollsRepositoryProvider).all(),
);
