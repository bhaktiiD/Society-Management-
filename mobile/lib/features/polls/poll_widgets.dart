import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'polls_repository.dart';

/// The voting popup: title, description and the options. Options are only
/// ever shown here, never directly on a poll card.
Future<void> showVoteSheet(BuildContext context, Poll poll) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Colors.white,
    builder: (sheet) => Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(sheet).bottom),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(poll.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            if ((poll.description ?? '').trim().isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(poll.description!,
                  style: const TextStyle(fontSize: 14, height: 1.4, color: AppColors.muted)),
            ],
            const SizedBox(height: 4),
            Text(pollTimeText(poll), style: const TextStyle(fontSize: 13, color: AppColors.muted)),
            const SizedBox(height: 14),
            VotePicker(poll: poll, onVoted: () => Navigator.of(sheet).pop()),
          ],
        ),
      ),
    ),
  );
}

/// Selectable options + "Submit vote". Used inside [showVoteSheet].
class VotePicker extends ConsumerStatefulWidget {
  const VotePicker({super.key, required this.poll, this.onVoted});
  final Poll poll;
  final VoidCallback? onVoted;

  @override
  ConsumerState<VotePicker> createState() => _VotePickerState();
}

class _VotePickerState extends ConsumerState<VotePicker> {
  int? _selected;
  bool _sending = false;

  Future<void> _submit() async {
    final choice = _selected;
    if (choice == null || _sending) return;
    setState(() => _sending = true);
    try {
      await ref.read(pollsRepositoryProvider).vote(widget.poll.id, choice);
      ref.invalidate(pollsProvider);
      if (!mounted) return;
      showSnack(context, 'Your vote is in');
      widget.onVoted?.call();
    } catch (e) {
      if (e is DioException && e.response?.statusCode == 409) {
        ref.invalidate(pollsProvider); // already voted: just refresh
        if (mounted) widget.onVoted?.call();
        return;
      }
      if (!mounted) return;
      setState(() => _sending = false);
      showSnack(context, errorMessage(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final o in widget.poll.options)
          Semantics(
            inMutuallyExclusiveGroup: true,
            checked: _selected == o.id,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: _sending ? null : () => setState(() => _selected = o.id),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                  child: Row(
                    children: [
                      Icon(
                        _selected == o.id
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked,
                        color: _selected == o.id ? AppColors.greenDark : AppColors.inputBorder,
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: Text(o.text, style: const TextStyle(fontSize: 15))),
                    ],
                  ),
                ),
              ),
            ),
          ),
        const SizedBox(height: 10),
        FilledButton(
          style: _voteButtonStyle,
          onPressed: _selected == null || _sending ? null : _submit,
          child: _sending
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                )
              : const Text('Cast my vote'),
        ),
      ],
    );
  }
}

/// Full-width green "Vote now" with a white label, used on every poll card.
class VoteNowButton extends StatelessWidget {
  const VoteNowButton({super.key, required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: onPressed,
        style: _voteButtonStyle,
        icon: const Icon(Icons.how_to_vote_rounded, size: 20),
        label: const Text('Vote now'),
      ),
    );
  }
}

final _voteButtonStyle = FilledButton.styleFrom(
  backgroundColor: AppColors.green,
  foregroundColor: Colors.white,
  minimumSize: const Size.fromHeight(52),
  padding: const EdgeInsets.symmetric(horizontal: 20),
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
  textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
);

/// Top of every poll card (home + polls page): icon, title, one-line description
/// and a status chip, then a muted meta row (who can vote, when it closes).
class PollHeader extends StatelessWidget {
  const PollHeader({super.key, required this.poll, required this.isAdmin});
  final Poll poll;
  final bool isAdmin;

  @override
  Widget build(BuildContext context) {
    final desc = (poll.description ?? '').trim();
    final StatusChip chip;
    if (!poll.isOpen) {
      chip = const StatusChip('Closed', tone: ChipTone.neutral);
    } else if (!isAdmin && poll.hasVoted) {
      chip = const StatusChip('You voted', tone: ChipTone.success);
    } else {
      chip = const StatusChip('Open', tone: ChipTone.success);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const IconBadge(Icons.how_to_vote_rounded,
                color: AppColors.purple, background: AppColors.purpleTint),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(poll.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, height: 1.25)),
                  if (desc.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(desc,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13, height: 1.35, color: AppColors.muted)),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            chip,
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 16,
          runSpacing: 4,
          children: [
            _Meta(Icons.groups_2_outlined, poll.ownersOnly ? 'Owners only' : 'Owners and tenants'),
            _Meta(Icons.schedule_rounded, pollTimeText(poll)),
          ],
        ),
      ],
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta(this.icon, this.text);
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: AppColors.muted),
          const SizedBox(width: 6),
          Flexible(child: Text(text, style: const TextStyle(fontSize: 13, color: AppColors.muted))),
        ],
      );
}

/// Horizontal result bars + "N of M have voted".
class PollResults extends StatelessWidget {
  const PollResults({super.key, required this.poll, this.showTurnout = true});
  final Poll poll;
  final bool showTurnout;

  @override
  Widget build(BuildContext context) {
    final total = poll.totalVotes;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final o in poll.options) _bar(o, total),
        if (showTurnout) ...[
          const SizedBox(height: 4),
          Text('$total of ${poll.eligibleCount} have voted',
              style: const TextStyle(fontSize: 13, color: AppColors.muted)),
        ],
      ],
    );
  }

  Widget _bar(PollOption o, int total) {
    final votes = o.votes ?? 0;
    final frac = total > 0 ? (votes / total).clamp(0.0, 1.0) : 0.0;
    final mine = poll.myOptionId == o.id;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (mine) ...[
                const Icon(Icons.check_circle, size: 18, color: AppColors.greenDark),
                const SizedBox(width: 6),
              ],
              Expanded(
                child: Text(o.text,
                    style: TextStyle(fontSize: 14, fontWeight: mine ? FontWeight.w800 : FontWeight.w600)),
              ),
              const SizedBox(width: 8),
              Text('$votes · ${(frac * 100).round()}%',
                  style: const TextStyle(fontSize: 13, color: AppColors.muted)),
            ],
          ),
          if (mine)
            const Text('Your vote',
                style: TextStyle(fontSize: 12, color: AppColors.greenDark, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          ProgressBar(value: frac, strong: mine),
        ],
      ),
    );
  }
}

class ProgressBar extends StatelessWidget {
  const ProgressBar({super.key, required this.value, this.strong = true});
  final double value;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: LinearProgressIndicator(
        value: value,
        minHeight: 10,
        backgroundColor: AppColors.surface,
        color: strong ? AppColors.green : const Color(0xFFB5E88A),
      ),
    );
  }
}
