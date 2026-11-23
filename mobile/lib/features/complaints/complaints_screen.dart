import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'complaints_repository.dart';

const _categories = <String, (String, IconData)>{
  'plumbing': ('Plumbing', Icons.water_drop_outlined),
  'electrical': ('Electrical', Icons.bolt_outlined),
  'lift': ('Lift', Icons.elevator_outlined),
  'security': ('Security', Icons.shield_outlined),
  'cleaning': ('Cleaning', Icons.cleaning_services_outlined),
  'parking': ('Parking', Icons.local_parking_outlined),
  'noise': ('Noise', Icons.volume_up_outlined),
  'other': ('Other', Icons.report_problem_outlined),
};

const _statuses = <String, String>{
  'open': 'Open',
  'in_progress': 'In progress',
  'resolved': 'Resolved',
};

String _categoryLabel(String c) => _categories[c]?.$1 ?? c;
String _statusLabel(String s) => _statuses[s] ?? s;

ChipTone _tone(String s) => switch (s) {
      'resolved' => ChipTone.success,
      'in_progress' => ChipTone.info,
      _ => ChipTone.warning,
    };

Widget _badge(String category) {
  final icon = _categories[category]?.$2 ?? Icons.report_problem_outlined;
  return IconBadge(icon);
}

class ComplaintsScreen extends ConsumerStatefulWidget {
  const ComplaintsScreen({super.key, required this.isAdmin});
  final bool isAdmin;

  @override
  ConsumerState<ComplaintsScreen> createState() => _ComplaintsScreenState();
}

class _ComplaintsScreenState extends ConsumerState<ComplaintsScreen> {
  String? _filter; // admin only; null = all

  Future<void> _refresh() async {
    if (widget.isAdmin) {
      ref.invalidate(adminComplaintsProvider(_filter));
      await refreshProvider(() => ref.read(adminComplaintsProvider(_filter).future));
    } else {
      ref.invalidate(myComplaintsProvider);
      await refreshProvider(() => ref.read(myComplaintsProvider.future));
    }
  }

  void _reload() {
    if (widget.isAdmin) {
      ref.invalidate(adminComplaintsProvider);
    } else {
      ref.invalidate(myComplaintsProvider);
    }
  }

