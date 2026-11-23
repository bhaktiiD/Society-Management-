import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../models/models.dart';
import 'secretary_repository.dart';

void _refreshAll(WidgetRef ref) {
  ref.invalidate(flatsProvider);
  ref.invalidate(staffInvitesProvider);
  ref.invalidate(collectionsProvider);
}

/// Admin: everything about one flat. The owner (tagged), everyone else living
/// there with their contact numbers, anyone waiting to sign up, plus the
/// bottom bar to add a resident or move people out.
class FlatDetailScreen extends ConsumerWidget {
  const FlatDetailScreen({super.key, required this.flatId});
  final int flatId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final flats = ref.watch(flatsProvider);
    final flat = flats.value?.where((f) => f.id == flatId).firstOrNull;
    final hasPeople = flat != null && (flat.members.isNotEmpty || flat.pendingInvites.isNotEmpty);

    return Scaffold(
      appBar: AppBar(title: Text(flat == null ? 'Flat' : 'Flat ${flat.flatNumber}')),
      bottomNavigationBar: flat == null
          ? null
          : _ActionBar(
              canMoveOut: hasPeople,
              onAdd: () => _showAddSheet(context, flat),
              onMoveOut: () => _showMoveOutSheet(context, flatId),
            ),
      body: AsyncBody<List<FlatInfo>>(
        value: flats,
        onRetry: () => _refreshAll(ref),
        builder: (list) {
          final f = list.where((x) => x.id == flatId).firstOrNull;
          if (f == null) {
            return const EmptyState(icon: Icons.home_outlined, message: 'This flat no longer exists.');
          }
          // One person is tagged Owner; everybody else is listed as a resident.
          final owners = f.members.where((m) => m.kind == 'owner').toList();
          final owner = owners.firstOrNull;
          final residents = [...owners.skip(1), ...f.members.where((m) => m.kind == 'tenant')];

          return RefreshIndicator(
            onRefresh: () async {
              _refreshAll(ref);
              await refreshProvider(() => ref.read(flatsProvider.future));
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
              children: [
                const SectionHeader('Owner'),
                if (owner != null)
                  _PersonCard(
                    member: owner,
                    tag: 'Owner',
                    tone: ChipTone.success,
                    note: owner.isResident ? null : 'Does not live here',
                  )
                else
                  const _Muted('No owner registered yet'),
                const SectionHeader('Residents'),
                if (residents.isEmpty)
                  const _Muted('No other residents')
                else
                  for (final m in residents) ...[
                    _PersonCard(
                      member: m,
                      tag: m.kind == 'tenant' ? 'Tenant' : 'Co-owner',
                      tone: m.kind == 'tenant' ? ChipTone.info : ChipTone.success,
                      note: m.isResident ? null : 'Does not live here',
                    ),
                    const SizedBox(height: 10),
                  ],
                if (f.pendingInvites.isNotEmpty) ...[
                  const SectionHeader('Waiting to sign up'),
                  for (final i in f.pendingInvites) ...[
                    _PendingCard(invite: i),
                    const SizedBox(height: 10),
                  ],
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  void _showAddSheet(BuildContext context, FlatInfo flat) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (_) => _AddResidentSheet(flatId: flat.id, flatNumber: flat.flatNumber),
    );
  }

  void _showMoveOutSheet(BuildContext context, int flatId) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.7),
      builder: (_) => _MoveOutSheet(flatId: flatId),
    );
  }
}

class _ActionBar extends StatelessWidget {
  const _ActionBar({required this.canMoveOut, required this.onAdd, required this.onMoveOut});
  final bool canMoveOut;
  final VoidCallback onAdd;
  final VoidCallback onMoveOut;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.border)),
        boxShadow: [BoxShadow(color: Color(0x14000000), blurRadius: 8, offset: Offset(0, -2))],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: onAdd,
                  icon: const Icon(Icons.person_add_alt_1_rounded),
                  label: const Text('Add resident'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: canMoveOut ? onMoveOut : null,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.error,
                    side: BorderSide(color: canMoveOut ? AppColors.error : AppColors.border, width: 1.5),
                  ),
                  icon: const Icon(Icons.logout_rounded),
                  label: const Text('Move out'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Muted extends StatelessWidget {
  const _Muted(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Text(text, style: const TextStyle(color: AppColors.muted, fontSize: 15)),
      );
}

/// A person in the flat: avatar, name, role tag, phone, email, call.
class _PersonCard extends StatelessWidget {
  const _PersonCard({
    required this.member,
    required this.tag,
    required this.tone,
    this.note,
  });

  final FlatMember member;
  final String tag;
  final ChipTone tone;
  final String? note;

  Future<void> _call(BuildContext context, String phone) async {
    var opened = false;
    try {
      opened = await launchUrl(Uri(scheme: 'tel', path: phone.replaceAll(' ', '')));
    } catch (_) {
      opened = false;
    }
    if (!opened && context.mounted) {
      await Clipboard.setData(ClipboardData(text: phone));
      if (context.mounted) showSnack(context, "Couldn't open the dialer. Number copied: $phone");
    }
  }

  @override
  Widget build(BuildContext context) {
    final phone = member.phone;
    final hasPhone = phone != null && phone.trim().isNotEmpty;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 6, 14),
        child: Row(
          children: [
            _Avatar(member.name),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(member.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                      StatusChip(tag, tone: tone),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    hasPhone ? phone : 'No phone number',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: hasPhone ? FontWeight.w700 : FontWeight.w500,
                      color: hasPhone ? AppColors.ink : AppColors.muted,
                    ),
                  ),
                  Text(
                    member.email,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14, color: AppColors.muted),
                  ),
                  if (note != null)
                    Text(note!, style: const TextStyle(fontSize: 14, color: AppColors.warningDark)),
                ],
              ),
            ),
            if (hasPhone)
              IconButton(
                tooltip: 'Call ${member.name}',
                icon: const Icon(Icons.call, color: AppColors.greenDark),
                onPressed: () => _call(context, phone),
              ),
          ],
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar(this.name);
  final String name;

  @override
  Widget build(BuildContext context) => CircleAvatar(
        radius: 24,
        backgroundColor: AppColors.greenTint,
        child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : '?',
          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: AppColors.greenDark),
        ),
      );
}

