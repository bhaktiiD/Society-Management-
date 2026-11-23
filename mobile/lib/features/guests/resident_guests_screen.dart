import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../models/models.dart';
import 'gate_pass_screen.dart';
import 'guests_repository.dart';

/// Resident view: approve or deny guests waiting at the gate.
/// Polls every few seconds so requests show up without push notifications.
class ResidentGuestsScreen extends ConsumerStatefulWidget {
  const ResidentGuestsScreen({super.key});

  @override
  ConsumerState<ResidentGuestsScreen> createState() => _ResidentGuestsScreenState();
}

class _ResidentGuestsScreenState extends ConsumerState<ResidentGuestsScreen> {
  Timer? _poll;
  final _deciding = <int>{};
  bool _showPasses = false;

  @override
  void initState() {
    super.initState();
    _poll = Timer.periodic(const Duration(seconds: 8), (_) {
      if (mounted) ref.invalidate(pendingGuestsProvider);
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _decide(GuestRequest g, bool approve) async {
    setState(() => _deciding.add(g.id));
    try {
      await ref.read(guestsRepositoryProvider).decide(g.id, approve: approve);
      if (mounted) showSnack(context, approve ? 'Guest approved' : 'Guest denied');
    } catch (error) {
      // e.g. someone else in the flat already answered (409)
      if (mounted) showSnack(context, errorMessage(error), error: true);
    } finally {
      if (mounted) {
        ref.invalidate(pendingGuestsProvider);
        ref.invalidate(guestHistoryProvider);
        setState(() => _deciding.remove(g.id));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: _ViewToggle(
            passes: _showPasses,
            onChanged: (v) => setState(() => _showPasses = v),
          ),
        ),
        Expanded(child: _showPasses ? const GatePassBody() : _approvals(context)),
      ],
    );
  }

  Widget _approvals(BuildContext context) {
    final pending = ref.watch(pendingGuestsProvider);
    final history = ref.watch(guestHistoryProvider);

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(pendingGuestsProvider);
        ref.invalidate(guestHistoryProvider);
        await refreshProvider(() => ref.read(pendingGuestsProvider.future));
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          const SectionHeader('Waiting for your approval'),
          pending.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(24),
              child: AppLoader(dotsOnly: true),
            ),
            error: (e, _) => Padding(
              padding: const EdgeInsets.all(8),
              child: Text(errorMessage(e), style: const TextStyle(color: AppColors.error)),
            ),
            data: (list) => list.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Text(
                      'No guests waiting right now.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.muted, fontSize: 16),
                    ),
                  )
                : Column(
                    children: [
                      for (final g in list)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _PendingCard(
                            guest: g,
                            busy: _deciding.contains(g.id),
                            onApprove: () => _decide(g, true),
                            onDeny: () => _decide(g, false),
                          ),
                        ),
                    ],
                  ),
          ),
          const SectionHeader('Recent visitors'),
          history.when(
            loading: () => const SizedBox.shrink(),
            error: (e, _) => const SizedBox.shrink(),
            data: (list) {
              final done = list.where((g) => g.status != 'pending').toList();
              if (done.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(8),
                  child: Text('Nothing yet.', style: TextStyle(color: AppColors.muted)),
                );
              }
              return Column(
                children: [
                  for (final g in done) ...[
                    _HistoryTile(guest: g),
                    const SizedBox(height: 10),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _PendingCard extends StatelessWidget {
  const _PendingCard({
    required this.guest,
    required this.busy,
    required this.onApprove,
    required this.onDeny,
  });
  final GuestRequest guest;
  final bool busy;
  final VoidCallback onApprove;
  final VoidCallback onDeny;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const CircleAvatar(
                  radius: 24,
                  backgroundColor: AppColors.greenTint,
                  child: Icon(Icons.person_outline, color: AppColors.greenDark),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        guest.guestName,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                      ),
                      Text(
                        [
                          'Flat ${guest.flatNumber ?? '-'}',
                          if (guest.purpose != null) guest.purpose!,
                        ].join(' · '),
                        style: const TextStyle(color: AppColors.muted, fontSize: 14),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'Expires ${formatDateTime(guest.expiresAt)}',
              style: const TextStyle(color: AppColors.muted, fontSize: 14),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: busy ? null : onDeny,
                    child: const Text('Deny'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: busy ? null : onApprove,
                    child: const Text('Approve'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.guest});
  final GuestRequest guest;

  @override
  Widget build(BuildContext context) {
    final (label, tone) = switch (guest.status) {
      'approved' => ('Approved', ChipTone.success),
      'checked_in' => ('Inside', ChipTone.info),
      'checked_out' => ('Left', ChipTone.neutral),
      'denied' => ('Denied', ChipTone.error),
      'expired' => ('Expired', ChipTone.warning),
      _ => (guest.status, ChipTone.neutral),
    };
    return TileCard(
      leading: const IconBadge(Icons.person_outline),
      title: guest.guestName,
      subtitle: formatDateTime(guest.createdAt),
      trailing: StatusChip(label, tone: tone),
    );
  }
}

/// Two equal tabs in a rounded track; a white pill slides under the selected one.
class _ViewToggle extends StatelessWidget {
  const _ViewToggle({required this.passes, required this.onChanged});
  final bool passes;
  final ValueChanged<bool> onChanged;

  Widget _tab(String label, bool selected, bool value) {
    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        excludeSemantics: true,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => onChanged(value),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    color: selected ? AppColors.greenDark : AppColors.muted,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Stack(
        children: [
          AnimatedAlign(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            alignment: passes ? Alignment.centerRight : Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: 0.5,
              heightFactor: 1,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: const [
                    BoxShadow(color: Color(0x1A000000), blurRadius: 8, offset: Offset(0, 2)),
                  ],
                ),
              ),
            ),
          ),
          Row(
            children: [
              _tab('Approvals', !passes, false),
              _tab('Gate passes', passes, true),
            ],
          ),
        ],
      ),
    );
  }
}
