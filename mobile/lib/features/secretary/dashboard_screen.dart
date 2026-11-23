import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../models/models.dart';
import '../bookings/bookings_repository.dart';
import '../bookings/bookings_screen.dart';
import '../complaints/complaints_repository.dart';
import '../complaints/complaints_screen.dart';
import '../meetings/meetings_repository.dart';
import '../meetings/upcoming_meeting_section.dart';
import '../notices/notices_repository.dart';
import '../polls/active_polls_section.dart';
import '../polls/polls_repository.dart';
import '../notices/notices_screen.dart';
import 'flat_detail_screen.dart';
import 'flats_screen.dart';
import 'maintenance_screen.dart';
import 'secretary_repository.dart';

/// Admin home: collections, quick actions, and a society-wide overview.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(collectionsProvider);
    return AsyncBody<Collections>(
      value: data,
      onRetry: () => ref.invalidate(collectionsProvider),
      builder: (c) => RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(collectionsProvider);
          ref.invalidate(adminComplaintsProvider);
          ref.invalidate(adminBookingsProvider);
          ref.invalidate(noticesProvider);
          ref.invalidate(adminPollsProvider);
          ref.invalidate(adminMeetingsProvider);
          await ref.read(collectionsProvider.future);
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            _CollectedCard(c),
            const SectionHeader('Quick actions'),
            const _QuickActions(),
            const _ComplaintsReminder(), // only shows when something is unresolved
            const ActivePollsSection(isAdmin: true), // only while a poll is open
            const UpcomingMeetingSection(isAdmin: true), // only when one is coming up
            const SizedBox(height: 16),
            // Four numbers, 2 x 2: identical boxes, same alignment.
            _StatGrid(stats: [
              _StatData('Flats', c.flatCount, Icons.apartment_rounded, AppColors.teal, AppColors.tealTint),
              _StatData('Residents', c.memberCount, Icons.groups_rounded, AppColors.purple, AppColors.purpleTint),
              _StatData('Bills paid', c.paid, Icons.check_circle_rounded, AppColors.greenDark, AppColors.greenTint),
              _StatData(
                'Bills pending',
                c.partial + c.outstanding,
                Icons.hourglass_bottom_rounded,
                AppColors.orange,
                AppColors.orangeTint,
              ),
            ]),
            const _ComplaintsSection(),
            const _BookingsSection(),
            const _NoticesSection(),
            const SectionHeader('Overdue flats'),
            if (c.defaulters.isEmpty)
              const Text(
                'No overdue payments 🎉',
                style: TextStyle(color: AppColors.muted, fontSize: 16, fontWeight: FontWeight.w600),
              )
            else
              for (final d in c.defaulters)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: TileCard(
                    leading: const IconBadge(
                      Icons.home_outlined,
                      color: AppColors.error,
                      background: AppColors.errorTint,
                    ),
                    title: 'Flat ${d.flatNumber ?? '-'}',
                    // The owner's name, so you know who to talk to; tap for their details.
                    subtitle: d.ownerName ?? 'No owner registered',
                    onTap: () => Navigator.of(context).push<void>(
                      MaterialPageRoute(builder: (_) => FlatDetailScreen(flatId: d.flatId)),
                    ),
                    trailing: Text(
                      formatRupees(d.overduePaise),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppColors.error,
                      ),
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

Future<void> _open(BuildContext context, Widget page) =>
    Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => page));

class _QuickActions extends ConsumerWidget {
  const _QuickActions();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Future<void> postNotice() async {
      final posted = await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => const NoticeFormScreen()),
      );
      if (posted == true) ref.invalidate(noticesProvider);
    }

    // The four things an admin reaches for most. Everything else is a section
    // below, a tab, or in Profile.
    return QuickActionsRow(
      tiles: [
        QuickActionTile(
          icon: Icons.campaign_rounded,
          label: 'Announce',
          color: AppColors.orange,
          gradient: AppGradients.orange,
          onTap: postNotice,
        ),
        QuickActionTile(
          icon: Icons.event_repeat_rounded,
          label: 'Billing',
          color: AppColors.teal,
          gradient: AppGradients.teal,
          onTap: () => _open(context, const MaintenanceScreen()),
        ),
        QuickActionTile(
          icon: Icons.support_agent_rounded,
          label: 'Complaints',
          color: AppColors.rose,
          gradient: AppGradients.rose,
          onTap: () => _open(context, const ComplaintsScreen(isAdmin: true)),
        ),
        QuickActionTile(
          icon: Icons.person_add_alt_1_rounded,
          label: 'Add resident',
          color: AppColors.purple,
          gradient: AppGradients.purple,
          onTap: () => _open(context, const InviteFormScreen()),
        ),
      ],
    );
  }
}