String _inviteName(PendingInvite i) {
  final n = i.fullName?.trim();
  return (n == null || n.isEmpty) ? i.email : n;
}

/// Someone registered but not yet signed up.
class _PendingCard extends StatelessWidget {
  const _PendingCard({required this.invite});
  final PendingInvite invite;

  @override
  Widget build(BuildContext context) {
    final name = invite.fullName?.trim();
    final phone = invite.phone?.trim();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            const IconBadge(Icons.mail_outline, color: AppColors.warningDark, background: AppColors.warningTint),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (name != null && name.isNotEmpty)
                    Text(name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                  Text(
                    invite.email,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      color: (name != null && name.isNotEmpty) ? AppColors.muted : AppColors.ink,
                      fontWeight: (name != null && name.isNotEmpty) ? FontWeight.w500 : FontWeight.w800,
                    ),
                  ),
                  if (phone != null && phone.isNotEmpty)
                    Text(phone, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  StatusChip(invite.role == 'owner' ? 'Owner' : 'Tenant', tone: ChipTone.warning),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- Add resident

class _AddResidentSheet extends ConsumerStatefulWidget {
  const _AddResidentSheet({required this.flatId, required this.flatNumber});
  final int flatId;
  final String flatNumber;

  @override
  ConsumerState<_AddResidentSheet> createState() => _AddResidentSheetState();
}

class _AddResidentSheetState extends ConsumerState<_AddResidentSheet> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  bool _owner = false;
  bool _livesHere = true;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    final name = _name.text.trim();
    final phone = _phone.text.trim();
    try {
      await ref.read(secretaryRepositoryProvider).invite(
            email: _email.text.trim(),
            role: _owner ? 'owner' : 'tenant',
            flatId: widget.flatId,
            isResident: _owner ? _livesHere : true,
            fullName: name,
            phone: phone.isEmpty ? null : phone,
          );
      if (!mounted) return;
      _refreshAll(ref);
      final messenger = ScaffoldMessenger.of(context);
      Navigator.pop(context);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text('Added. ${name.split(RegExp(r'\s+')).first} can now create an account with that email.'),
          backgroundColor: AppColors.ink,
        ));
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      showSnack(context, errorMessage(error), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Add a resident to Flat ${widget.flatNumber}',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              const Text(
                'They create their account with this email and get access to this flat.',
                style: TextStyle(fontSize: 15, color: AppColors.muted),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: 'Full name'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter their full name' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: 'Email'),
                validator: (v) {
                  final value = (v ?? '').trim();
                  if (value.isEmpty) return 'Enter their email';
                  return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value) ? null : 'Enter a valid email';
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Phone (optional)'),
                validator: (v) {
                  final value = (v ?? '').trim();
                  if (value.isEmpty) return null;
                  return RegExp(r'^[0-9+() \-]{3,20}$').hasMatch(value)
                      ? null
                      : 'Enter a valid phone number, digits only';
                },
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<bool>(
                  showSelectedIcon: false,
                  style: SegmentedButton.styleFrom(
                    selectedBackgroundColor: AppColors.greenTint,
                    selectedForegroundColor: AppColors.greenDark,
                    minimumSize: const Size.fromHeight(48),
                  ),
                  segments: const [
                    ButtonSegment(value: true, label: Text('Owner')),
                    ButtonSegment(value: false, label: Text('Resident')),
                  ],
                  selected: {_owner},
                  onSelectionChanged: (s) => setState(() => _owner = s.first),
                ),
              ),
              if (_owner)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Lives in this flat'),
                  value: _livesHere,
                  activeThumbColor: AppColors.greenDark,
                  onChanged: (v) => setState(() => _livesHere = v),
                ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _busy ? null : _save,
                  child: _busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.onGreen),
                        )
                      : const Text('Add resident'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// -------------------------------------------------------------------- Move out

class _MoveOutSheet extends ConsumerWidget {
  const _MoveOutSheet({required this.flatId});
  final int flatId;

  Future<void> _confirm(
    BuildContext context,
    WidgetRef ref, {
    required String flatNumber,
    required String name,
    required Future<void> Function() action,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove $name?'),
        content: Text('They lose access to Flat $flatNumber immediately. Past bills stay on record.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await action();
      _refreshAll(ref);
      if (context.mounted) showSnack(context, '$name removed');
    } catch (error) {
      if (context.mounted) showSnack(context, errorMessage(error), error: true);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final flat = ref.watch(flatsProvider).value?.where((f) => f.id == flatId).firstOrNull;
    if (flat == null) return const SizedBox(height: 120, child: AppLoader());
    final repo = ref.read(secretaryRepositoryProvider);

    if (flat.members.isEmpty && flat.pendingInvites.isEmpty) {
      final route = ModalRoute.of(context);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // isCurrent turns false once the first pop starts, so this pops at most once.
        if (context.mounted && route?.isCurrent == true) Navigator.pop(context);
      });
    }

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Who is moving out of Flat ${flat.flatNumber}?',
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Tap the bin to remove someone. They lose access straight away. Past bills stay on record.',
                  style: TextStyle(fontSize: 15, color: AppColors.muted),
                ),
              ],
            ),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              children: [
                for (final m in flat.members)
                  _MoveOutRow(
                    name: m.name,
                    email: m.email,
                    tag: m.kind == 'tenant' ? 'Tenant' : (m.kind == 'owner' ? 'Owner' : 'Co-owner'),
                    tone: m.kind == 'tenant' ? ChipTone.info : ChipTone.success,
                    onRemove: () => _confirm(
                      context,
                      ref,
                      flatNumber: flat.flatNumber,
                      name: m.name,
                      action: () => repo.endMembership(m.membershipId),
                    ),
                  ),
                for (final i in flat.pendingInvites)
                  _MoveOutRow(
                    name: _inviteName(i),
                    email: i.email,
                    tag: 'Not signed up',
                    tone: ChipTone.warning,
                    onRemove: () => _confirm(
                      context,
                      ref,
                      flatNumber: flat.flatNumber,
                      name: _inviteName(i),
                      action: () => repo.revokeInvite(i.id),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MoveOutRow extends StatelessWidget {
  const _MoveOutRow({
    required this.name,
    required this.email,
    required this.tag,
    required this.tone,
    required this.onRemove,
  });
  final String name;
  final String email;
  final String tag;
  final ChipTone tone;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border, width: 1.5),
      ),
      child: Row(
        children: [
          _Avatar(name),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                Text(
                  email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14, color: AppColors.muted),
                ),
                const SizedBox(height: 4),
                StatusChip(tag, tone: tone),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Remove $name',
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            icon: const Icon(Icons.delete_outline_rounded, color: AppColors.error),
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}
