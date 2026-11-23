import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../models/models.dart';
import '../bills/bills_screen.dart';
import '../bills/maintenance_history_screen.dart';
import '../bookings/bookings_screen.dart';
import '../complaints/complaints_screen.dart';
import '../contacts/contacts_screen.dart';
import '../guests/gate_pass_screen.dart';
import '../guests/resident_guests_screen.dart';
import '../meetings/meetings_screen.dart';
import '../notices/notices_screen.dart';
import '../polls/polls_screen.dart';
import '../society/society_history_screen.dart';

/// One tappable action row: pastel icon badge, title, one-line subtitle, chevron.
/// Shared by the admin and resident groups on the profile screen.
class ActionTile extends StatelessWidget {
  const ActionTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.color = AppColors.greenDark,
    this.tint = AppColors.greenTint,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Color color;
  final Color tint;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: TileCard(
            leading: IconBadge(icon, color: color, background: tint),
            title: title,
            subtitle: subtitle,
            trailing: const Icon(Icons.chevron_right),
            onTap: onTap,
          ),
        ),
      );
}

/// "Flat A-101 (Owner)" style line for residents; null if no flats.
String? residentSummary(Me me) {
  if (me.flats.isEmpty) return null;
  final parts = [
    for (final f in me.flats) '${f.flatNumber} (${f.kind == 'owner' ? 'Owner' : 'Tenant'})',
  ];
  return '${parts.length == 1 ? 'Flat' : 'Flats'} ${parts.join(', ')}';
}

Future<T?> _push<T>(BuildContext context, Widget page) =>
    Navigator.of(context).push<T>(MaterialPageRoute(builder: (_) => page));

/// Action groups shown on the profile screen while acting as a resident.
class ResidentGroups extends StatelessWidget {
  const ResidentGroups({super.key, required this.canApproveGuests});
  final bool canApproveGuests;

  static const _gap = SizedBox(height: 10);

  @override
  Widget build(BuildContext context) {
    void open(Widget page) => _push(context, page);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader('My bills'),
        ActionTile(
          icon: Icons.receipt_long_outlined,
          title: 'My bills',
          subtitle: 'Pay and track maintenance and society fees',
          onTap: () => open(Scaffold(
            appBar: AppBar(title: const Text('My bills')),
            body: const BillsScreen(),
          )),
        ),
        _gap,
        ActionTile(
          icon: Icons.history_outlined,
          title: 'Payment history',
          subtitle: 'Everything you have paid or still owe',
          color: AppColors.teal,
          tint: AppColors.tealTint,
          onTap: () => open(const MaintenanceHistoryScreen()),
        ),
        _gap,
        ActionTile(
          icon: Icons.insights_outlined,
          title: 'Society history',
          subtitle: 'How the society is doing',
          color: AppColors.orange,
          tint: AppColors.orangeTint,
          onTap: () => open(const SocietyHistoryScreen()),
        ),
        const SectionHeader('Visitors'),
        ActionTile(
          icon: Icons.confirmation_number_outlined,
          title: 'Gate passes',
          subtitle: 'Create a pass for an expected visitor',
          color: AppColors.purple,
          tint: AppColors.purpleTint,
          onTap: () => open(const GatePassScreen()),
        ),
        if (canApproveGuests) ...[
          _gap,
          ActionTile(
            icon: Icons.how_to_reg_outlined,
            title: 'Guest approvals',
            subtitle: 'Approve or deny people at the gate',
            color: AppColors.rose,
            tint: AppColors.roseTint,
            onTap: () => open(Scaffold(
              appBar: AppBar(title: const Text('Visitors')),
              body: const ResidentGuestsScreen(),
            )),
          ),
        ],
        const SectionHeader('Community'),
        ActionTile(
          icon: Icons.event_available_outlined,
          title: 'Community hall',
          subtitle: 'Request the hall for an occasion',
          onTap: () => open(const BookingsScreen(isAdmin: false)),
        ),
        _gap,
        ActionTile(
          icon: Icons.report_problem_outlined,
          title: 'Complaints',
          subtitle: 'Report an issue and track it',
          color: AppColors.teal,
          tint: AppColors.tealTint,
          onTap: () => open(const ComplaintsScreen(isAdmin: false)),
        ),
        _gap,
        ActionTile(
          icon: Icons.how_to_vote_outlined,
          title: 'Polls',
          subtitle: 'Vote on society decisions',
          color: AppColors.orange,
          tint: AppColors.orangeTint,
          onTap: () => open(const PollsScreen(isAdmin: false)),
        ),
        _gap,
        ActionTile(
          icon: Icons.groups_outlined,
          title: 'Meetings',
          subtitle: 'Upcoming society meetings',
          color: AppColors.purple,
          tint: AppColors.purpleTint,
          onTap: () => open(const MeetingsScreen(isAdmin: false)),
        ),
        _gap,
        ActionTile(
          icon: Icons.campaign_outlined,
          title: 'Notices',
          subtitle: 'Read society announcements',
          color: AppColors.rose,
          tint: AppColors.roseTint,
          onTap: () => open(Scaffold(
            appBar: AppBar(title: const Text('Notices')),
            body: const NoticesScreen(),
          )),
        ),
        const SectionHeader('Safety'),
        ActionTile(
          icon: Icons.phone_in_talk_outlined,
          title: 'Emergency contacts',
          subtitle: 'Important numbers for your society',
          color: AppColors.rose,
          tint: AppColors.roseTint,
          onTap: () => open(const ContactsScreen(isAdmin: false)),
        ),
      ],
    );
  }
}