/// Shared loading / error / data handling so one failing section never
/// breaks the rest of the screen.
class _SectionBody<T> extends StatelessWidget {
  const _SectionBody({required this.value, required this.builder});
  final AsyncValue<T> value;
  final Widget Function(T data) builder;

  @override
  Widget build(BuildContext context) {
    return value.when(
      data: builder,
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: AppLoader(dotsOnly: true),
      ),
      error: (_, _) => const _MutedLine('Could not load'),
    );
  }
}

class _MutedLine extends StatelessWidget {
  const _MutedLine(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          text,
          style: const TextStyle(color: AppColors.muted, fontSize: 16, fontWeight: FontWeight.w600),
        ),
      );
}

const _categoryIcons = <String, IconData>{
  'plumbing': Icons.water_drop_outlined,
  'electrical': Icons.bolt_outlined,
  'lift': Icons.elevator_outlined,
  'security': Icons.shield_outlined,
  'cleaning': Icons.cleaning_services_outlined,
  'parking': Icons.local_parking_outlined,
  'noise': Icons.volume_up_outlined,
};

class _ComplaintsSection extends ConsumerWidget {
  const _ComplaintsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(adminComplaintsProvider(null));
    Future<void> openAll() async {
      await _open(context, const ComplaintsScreen(isAdmin: true));
      ref.invalidate(adminComplaintsProvider);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader('Complaints', actionLabel: 'See all', onAction: openAll),
        _SectionBody<List<Complaint>>(
          value: value,
          builder: (all) {
            final list = all.where((c) => c.status != 'resolved').toList()
              ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
            if (list.isEmpty) return const _MutedLine('No pending complaints 🎉');
            return Column(
              children: [
                for (final c in list.take(3))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: TileCard(
                      leading: IconBadge(_categoryIcons[c.category] ?? Icons.report_problem_outlined),
                      title: c.title,
                      subtitle: [
                        'Flat ${c.flatNumber ?? '-'}',
                        if (c.creatorName != null) c.creatorName!,
                        formatDate(c.createdAt),
                      ].join(' - '),
                      trailing: c.status == 'open'
                          ? const StatusChip('Open', tone: ChipTone.warning)
                          : const StatusChip('In progress', tone: ChipTone.info),
                      onTap: () => showComplaintSheet(context, c, isAdmin: true),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

const _monthNames = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

String _shortDate(String iso) {
  final d = DateTime.tryParse(iso);
  return d == null ? iso : '${d.day} ${_monthNames[d.month - 1]}';
}

class _BookingsSection extends ConsumerWidget {
  const _BookingsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(adminBookingsProvider);
    void openAll() => _open(context, const BookingsScreen(isAdmin: true));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader('Hall bookings', actionLabel: 'See all', onAction: openAll),
        _SectionBody<List<HallBooking>>(
          value: value,
          builder: (all) {
            // Requests waiting for a decision first, then confirmed bookings.
            final list = all.where((b) => b.isPending || b.confirmed).toList()
              ..sort((a, b) {
                final p = (b.isPending ? 1 : 0) - (a.isPending ? 1 : 0);
                if (p != 0) return p;
                final byDate = a.date.compareTo(b.date);
                return byDate != 0 ? byDate : (a.startTime ?? '').compareTo(b.startTime ?? '');
              });
            if (list.isEmpty) return const _MutedLine('No upcoming bookings');
            return Column(
              children: [
                for (final b in list.take(3))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: TileCard(
                      leading: b.isPending
                          ? const IconBadge(Icons.pending_actions_outlined,
                              color: AppColors.orange, background: AppColors.orangeTint)
                          : const IconBadge(Icons.event_outlined),
                      title: '${_shortDate(b.date)} - ${b.displayTime}',
                      subtitle: [
                        'Flat ${b.flatNumber ?? '-'}',
                        if (b.bookerName != null) b.bookerName!,
                      ].join(' - '),
                      trailing: b.isPending
                          ? const StatusChip('Needs decision', tone: ChipTone.warning)
                          : null,
                      onTap: () => showBookingSheet(context, b, isAdmin: true),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _NoticesSection extends ConsumerWidget {
  const _NoticesSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(noticesProvider);
    Future<void> openAll() async {
      await _open(
        context,
        Scaffold(
          appBar: AppBar(title: const Text('Notices')),
          body: const NoticesScreen(canManage: true),
        ),
      );
      ref.invalidate(noticesProvider);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader('Society notices', actionLabel: 'See all', onAction: openAll),
        _SectionBody<List<Notice>>(
          value: value,
          builder: (all) {
            final list = [...all]..sort((a, b) {
                if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
                return b.createdAt.compareTo(a.createdAt);
              });
            if (list.isEmpty) return const _MutedLine('No notices yet');
            return Column(
              children: [
                for (final n in list.take(2))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: TileCard(
                      leading: n.pinned
                          ? const IconBadge(
                              Icons.push_pin,
                              color: AppColors.warningDark,
                              background: AppColors.warningTint,
                            )
                          : const IconBadge(Icons.campaign_outlined),
                      title: n.title,
                      subtitle: formatDate(n.createdAt),
                      trailing: n.pinned ? const StatusChip('Important', tone: ChipTone.warning) : null,
                      onTap: () => showNoticeDialog(context, n, canManage: true),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// Reminder for the admin: complaints that are still open or in progress.
/// Hidden when everything is resolved. Tap to open the complaints list.
class _ComplaintsReminder extends ConsumerWidget {
  const _ComplaintsReminder();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final complaints = ref.watch(adminComplaintsProvider(null)).value;
    if (complaints == null) return const SizedBox.shrink();

    final unresolved = complaints.where((c) => c.status != 'resolved').toList();
    if (unresolved.isEmpty) return const SizedBox.shrink();

    final open = unresolved.where((c) => c.status == 'open').length;
    final inProgress = unresolved.length - open;

    // How long has the longest-waiting complaint been sitting there?
    final oldest = unresolved
        .map((c) => DateTime.tryParse(c.createdAt))
        .whereType<DateTime>()
        .fold<DateTime?>(null, (min, d) => min == null || d.isBefore(min) ? d : min);
    final days = oldest == null ? 0 : DateTime.now().difference(oldest).inDays;
    final waiting = days <= 0 ? 'oldest raised today' : 'oldest waiting $days ${days == 1 ? 'day' : 'days'}';

    final n = unresolved.length;
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Card(
        color: AppColors.warningTint,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () async {
            await Navigator.of(context).push<void>(
              MaterialPageRoute(builder: (_) => const ComplaintsScreen(isAdmin: true)),
            );
            ref.invalidate(adminComplaintsProvider);
          },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const IconBadge(
                  Icons.report_problem_outlined,
                  color: AppColors.warningDark,
                  background: Colors.white,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$n unresolved ${n == 1 ? 'complaint' : 'complaints'}',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$open open · $inProgress in progress · $waiting',
                        style: const TextStyle(fontSize: 14, height: 1.3),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CollectedCard extends StatelessWidget {
  const _CollectedCard(this.c);
  final Collections c;

  @override
  Widget build(BuildContext context) {
    final ratio = c.maintBilledPaise == 0 ? 0.0 : c.maintCollectedPaise / c.maintBilledPaise;
    return HeroCard(
      label: 'Maintenance collected',
      value: formatRupees(c.maintCollectedPaise),
      trailing: const _MoneyBadge(),
      footer: Column(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: ratio.clamp(0.0, 1.0),
              minHeight: 10,
              backgroundColor: Colors.white,
              color: AppColors.green,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Billed ${formatRupees(c.maintBilledPaise)}', style: const TextStyle(fontSize: 14)),
              Text(
                'Pending ${formatRupees(c.maintOutstandingPaise)}',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatData {
  const _StatData(this.label, this.value, this.icon, this.color, this.background);
  final String label;
  final int value;
  final IconData icon;
  final Color color;
  final Color background;
}

/// 2 x 2 grid with a fixed row height so all four boxes are identical.
class _StatGrid extends StatelessWidget {
  const _StatGrid({required this.stats});
  final List<_StatData> stats;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: stats.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        mainAxisExtent: 88,
      ),
      itemBuilder: (_, i) {
        final s = stats[i];
        return Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(color: s.background, borderRadius: BorderRadius.circular(15)),
                  child: Icon(s.icon, color: s.color, size: 26),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${s.value}', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, height: 1.1)),
                      // scaleDown keeps the label on one line even with large system text.
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          s.label,
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.muted),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}


/// Soft coin badge that gently bobs; decorative only.
class _MoneyBadge extends StatefulWidget {
  const _MoneyBadge();

  @override
  State<_MoneyBadge> createState() => _MoneyBadgeState();
}

class _MoneyBadgeState extends State<_MoneyBadge> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.of(context).disableAnimations;
    if (reduce) _c.stop();
    return ExcludeSemantics(
      child: AnimatedBuilder(
        animation: CurvedAnimation(parent: _c, curve: Curves.easeInOut),
        builder: (_, child) => Transform.translate(
          offset: Offset(0, -4 * Curves.easeInOut.transform(_c.value)),
          child: child,
        ),
        child: Container(
          width: 56,
          height: 56,
          margin: const EdgeInsets.only(left: 12),
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white,
            boxShadow: [BoxShadow(color: Color(0x1A000000), blurRadius: 10, offset: Offset(0, 4))],
          ),
          child: const Icon(Icons.currency_rupee_rounded, size: 30, color: AppColors.greenDark),
        ),
      ),
    );
  }
}
