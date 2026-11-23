import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'meeting_form_screen.dart';
import 'meeting_widgets.dart';
import 'meetings_repository.dart';

class MeetingsScreen extends ConsumerWidget {
  const MeetingsScreen({super.key, required this.isAdmin});
  final bool isAdmin;

  Future<void> _schedule(BuildContext context, WidgetRef ref) async {
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const MeetingFormScreen()),
    );
    if (ok == true && context.mounted) {
      ref.invalidate(adminMeetingsProvider);
      ref.invalidate(meetingsProvider);
      showSnack(context, 'Meeting scheduled');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = isAdmin ? adminMeetingsProvider : meetingsProvider;
    final value = ref.watch(provider);
    return Scaffold(
      appBar: AppBar(title: const Text('Meetings')),
      floatingActionButton: isAdmin
          ? FloatingActionButton.extended(
              onPressed: () => _schedule(context, ref),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Schedule meeting', style: TextStyle(fontWeight: FontWeight.w800)),
            )
          : null,
      body: AsyncBody<List<Meeting>>(
        value: value,
        onRetry: () => ref.invalidate(provider),
        builder: (meetings) {
          final upcoming = meetings.where((m) => m.isUpcoming).toList()
            ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
          final earlier = meetings.where((m) => !m.isUpcoming).toList()
            ..sort((a, b) => b.scheduledAt.compareTo(a.scheduledAt));
          return RefreshIndicator(
            onRefresh: () => refreshProvider(() => ref.refresh(provider.future)),
            child: meetings.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: const [
                      SizedBox(height: 120),
                      EmptyState(
                        icon: Icons.event_outlined,
                        message: 'No meetings scheduled\nWhen a meeting is planned, it will show up here.',
                      ),
                    ],
                  )
                : ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                    children: [
                      if (upcoming.isNotEmpty) ...[
                        const SectionHeader('Upcoming'),
                        for (final m in upcoming) _MeetingCard(m, isAdmin: isAdmin),
                      ],
                      if (earlier.isNotEmpty) ...[
                        const SectionHeader('Earlier'),
                        for (final m in earlier) _MeetingCard(m, isAdmin: isAdmin),
                      ],
                    ],
                  ),
          );
        },
      ),
    );
  }
}

class _MeetingCard extends StatelessWidget {
  const _MeetingCard(this.meeting, {required this.isAdmin});
  final Meeting meeting;
  final bool isAdmin;

  @override
  Widget build(BuildContext context) {
    final m = meeting;
    final muted = !m.isUpcoming;
    final agenda = m.agenda?.trim() ?? '';
    final location = m.location?.trim() ?? '';
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => showMeetingSheet(context, m, isAdmin: isAdmin),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DateBlock(m.scheduledAt, muted: muted),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        m.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: muted ? AppColors.muted : AppColors.ink,
                          decoration: m.isCancelled ? TextDecoration.lineThrough : null,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(weekdayTime(m.scheduledAt),
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.muted)),
                      if (location.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            const Icon(Icons.place_outlined, size: 16, color: AppColors.muted),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(location,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 14, color: AppColors.muted)),
                            ),
                          ],
                        ),
                      ],
                      if (agenda.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(agenda,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 14, color: AppColors.ink)),
                      ],
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          if (m.isCancelled) const StatusChip('Cancelled', tone: ChipTone.error),
                          Text(audienceTag(m.audience),
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.muted)),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Opens one meeting's detail popup (date, place, full agenda, who is invited).
Future<void> showMeetingSheet(BuildContext context, Meeting meeting, {required bool isAdmin}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    builder: (_) => _MeetingSheet(meeting: meeting, isAdmin: isAdmin),
  );
}

class _MeetingSheet extends ConsumerStatefulWidget {
  const _MeetingSheet({required this.meeting, required this.isAdmin});
  final Meeting meeting;
  final bool isAdmin;

  @override
  ConsumerState<_MeetingSheet> createState() => _MeetingSheetState();
}

class _MeetingSheetState extends ConsumerState<_MeetingSheet> {
  bool _busy = false;

  Future<void> _cancel() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel meeting'),
        content: const Text('Cancel this meeting? Everyone invited will be told.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep it')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Cancel meeting'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    setState(() => _busy = true);
    try {
      await ref.read(meetingsRepositoryProvider).cancel(widget.meeting.id);
      ref.invalidate(adminMeetingsProvider);
      ref.invalidate(meetingsProvider);
      if (!mounted) return;
      nav.pop();
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Meeting cancelled'), backgroundColor: AppColors.ink));
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      showSnack(context, errorMessage(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.meeting;
    final agenda = m.agenda?.trim() ?? '';
    final location = m.location?.trim() ?? '';
    final who = m.ownersOnly ? 'Owners only are invited.' : 'All owners and tenants are invited.';
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (m.isCancelled) ...[
              const StatusChip('Cancelled', tone: ChipTone.error),
              const SizedBox(height: 8),
            ],
            Text(m.title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 14),
            _Row(Icons.schedule_rounded, fullWhen(m.scheduledAt)),
            if (location.isNotEmpty) _Row(Icons.place_outlined, location),
            _Row(Icons.groups_outlined, widget.isAdmin ? '$who ${m.invitedCount} people invited.' : who),
            const SizedBox(height: 14),
            const Text('Agenda', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.muted)),
            const SizedBox(height: 4),
            Text(agenda.isEmpty ? 'No agenda added.' : agenda, style: const TextStyle(fontSize: 15, height: 1.4)),
            if (widget.isAdmin && m.isUpcoming) ...[
              const SizedBox(height: 24),
              OutlinedButton.icon(
                onPressed: _busy ? null : _cancel,
                icon: _busy
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.event_busy_outlined),
                label: const Text('Cancel meeting'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.error,
                  side: const BorderSide(color: AppColors.error, width: 2),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.icon, this.text);
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: AppColors.greenDark),
            const SizedBox(width: 10),
            Expanded(child: Text(text, style: const TextStyle(fontSize: 15, height: 1.3))),
          ],
        ),
      );
}
