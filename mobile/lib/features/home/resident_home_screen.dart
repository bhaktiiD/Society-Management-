import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../auth/auth_repository.dart';
import '../bills/bills_repository.dart';
import '../bills/bills_screen.dart';
import '../bookings/bookings_repository.dart';
import '../bookings/bookings_screen.dart';
import '../complaints/complaints_repository.dart';
import '../complaints/complaints_screen.dart';
import '../bills/invoice_screen.dart';
import '../bills/maintenance_history_screen.dart';
import '../bills/paid_maintenance_card.dart';
import '../guests/gate_pass_repository.dart';
import '../guests/gate_pass_screen.dart';
import '../society/society_history_screen.dart';
import '../society/society_repository.dart';
import '../../models/models.dart';
import '../guests/guests_repository.dart';
import '../guests/resident_guests_screen.dart';
import '../meetings/meetings_repository.dart';
import '../meetings/upcoming_meeting_section.dart';
import '../notices/notices_repository.dart';
import '../polls/active_polls_section.dart';
import '../polls/polls_repository.dart';
import '../notices/notices_screen.dart';

/// Resident home dashboard (body only; the shell draws the header).
class ResidentHomeScreen extends ConsumerWidget {
  const ResidentHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canApprove = ref.watch(meProvider).value?.canApproveGuests ?? false;

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(chargesProvider);
        ref.invalidate(pendingGuestsProvider);
        ref.invalidate(myComplaintsProvider);
        ref.invalidate(myBookingsProvider);
        ref.invalidate(noticesProvider);
        ref.invalidate(pollsProvider);
        ref.invalidate(meetingsProvider);
        ref.invalidate(gatePassesProvider);
        ref.invalidate(societySummaryProvider);
        await ref.read(chargesProvider.future).catchError((_) => <Never>[]);
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          const _BillsHero(),
          const SectionHeader('Quick actions'),
          const _QuickActions(),
          if (canApprove) const _WaitingForYou(),
          // Only appear while a poll is open / a meeting is coming up.
          const ActivePollsSection(isAdmin: false),
          const UpcomingMeetingSection(isAdmin: false),
          const _MyPayments(),
          const _NoticesSection(),
          const _SocietyHistoryCard(),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

// ---- navigation helpers

Future<void> _push(BuildContext context, WidgetRef ref, Widget page, List<FutureProvider<Object?>> refresh) async {
  await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
  for (final p in refresh) {
    ref.invalidate(p);
  }
}

Widget _titled(String title, Widget body) => Scaffold(appBar: AppBar(title: Text(title)), body: body);

Future<void> _openBills(BuildContext c, WidgetRef r) =>
    _push(c, r, _titled('Bills', const BillsScreen()), [chargesProvider]);
Future<void> _openVisitors(BuildContext c, WidgetRef r) =>
    _push(c, r, _titled('Visitors', const ResidentGuestsScreen()), [pendingGuestsProvider]);
Future<void> _openComplaints(BuildContext c, WidgetRef r) =>
    _push(c, r, const ComplaintsScreen(isAdmin: false), [myComplaintsProvider]);
Future<void> _openBookings(BuildContext c, WidgetRef r) =>
    _push(c, r, const BookingsScreen(isAdmin: false), [myBookingsProvider]);
Future<void> _openGatePass(BuildContext c, WidgetRef r) => _push(c, r, const GatePassScreen(), const []);
Future<void> _openHistory(BuildContext c, WidgetRef r) =>
    _push(c, r, const MaintenanceHistoryScreen(), [chargesProvider]);
Future<void> _openNotices(BuildContext c, WidgetRef r) =>
    _push(c, r, _titled('Notices', const NoticesScreen()), [noticesProvider]);

// ---- shared bits

class _Loading extends StatelessWidget {
  const _Loading();
  @override
  Widget build(BuildContext context) =>
      const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: AppLoader(dotsOnly: true));
}

