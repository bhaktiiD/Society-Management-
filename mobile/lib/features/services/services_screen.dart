import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../bookings/bookings_screen.dart';
import '../complaints/complaints_screen.dart';
import '../bills/maintenance_history_screen.dart';
import '../contacts/contacts_screen.dart';
import '../guests/gate_pass_screen.dart';
import '../society/society_history_screen.dart';
import '../meetings/meetings_screen.dart';
import '../polls/polls_screen.dart';
import '../secretary/charges_screen.dart';
import '../secretary/secretary_repository.dart';

/// "Services" tab: a hub that opens each society service. Residents and the
/// admin see the same tiles; each screen adapts to [isAdmin]. The admin also
/// gets "New society charge" here (the Charges tab is history only).
class ServicesScreen extends ConsumerWidget {
  const ServicesScreen({super.key, required this.isAdmin});
  final bool isAdmin;

  void _open(BuildContext context, Widget screen) =>
      Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => screen));

  Future<void> _newSocietyCharge(BuildContext context, WidgetRef ref) async {
    final result = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(builder: (_) => const ChargeFormScreen()),
    );
    if (result == null) return; // backed out
    ref.invalidate(secretaryChargesProvider);
    ref.invalidate(collectionsProvider);
    if (!context.mounted) return;
    final skipped = (result['skipped_flats'] as List).cast<String>();
    showSnack(
      context,
      'Added to ${result['created']} flats'
      '${skipped.isEmpty ? '' : '. Skipped (nobody registered): ${skipped.join(', ')}'}',
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        if (isAdmin) ...[
          TileCard(
            leading: const IconBadge(Icons.add_card_rounded),
            title: 'New society charge',
            subtitle: 'Bill every flat for a festival or repair',
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _newSocietyCharge(context, ref),
          ),
          const SizedBox(height: 12),
        ],
        if (!isAdmin) ...[
          TileCard(
            leading: const IconBadge(Icons.qr_code_2_rounded,
                color: AppColors.orange, background: AppColors.orangeTint),
            title: 'Gate passes',
            subtitle: 'Let guests and helpers in with a pass',
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _open(context, const GatePassScreen()),
          ),
          const SizedBox(height: 12),
        ],
        TileCard(
          leading: const IconBadge(
            Icons.how_to_vote_rounded,
            color: AppColors.purple,
            background: AppColors.purpleTint,
          ),
          title: 'Polls',
          subtitle: isAdmin ? 'Ask residents to decide together' : 'Vote on society decisions',
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _open(context, PollsScreen(isAdmin: isAdmin)),
        ),
        const SizedBox(height: 12),
        TileCard(
          leading: const IconBadge(
            Icons.event_note_rounded,
            color: AppColors.teal,
            background: AppColors.tealTint,
          ),
          title: 'Meetings',
          subtitle: isAdmin ? 'Schedule and manage society meetings' : 'See upcoming society meetings',
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _open(context, MeetingsScreen(isAdmin: isAdmin)),
        ),
        const SizedBox(height: 12),
        TileCard(
          leading: const IconBadge(Icons.report_problem_outlined),
          title: 'Complaints',
          subtitle: isAdmin ? 'Review and resolve residents\' complaints' : 'Report an issue and track it',
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _open(context, ComplaintsScreen(isAdmin: isAdmin)),
        ),
        const SizedBox(height: 12),
        TileCard(
          leading: const IconBadge(Icons.event_available_outlined),
          title: 'Community hall',
          subtitle: isAdmin ? 'See and manage bookings' : 'Book the hall for an event',
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _open(context, BookingsScreen(isAdmin: isAdmin)),
        ),
        const SizedBox(height: 12),
        TileCard(
          leading: const IconBadge(
            Icons.local_phone_outlined,
            color: AppColors.error,
            background: AppColors.errorTint,
          ),
          title: 'Emergency contacts',
          subtitle: isAdmin ? 'Manage important numbers' : 'Police, ambulance, security and more',
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _open(context, ContactsScreen(isAdmin: isAdmin)),
        ),
        if (!isAdmin) ...[
          const SizedBox(height: 12),
          TileCard(
            leading: const IconBadge(Icons.receipt_long_rounded,
                color: AppColors.teal, background: AppColors.tealTint),
            title: 'My payment history',
            subtitle: 'Paid bills and receipts',
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _open(context, const MaintenanceHistoryScreen()),
          ),
          const SizedBox(height: 12),
          TileCard(
            leading: const IconBadge(Icons.insights_rounded,
                color: AppColors.purple, background: AppColors.purpleTint),
            title: 'Society history',
            subtitle: 'See how the society is doing',
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _open(context, const SocietyHistoryScreen()),
          ),
        ],
      ],
    );
  }
}
