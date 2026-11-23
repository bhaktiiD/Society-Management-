import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'poll_widgets.dart';
import 'polls_repository.dart';
import 'polls_screen.dart';

/// Home-screen block: up to 2 open polls. Renders nothing while loading, on
/// error, or when no poll is open.
class ActivePollsSection extends ConsumerWidget {
  const ActivePollsSection({super.key, required this.isAdmin});
  final bool isAdmin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final polls = (isAdmin ? ref.watch(adminPollsProvider) : ref.watch(pollsProvider)).asData?.value;
    final open = (polls ?? const <Poll>[]).where((p) => p.isOpen).take(2).toList();
    if (open.isEmpty) return const SizedBox.shrink();

    void openAll() => Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => PollsScreen(isAdmin: isAdmin)));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader('Polls', actionLabel: 'See all', onAction: openAll),
        for (final p in open) _HomePollCard(poll: p, isAdmin: isAdmin, onOpen: openAll),
      ],
    );
  }
}

class _HomePollCard extends StatefulWidget {
  const _HomePollCard({required this.poll, required this.isAdmin, required this.onOpen});
  final Poll poll;
  final bool isAdmin;
  final VoidCallback onOpen;

  @override
  State<_HomePollCard> createState() => _HomePollCardState();
}

/// Collapsed: title, short description and the turnout ring. Tap to expand and
/// see who can vote, the options and the vote button.
class _HomePollCardState extends State<_HomePollCard> {
  bool _open = false;

  void _toggle() {
    setState(() => _open = !_open);
    if (!_open) return;
    // Once the panel has finished opening, scroll so the whole card is on screen.
    Future<void>.delayed(const Duration(milliseconds: 260), () {
      if (!mounted) return;
      Scrollable.ensureVisible(
        context,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
        alignment: 0.05,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final poll = widget.poll;
    final desc = (poll.description ?? '').trim();
    final turnout = poll.eligibleCount > 0 ? (poll.totalVotes / poll.eligibleCount).clamp(0.0, 1.0) : 0.0;

    final Widget body;
    if (widget.isAdmin || poll.hasResults) {
      body = PollResults(poll: poll);
    } else if (poll.canVote) {
      body = VotePicker(poll: poll, onVoted: () => setState(() => _open = false));
    } else {
      body = const Text('Only owners can vote in this poll.',
          style: TextStyle(fontSize: 13, color: AppColors.muted));
    }

    final hint = widget.isAdmin
        ? '${poll.totalVotes} of ${poll.eligibleCount} voted'
        : poll.canVote
            ? 'Tap to cast your vote'
            : poll.hasVoted
                ? 'You voted. Tap to see results'
                : 'Tap for details';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: AppGradients.purple,
        ),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(24),
              onTap: _toggle,
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(poll.title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, height: 1.25)),
                              if (desc.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(desc,
                                    maxLines: _open ? 4 : 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 13, height: 1.35, color: AppColors.ink)),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 14),
                        _TurnoutRing(value: turnout),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: Text(hint,
                              style: const TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.purple)),
                        ),
                        AnimatedRotation(
                          turns: _open ? 0.5 : 0,
                          duration: const Duration(milliseconds: 200),
                          child: const Icon(Icons.expand_more_rounded, color: AppColors.purple),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              alignment: Alignment.topCenter,
              child: _open
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.85),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.schedule_rounded, size: 16, color: AppColors.muted),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    '${poll.ownersOnly ? 'Owners only' : 'Owners and tenants'} · ${pollTimeText(poll)}',
                                    style: const TextStyle(fontSize: 13, color: AppColors.muted),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            body,
                            Align(
                              alignment: Alignment.centerLeft,
                              child: TextButton(
                                onPressed: widget.onOpen,
                                style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 40)),
                                child: const Text('See all polls'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : const SizedBox(width: double.infinity),
            ),
          ],
        ),
      ),
    );
  }
}

/// Turnout so far, as a small ring with the percentage inside.
class _TurnoutRing extends StatelessWidget {
  const _TurnoutRing({required this.value});
  final double value;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: SizedBox(
        width: 58,
        height: 58,
        child: Stack(
          alignment: Alignment.center,
          children: [
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: value == 0 ? 0.03 : value),
              duration: const Duration(milliseconds: 700),
              curve: Curves.easeOutCubic,
              builder: (_, v, _) => SizedBox(
                width: 58,
                height: 58,
                child: CircularProgressIndicator(
                  value: v,
                  strokeWidth: 6,
                  strokeCap: StrokeCap.round,
                  backgroundColor: Colors.white.withValues(alpha: 0.8),
                  color: AppColors.purple,
                ),
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${(value * 100).round()}%',
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.purple, height: 1)),
                const Text('voted',
                    style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: AppColors.purple)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
