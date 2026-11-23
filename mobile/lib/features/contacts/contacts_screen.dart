import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'contacts_repository.dart';

/// Emergency / useful contacts. Everyone reads and calls; only the admin
/// ([isAdmin]) can add, edit or delete (the server enforces this too).
class ContactsScreen extends ConsumerWidget {
  const ContactsScreen({super.key, required this.isAdmin});
  final bool isAdmin;

  Future<void> _call(BuildContext context, SocietyContact c) async {
    var ok = false;
    try {
      ok = await launchUrl(Uri(scheme: 'tel', path: c.phone));
    } catch (_) {}
    if (!ok) {
      await Clipboard.setData(ClipboardData(text: c.phone));
      if (context.mounted) showSnack(context, 'Could not open dialer. ${c.phone} copied.');
    }
  }

  Future<void> _openForm(BuildContext context, WidgetRef ref, [SocietyContact? existing]) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => ContactFormScreen(existing: existing)),
    );
    if (saved == true) ref.invalidate(contactsProvider);
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, SocietyContact c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete contact?'),
        content: Text('${c.name} will be removed for everyone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(contactsRepositoryProvider).delete(c.id);
      ref.invalidate(contactsProvider);
    } catch (error) {
      if (context.mounted) showSnack(context, errorMessage(error), error: true);
    }
  }

  Widget _icon(String category) => switch (category) {
        'emergency' => const IconBadge(
            Icons.emergency_outlined,
            color: AppColors.error,
            background: AppColors.errorTint,
          ),
        'staff' => const IconBadge(Icons.badge_outlined),
        _ => const IconBadge(Icons.handyman_outlined),
      };

  Widget _tile(BuildContext context, WidgetRef ref, SocietyContact c) {
    final sub = [if (c.label != null && c.label!.isNotEmpty) c.label!, c.phone].join('\n');
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TileCard(
        leading: _icon(c.category),
        title: c.name,
        subtitle: sub,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isAdmin)
              PopupMenuButton<String>(
                tooltip: 'Edit or delete',
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                onSelected: (v) =>
                    v == 'edit' ? _openForm(context, ref, c) : _delete(context, ref, c),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('Edit')),
                  PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
              ),
            SizedBox(
              width: 48,
              height: 48,
              child: IconButton.filled(
                tooltip: 'Call ${c.name}',
                style: IconButton.styleFrom(
                  backgroundColor: AppColors.green,
                  foregroundColor: AppColors.onGreen,
                ),
                icon: const Icon(Icons.call),
                onPressed: () => _call(context, c),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contacts = ref.watch(contactsProvider);
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(title: const Text('Emergency contacts')),
      floatingActionButton: isAdmin
          ? FloatingActionButton.extended(
              onPressed: () => _openForm(context, ref),
              icon: const Icon(Icons.add),
              label: const Text('Add contact'),
            )
          : null,
      body: AsyncBody<List<SocietyContact>>(
        value: contacts,
        onRetry: () => ref.invalidate(contactsProvider),
        builder: (list) {
          Future<void> refresh() async {
            ref.invalidate(contactsProvider);
            await refreshProvider(() => ref.read(contactsProvider.future));
          }

          if (list.isEmpty) {
            return RefreshIndicator(
              onRefresh: refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  SizedBox(
                    height: 360,
                    child: EmptyState(
                      icon: Icons.contact_phone_outlined,
                      message: isAdmin
                          ? 'No contacts yet.\nAdd police, ambulance, fire, plumber...'
                          : 'No contacts yet',
                    ),
                  ),
                ],
              ),
            );
          }
          const groups = [
            ('emergency', 'Emergency'),
            ('staff', 'Staff'),
            ('service', 'Services'),
          ];
          final children = <Widget>[];
          for (final (cat, title) in groups) {
            final items = list.where((c) => c.category == cat).toList();
            if (items.isEmpty) continue;
            children.add(SectionHeader(title));
            children.addAll(items.map((c) => _tile(context, ref, c)));
          }
          return RefreshIndicator(
            onRefresh: refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              children: children,
            ),
          );
        },
      ),
    );
  }
}

class ContactFormScreen extends ConsumerStatefulWidget {
  const ContactFormScreen({super.key, this.existing});
  final SocietyContact? existing;

  @override
  ConsumerState<ContactFormScreen> createState() => _ContactFormScreenState();
}

class _ContactFormScreenState extends ConsumerState<ContactFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.existing?.name);
  late final _label = TextEditingController(text: widget.existing?.label);
  late final _phone = TextEditingController(text: widget.existing?.phone);
  late String _category = widget.existing?.category ?? 'service';
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _label.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    final repo = ref.read(contactsRepositoryProvider);
    try {
      final e = widget.existing;
      if (e == null) {
        await repo.create(
          name: _name.text.trim(),
          label: _label.text.trim(),
          phone: _phone.text.trim(),
          category: _category,
        );
      } else {
        await repo.update(
          e.id,
          name: _name.text.trim(),
          label: _label.text.trim(),
          phone: _phone.text.trim(),
          category: _category,
          sortOrder: e.sortOrder,
        );
      }
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
    final editing = widget.existing != null;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(title: Text(editing ? 'Edit contact' : 'Add contact')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _name,
                  textInputAction: TextInputAction.next,
                  maxLength: 100,
                  decoration: const InputDecoration(labelText: 'Name'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter a name' : null,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _label,
                  textInputAction: TextInputAction.next,
                  maxLength: 60,
                  decoration: const InputDecoration(labelText: 'Label (optional)'),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  maxLength: 20,
                  decoration: const InputDecoration(labelText: 'Phone'),
                  validator: (v) {
                    final t = (v ?? '').trim();
                    if (t.isEmpty) return 'Enter a phone number';
                    if (!RegExp(r'^[0-9+() \-]{3,20}$').hasMatch(t)) {
                      return 'Use digits, +, spaces, - or brackets (3-20 characters)';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: _category,
                  decoration: const InputDecoration(labelText: 'Category'),
                  items: const [
                    DropdownMenuItem(value: 'emergency', child: Text('Emergency')),
                    DropdownMenuItem(value: 'staff', child: Text('Staff')),
                    DropdownMenuItem(value: 'service', child: Text('Service')),
                  ],
                  onChanged: (v) => setState(() => _category = v ?? 'service'),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _busy ? null : _submit,
                  child: _busy
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(strokeWidth: 3),
                        )
                      : Text(editing ? 'Save changes' : 'Add contact'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
