import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../models/models.dart';
import 'flat_detail_screen.dart';
import 'secretary_repository.dart';

void _refreshPeople(WidgetRef ref) {
  ref.invalidate(flatsProvider);
  ref.invalidate(staffInvitesProvider);
  ref.invalidate(collectionsProvider);
}

/// Admin: flats, the people in them, and who is pre-registered but has not
/// created an account yet.
class FlatsScreen extends ConsumerWidget {
  const FlatsScreen({super.key});

  Future<void> _run(BuildContext context, WidgetRef ref, Future<void> Function() action) async {
    try {
      await action();
      _refreshPeople(ref);
    } catch (error) {
      if (context.mounted) showSnack(context, errorMessage(error), error: true);
    }
  }

  Future<void> _addFlat(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    String? type;
    final number = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Add a flat'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                autofocus: true,
                textCapitalization: TextCapitalization.characters,
                onChanged: (_) => setLocal(() {}),
                decoration: const InputDecoration(labelText: 'Flat number', hintText: 'e.g. B-204'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: type,
                decoration: const InputDecoration(
                  labelText: 'Flat type',
                  helperText: 'Decides the monthly maintenance rate. Cannot be changed later.',
                  helperMaxLines: 2,
                ),
                items: [for (final t in flatTypes) DropdownMenuItem(value: t, child: Text(t))],
                onChanged: (v) => setLocal(() => type = v),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            TextButton(
              // Both a number and a type are required before Add is enabled.
              onPressed: controller.text.trim().isEmpty || type == null
                  ? null
                  : () => Navigator.pop(ctx, controller.text.trim()),
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
    // Not disposed: the dialog is still animating closed and nothing listens to it.
    if (number == null || number.isEmpty || !context.mounted) return;
    await _run(
      context,
      ref,
      () => ref.read(secretaryRepositoryProvider).createFlat(number, flatType: type),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final flats = ref.watch(flatsProvider);
    final staff = ref.watch(staffInvitesProvider).value ?? const <PendingInvite>[];
    final repo = ref.read(secretaryRepositoryProvider);

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final sent = await Navigator.of(context).push<bool>(
            MaterialPageRoute(builder: (_) => const InviteFormScreen()),
          );
          if (sent == true && context.mounted) {
            showSnack(context, 'Registered. They can now create their account with that email.');
          }
        },
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Register person'),
      ),
      body: AsyncBody<List<FlatInfo>>(
        value: flats,
        onRetry: () => _refreshPeople(ref),
        builder: (list) => RefreshIndicator(
          onRefresh: () async {
            _refreshPeople(ref);
            await refreshProvider(() => ref.read(flatsProvider.future));
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            children: [
              OutlinedButton.icon(
                onPressed: () => _addFlat(context, ref),
                icon: const Icon(Icons.add_home_outlined),
                label: const Text('Add a flat'),
              ),
              const SizedBox(height: 12),
              if (list.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: EmptyState(
                    icon: Icons.apartment_outlined,
                    message: 'No flats yet.\nAdd your first flat above.',
                  ),
                ),
              for (final f in list) ...[
                _FlatCard(flat: f),
                const SizedBox(height: 10),
              ],
              if (staff.isNotEmpty) ...[
                const SectionHeader('Security & admins'),
                for (final m in staff) ...[
                  TileCard(
                    leading: IconBadge(
                      m.role == 'guard' ? Icons.security_outlined : Icons.admin_panel_settings_outlined,
                    ),
                    title: m.email,
                    subtitle: m.role == 'guard' ? 'Security guard' : 'Admin',
                    trailing: m.accepted
                        ? const StatusChip('Registered', tone: ChipTone.success)
                        : Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const StatusChip('Not signed up', tone: ChipTone.warning),
                              IconButton(
                                tooltip: 'Cancel invite',
                                icon: const Icon(Icons.close),
                                onPressed: () => _run(context, ref, () => repo.revokeInvite(m.id)),
                              ),
                            ],
                          ),
                  ),
                  const SizedBox(height: 10),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// One flat in the list. People first: the owner's name is the headline, the
/// flat number sits underneath, and an Owner / Tenant tag is in the top-right
/// corner. Tap for the full details.
class _FlatCard extends StatelessWidget {
  const _FlatCard({required this.flat});
  final FlatInfo flat;

  @override
  Widget build(BuildContext context) {
    final owner = flat.members.where((m) => m.kind == 'owner').firstOrNull;
    final rented = flat.members.any((m) => m.kind == 'tenant');
    final pendingOwner = flat.pendingInvites.where((i) => i.role == 'owner').firstOrNull;

    final String name;
    final bool muted;
    if (owner != null) {
      name = owner.name;
      muted = false;
    } else if (pendingOwner != null) {
      name = (pendingOwner.fullName?.isNotEmpty ?? false) ? pendingOwner.fullName! : pendingOwner.email;
      muted = true;
    } else {
      name = 'No owner registered';
      muted = true;
    }

    final Widget? tag = owner != null
        ? StatusChip(rented ? 'Tenant' : 'Owner', tone: rented ? ChipTone.info : ChipTone.success)
        : pendingOwner != null
            ? const StatusChip('Not signed up', tone: ChipTone.warning)
            : null;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).push<void>(
          MaterialPageRoute(builder: (_) => FlatDetailScreen(flatId: flat.id)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 12, 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: muted ? AppColors.surface : AppColors.greenTint,
                child: owner != null
                    ? Text(
                        name.isEmpty ? '?' : name[0].toUpperCase(),
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: AppColors.greenDark),
                      )
                    : const Icon(Icons.person_outline_rounded, color: AppColors.muted),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 20,
                          height: 1.2,
                          fontWeight: FontWeight.w900,
                          color: muted ? AppColors.muted : AppColors.ink,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Flat ${flat.flatNumber}',
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.muted),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  ?tag,
                  SizedBox(height: tag == null ? 0 : 10),
                  const Icon(Icons.chevron_right, color: AppColors.muted),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class InviteFormScreen extends ConsumerStatefulWidget {
  const InviteFormScreen({super.key});

  @override
  ConsumerState<InviteFormScreen> createState() => _InviteFormScreenState();
}

class _InviteFormScreenState extends ConsumerState<InviteFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  String _role = 'owner';
  int? _flatId;
  bool _livesHere = true;
  bool _busy = false;

  bool get _needsFlat => _role == 'owner' || _role == 'tenant';

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await ref.read(secretaryRepositoryProvider).invite(
            email: _email.text.trim(),
            role: _role,
            flatId: _needsFlat ? _flatId : null,
            isResident: _role == 'owner' ? _livesHere : true,
          );
      _refreshPeople(ref);
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        showSnack(context, errorMessage(error), error: true);
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final flats = ref.watch(flatsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Register a person')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Enter the email this person gave you. They create their account '
                  'with exactly that email, and only then can they open the app.',
                  style: TextStyle(color: AppColors.muted, height: 1.4),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  decoration: const InputDecoration(labelText: 'Email'),
                  validator: (v) {
                    final value = v?.trim() ?? '';
                    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value)
                        ? null
                        : 'Enter a valid email';
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _role,
                  decoration: const InputDecoration(labelText: 'Role'),
                  items: const [
                    DropdownMenuItem(value: 'owner', child: Text('Flat owner')),
                    DropdownMenuItem(value: 'tenant', child: Text('Tenant')),
                    DropdownMenuItem(value: 'guard', child: Text('Security guard')),
                    DropdownMenuItem(value: 'secretary', child: Text('Admin')),
                  ],
                  onChanged: (v) => setState(() => _role = v ?? 'owner'),
                ),
                if (_needsFlat) ...[
                  const SizedBox(height: 12),
                  flats.when(
                    loading: () => const LinearProgressIndicator(),
                    error: (e, _) => Text(errorMessage(e), style: const TextStyle(color: AppColors.error)),
                    data: (list) => DropdownButtonFormField<int>(
                      initialValue: _flatId,
                      decoration: const InputDecoration(labelText: 'Flat'),
                      items: [
                        for (final f in list)
                          DropdownMenuItem(value: f.id, child: Text('Flat ${f.flatNumber}')),
                      ],
                      onChanged: (v) => setState(() => _flatId = v),
                      validator: (v) => v == null ? 'Choose a flat' : null,
                    ),
                  ),
                ],
                if (_role == 'owner')
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    activeThumbColor: AppColors.greenDark,
                    title: const Text('Lives in this flat'),
                    subtitle: const Text('Only residents can approve guests.'),
                    value: _livesHere,
                    onChanged: (v) => setState(() => _livesHere = v),
                  ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _busy ? null : _submit,
                  child: _busy
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(strokeWidth: 3),
                        )
                      : const Text('Register'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