class _Muted extends StatelessWidget {
  const _Muted(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
        child: Text(text, style: const TextStyle(fontSize: 14, color: AppColors.muted)),
      );
}

class _CouldNotLoad extends StatelessWidget {
  const _CouldNotLoad();
  @override
  Widget build(BuildContext context) => const _Muted('Could not load');
}

// ---- 1. hero

class _BillsHero extends ConsumerWidget {
  const _BillsHero();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final charges = ref.watch(chargesProvider);
    return charges.when(
      loading: () => const _Loading(),
      error: (_, _) => const _CouldNotLoad(),
      data: (list) {
        final unpaid = list.where((c) => !c.isPaid && c.balancePaise > 0).toList();
        final total = unpaid.fold<int>(0, (s, c) => s + c.balancePaise);
        final overdue = unpaid.where((c) => c.overdue).length;
        final dues = unpaid.map((c) => c.dueDate).toList()..sort();

        if (total == 0) return const PaidMaintenanceCard();

        final dueLine = overdue > 0
            // White pill + warm amber: readable on green and calm, not an alarm.
            ? Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.schedule_rounded, size: 16, color: AppColors.orange),
                      const SizedBox(width: 6),
                      Text(
                        overdue == 1 ? '1 bill overdue' : '$overdue bills overdue',
                        style: const TextStyle(fontSize: 14, color: AppColors.orange, fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                ),
              )
            : Text(
                dues.isEmpty ? 'Due now' : 'Due by ${formatDate(dues.first)}',
                style: const TextStyle(fontSize: 14, color: AppColors.ink, fontWeight: FontWeight.w700),
              );

        return HeroCard(
          label: 'Maintenance due',
          value: formatRupees(total),
          trailing: const Padding(
            padding: EdgeInsets.only(left: 12),
            child: IconBadge(Icons.currency_rupee_rounded,
                color: AppColors.greenDark, background: Colors.white, size: 52),
          ),
          footer: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              dueLine,
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                  onPressed: () => _openBills(context, ref),
                  child: const Text('Pay now'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ---- 2. waiting for you

class _WaitingForYou extends ConsumerWidget {
  const _WaitingForYou();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = ref.watch(pendingGuestsProvider);
    return pending.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (list) {
        if (list.isEmpty) return const SizedBox.shrink();
        final n = list.length;
        final first = list.first;
        final name = first.guestName;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionHeader('Waiting for you'),
            Card(
              color: AppColors.warningTint,
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => _openVisitors(context, ref),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      const IconBadge(Icons.person_add_alt_1_outlined,
                          color: AppColors.warningDark, background: Colors.white),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(n == 1 ? '1 guest waiting for approval' : '$n guests waiting for approval',
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                            const SizedBox(height: 2),
                            Text(n == 1 ? name : '$name and ${n - 1} more',
                                style: const TextStyle(fontSize: 14, color: AppColors.muted)),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right, color: AppColors.warningDark),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ---- 3. quick actions

class _QuickActions extends ConsumerWidget {
  const _QuickActions();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return QuickActionsRow(
      tiles: [
        QuickActionTile(
          icon: Icons.account_balance_wallet_rounded,
          label: 'Pay bills',
          color: AppColors.greenDark,
          gradient: AppGradients.green,
          onTap: () => _openBills(context, ref),
        ),
        QuickActionTile(
          icon: Icons.qr_code_2_rounded,
          label: 'Gate pass',
          color: AppColors.orange,
          gradient: AppGradients.orange,
          onTap: () => _openGatePass(context, ref),
        ),
        QuickActionTile(
          icon: Icons.celebration_rounded,
          label: 'Book hall',
          color: AppColors.purple,
          gradient: AppGradients.purple,
          onTap: () => _openBookings(context, ref),
        ),
        QuickActionTile(
          icon: Icons.support_agent_rounded,
          label: 'Report issue',
          color: AppColors.rose,
          gradient: AppGradients.rose,
          onTap: () => _openComplaints(context, ref),
        ),
      ],
    );
  }
}

// ---- 5. my payments

class _MyPayments extends ConsumerWidget {
  const _MyPayments();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Paid bills come from the charges already loaded; nothing extra is fetched.
    final paid = (ref.watch(chargesProvider).value ?? const <Charge>[])
        .where((c) => c.isPaid)
        .toList()
      ..sort((a, b) => b.dueDate.compareTo(a.dueDate));
    if (paid.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader('My payments', actionLabel: 'See all', onAction: () => _openHistory(context, ref)),
        for (final c in paid.take(3))
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: TileCard(
              leading: const IconBadge(Icons.receipt_long_rounded,
                  color: AppColors.teal, background: AppColors.tealTint, size: 40),
              title: c.title,
              subtitle: 'Paid - due ${formatDate(c.dueDate)}',
              trailing: Text(formatRupees(c.paidPaise > 0 ? c.paidPaise : c.amountPaise),
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              onTap: () => _push(context, ref, InvoiceScreen(chargeId: c.id), [chargesProvider]),
            ),
          ),
      ],
    );
  }
}

// ---- 7. society history

class _SocietyHistoryCard extends ConsumerWidget {
  const _SocietyHistoryCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(societySummaryProvider).asData?.value;
    void open() => _push(context, ref, const SocietyHistoryScreen(), const []);
    final billed = summary?.billedAllTimePaise ?? 0;
    final collected = summary?.collectedAllTimePaise ?? 0;
    final month = (summary?.months.isNotEmpty ?? false) ? summary!.months.first : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('Society history'),
        Card(
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: open,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const IconBadge(Icons.insights_rounded,
                          color: AppColors.purple, background: AppColors.purpleTint),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text('How the society is doing',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                      ),
                      const Icon(Icons.chevron_right, color: AppColors.muted),
                    ],
                  ),
                  if (summary != null && billed > 0) ...[
                    const SizedBox(height: 14),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: (collected / billed).clamp(0.0, 1.0),
                        minHeight: 10,
                        backgroundColor: AppColors.surface,
                        color: AppColors.green,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text('${formatRupees(collected)} collected of ${formatRupees(billed)} billed',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.muted)),
                    if (month != null) ...[
                      const SizedBox(height: 2),
                      Text('Latest month: ${month.flatsFullyPaid} of ${month.flatsBilled} flats paid',
                          style: const TextStyle(fontSize: 13, color: AppColors.muted)),
                    ],
                  ] else ...[
                    const SizedBox(height: 8),
                    const Text('Monthly collection and society charges, with no personal details.',
                        style: TextStyle(fontSize: 13, height: 1.4, color: AppColors.muted)),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ---- 6. notices

class _NoticesSection extends ConsumerWidget {
  const _NoticesSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notices = ref.watch(noticesProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader('Society notices', actionLabel: 'See all', onAction: () => _openNotices(context, ref)),
        notices.when(
          loading: () => const _Loading(),
          error: (_, _) => const _CouldNotLoad(),
          data: (list) {
            if (list.isEmpty) return const _Muted('No notices yet');
            // Stable sort keeps server order within each group.
            final pinned = list.where((n) => n.pinned);
            final rest = list.where((n) => !n.pinned);
            final top = [...pinned, ...rest].take(2);
            return Column(
              children: [
                for (final n in top)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: TileCard(
                      leading: n.pinned
                          ? const IconBadge(Icons.push_pin,
                              color: AppColors.warningDark, background: AppColors.warningTint)
                          : const IconBadge(Icons.campaign_outlined),
                      title: n.title,
                      subtitle: n.body.trim().split('\n').first,
                      trailing: n.pinned ? const StatusChip('Important', tone: ChipTone.warning) : null,
                      onTap: () => showNoticeDialog(context, n, canManage: false),
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