  Future<void> _openNew() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const ComplaintFormScreen()),
    );
    if (created == true) ref.invalidate(myComplaintsProvider);
  }

  void _openDetail(Complaint c) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (_) => widget.isAdmin
          ? _AdminSheet(complaint: c, onSaved: _reload)
          : _DetailSheet(complaint: c),
    );
  }

  @override
  Widget build(BuildContext context) {
    final value = widget.isAdmin
        ? ref.watch(adminComplaintsProvider(_filter))
        : ref.watch(myComplaintsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Complaints')),
      floatingActionButton: widget.isAdmin
          ? null
          : FloatingActionButton.extended(
              onPressed: _openNew,
              icon: const Icon(Icons.add),
              label: const Text('New complaint'),
            ),
      body: Column(
        children: [
          if (widget.isAdmin)
            SizedBox(
              height: 60,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                children: [
                  for (final e in <String?, String>{null: 'All', ..._statuses}.entries)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(e.value, style: const TextStyle(fontSize: 14)),
                        selected: _filter == e.key,
                        selectedColor: AppColors.greenTint,
                        onSelected: (_) => setState(() => _filter = e.key),
                      ),
                    ),
                ],
              ),
            ),
          Expanded(
            child: AsyncBody<List<Complaint>>(
              value: value,
              onRetry: _reload,
              builder: (list) => RefreshIndicator(
                onRefresh: _refresh,
                child: list.isEmpty
                    ? LayoutBuilder(
                        builder: (_, box) => ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: [
                            SizedBox(
                              height: box.maxHeight,
                              child: EmptyState(
                                icon: Icons.check_circle_outline,
                                message: widget.isAdmin
                                    ? 'No complaints here.'
                                    : 'No complaints yet.\nTap "New complaint" to raise one.',
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                        itemCount: list.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (_, i) {
                          final c = list[i];
                          final who = widget.isAdmin
                              ? [
                                  if (c.flatNumber != null) 'Flat ${c.flatNumber}',
                                  if (c.creatorName != null) c.creatorName!,
                                ].join(' - ')
                              : _categoryLabel(c.category);
                          return TileCard(
                            leading: _badge(c.category),
                            title: c.title,
                            subtitle: '$who - ${formatDate(c.createdAt)}',
                            trailing: StatusChip(_statusLabel(c.status), tone: _tone(c.status)),
                            onTap: () => _openDetail(c),
                          );
                        },
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SheetHeader extends StatelessWidget {
  const _SheetHeader(this.c);
  final Complaint c;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _badge(c.category),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(c.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
              const SizedBox(height: 2),
              Text(
                '${_categoryLabel(c.category)} - ${formatDate(c.createdAt)}',
                style: const TextStyle(fontSize: 14, color: AppColors.muted),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Opens one complaint's detail popup (admin gets the status/note editor).
/// Used by the admin Home cards so a tap shows only that complaint.
Future<void> showComplaintSheet(BuildContext context, Complaint c, {required bool isAdmin}) {
  final container = ProviderScope.containerOf(context, listen: false);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Colors.white,
    builder: (_) => isAdmin
        ? _AdminSheet(complaint: c, onSaved: () => container.invalidate(adminComplaintsProvider))
        : _DetailSheet(complaint: c),
  );
}

class _DetailSheet extends StatelessWidget {
  const _DetailSheet({required this.complaint});
  final Complaint complaint;

  @override
  Widget build(BuildContext context) {
    final c = complaint;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _SheetHeader(c),
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerLeft,
              child: StatusChip(_statusLabel(c.status), tone: _tone(c.status)),
            ),
            const SizedBox(height: 14),
            Text(c.description, style: const TextStyle(fontSize: 15, height: 1.4)),
            if (c.resolvedAt != null) ...[
              const SizedBox(height: 12),
              Text('Resolved on ${formatDate(c.resolvedAt!)}',
                  style: const TextStyle(fontSize: 14, color: AppColors.muted)),
            ],
            if (c.adminNote != null && c.adminNote!.isNotEmpty) ...[
              const SectionHeader('Note from admin'),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.greenTint,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(c.adminNote!, style: const TextStyle(fontSize: 15, height: 1.4)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AdminSheet extends ConsumerStatefulWidget {
  const _AdminSheet({required this.complaint, required this.onSaved});
  final Complaint complaint;
  final VoidCallback onSaved;

  @override
  ConsumerState<_AdminSheet> createState() => _AdminSheetState();
}

class _AdminSheetState extends ConsumerState<_AdminSheet> {
  late String _status = widget.complaint.status;
  late final _note = TextEditingController(text: widget.complaint.adminNote ?? '');
  bool _busy = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      await ref
          .read(complaintsRepositoryProvider)
          .update(widget.complaint.id, status: _status, note: _note.text.trim());
      widget.onSaved();
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) {
        showSnack(context, errorMessage(error), error: true);
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.complaint;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _SheetHeader(c),
              const SizedBox(height: 10),
              Text(
                [
                  if (c.flatNumber != null) 'Flat ${c.flatNumber}',
                  if (c.creatorName != null) c.creatorName!,
                  if (c.creatorEmail != null) c.creatorEmail!,
                ].join(' - '),
                style: const TextStyle(fontSize: 14, color: AppColors.muted),
              ),
              const SizedBox(height: 12),
              Text(c.description, style: const TextStyle(fontSize: 15, height: 1.4)),
              const SectionHeader('Status'),
              Wrap(
                spacing: 8,
                children: [
                  for (final e in _statuses.entries)
                    ChoiceChip(
                      label: Text(e.value, style: const TextStyle(fontSize: 14)),
                      selected: _status == e.key,
                      selectedColor: AppColors.greenTint,
                      onSelected: (_) => setState(() => _status = e.key),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _note,
                minLines: 2,
                maxLines: 4,
                maxLength: 1000,
                decoration: const InputDecoration(
                  labelText: 'Note for the resident (optional)',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: _busy ? null : _save,
                child: _busy
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(strokeWidth: 3),
                      )
                    : const Text('Save'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ComplaintFormScreen extends ConsumerStatefulWidget {
  const ComplaintFormScreen({super.key});

  @override
  ConsumerState<ComplaintFormScreen> createState() => _ComplaintFormScreenState();
}

class _ComplaintFormScreenState extends ConsumerState<ComplaintFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _desc = TextEditingController();
  String _category = 'plumbing';
  bool _busy = false;

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await ref.read(complaintsRepositoryProvider).create(
            category: _category,
            title: _title.text.trim(),
            description: _desc.text.trim(),
          );
      if (mounted) {
        showSnack(context, 'Complaint submitted');
        Navigator.pop(context, true);
      }
    } catch (error) {
      if (mounted) {
        showSnack(context, errorMessage(error), error: true);
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New complaint')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: _category,
                  decoration: const InputDecoration(labelText: 'Category'),
                  items: [
                    for (final e in _categories.entries)
                      DropdownMenuItem(value: e.key, child: Text(e.value.$1)),
                  ],
                  onChanged: (v) => setState(() => _category = v ?? _category),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _title,
                  textInputAction: TextInputAction.next,
                  maxLength: 120,
                  decoration: const InputDecoration(labelText: 'Title'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter a title' : null,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _desc,
                  minLines: 5,
                  maxLines: 10,
                  maxLength: 2000,
                  decoration: const InputDecoration(
                    labelText: 'Describe the problem',
                    alignLabelWithHint: true,
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Describe the problem' : null,
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _busy ? null : _submit,
                  child: _busy
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(strokeWidth: 3),
                        )
                      : const Text('Submit complaint'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
