import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'poll_form_screen.dart';
import 'poll_widgets.dart';
import 'polls_repository.dart';

class PollsScreen extends ConsumerWidget {
  const PollsScreen({super.key, required this.isAdmin});
  final bool isAdmin;

  FutureProvider<List<Poll>> get _provider => isAdmin ? adminPollsProvider : pollsProvider;

  Future<void> _newPoll(BuildContext context, WidgetRef ref) async {
    final created = await Navigator.of(context)
        .push<bool>(MaterialPageRoute(builder: (_) => const PollFormScreen()));
    if (created == true) {
      ref.invalidate(adminPollsProvider);
      if (context.mounted) showSnack(context, 'Poll published');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(_provider);
    return Scaffold(
      appBar: AppBar(title: const Text('Polls')),
      floatingActionButton: isAdmin
          ? FloatingActionButton.extended(
              onPressed: () => _newPoll(context, ref),
              icon: const Icon(Icons.add),
              label: const Text('New poll'),
            )
          : null,
      body: AsyncBody<List<Poll>>(
        value: value,
        onRetry: () => ref.invalidate(_provider),
        builder: (polls) {
          Future<void> refresh() async {
            ref.invalidate(_provider);
            await refreshProvider(() => ref.read(_provider.future));
          }

          if (polls.isEmpty) {
            return RefreshIndicator(
              onRefresh: refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 120),
                  EmptyState(icon: Icons.poll_outlined, message: 'No polls right now'),
                ],
              ),
            );
          }
          final open = polls.where((p) => p.isOpen).toList();
          final past = polls.where((p) => !p.isOpen).toList();
          return RefreshIndicator(
            onRefresh: refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(16, 0, 16, isAdmin ? 96 : 24),
              children: [
                if (open.isNotEmpty) const SectionHeader('Open polls'),
                for (final p in open) _PollCard(key: ValueKey(p.id), poll: p, isAdmin: isAdmin),
                if (past.isNotEmpty) const SectionHeader('Past polls'),
                for (final p in past) _PollCard(key: ValueKey(p.id), poll: p, isAdmin: isAdmin),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _PollCard extends ConsumerStatefulWidget {
  const _PollCard({super.key, required this.poll, required this.isAdmin});
  final Poll poll;
  final bool isAdmin;

  @override
  ConsumerState<_PollCard> createState() => _PollCardState();
}

class _PollCardState extends ConsumerState<_PollCard> {
  bool _closing = false;

  Future<void> _close() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: const Text('Close this poll now? Residents will no longer be able to vote.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Close poll')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _closing = true);
    try {
      await ref.read(pollsRepositoryProvider).close(widget.poll.id);
      ref.invalidate(adminPollsProvider);
      ref.invalidate(pollsProvider);
    } catch (e) {
      if (!mounted) return;
      setState(() => _closing = false);
      showSnack(context, errorMessage(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.poll;
    final admin = widget.isAdmin;
    final Widget body;
    if (admin) {
      final frac = p.eligibleCount > 0 ? (p.totalVotes / p.eligibleCount).clamp(0.0, 1.0) : 0.0;
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PollResults(poll: p, showTurnout: false),
          ProgressBar(value: frac),
          const SizedBox(height: 6),
          Text('${p.totalVotes} of ${p.eligibleCount} voted',
              style: const TextStyle(fontSize: 13, color: AppColors.muted)),
          if (p.isOpen)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: _closing ? null : _close,
                child: _closing
                    ? const SizedBox(
                        width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Close poll'),
              ),
            ),
        ],
      );
    } else if (p.isOpen && p.canVote) {
      body = VoteNowButton(onPressed: () => showVoteSheet(context, p));
    } else if (p.hasResults) {
      body = PollResults(poll: p);
    } else if (!p.eligible) {
      body = const _Note('Only owners can vote in this poll.');
    } else {
      body = const SizedBox.shrink();
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PollHeader(poll: p, isAdmin: admin),
            if (p.isOpen && !admin && p.canVote || admin || p.hasResults || !p.eligible) ...[
              const SizedBox(height: 14),
              const Divider(height: 1),
              const SizedBox(height: 14),
              body,
            ],
          ],
        ),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12)),
        child: Row(
          children: [
            const Icon(Icons.info_outline, size: 18, color: AppColors.muted),
            const SizedBox(width: 8),
            Expanded(child: Text(text, style: const TextStyle(fontSize: 14, color: AppColors.muted))),
          ],
        ),
      );
}
