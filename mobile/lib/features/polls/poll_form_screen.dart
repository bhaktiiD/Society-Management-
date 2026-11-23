import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'polls_repository.dart';

class PollFormScreen extends ConsumerStatefulWidget {
  const PollFormScreen({super.key});

  @override
  ConsumerState<PollFormScreen> createState() => _PollFormScreenState();
}

class _PollFormScreenState extends ConsumerState<PollFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _desc = TextEditingController();
  final _options = <TextEditingController>[TextEditingController(), TextEditingController()];
  String _audience = 'everyone';
  late DateTime _deadline = _today().add(const Duration(days: 3));
  bool _saving = false;

  static DateTime _today() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    for (final c in _options) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickDate() async {
    final today = _today();
    final d = await showDatePicker(
      context: context,
      initialDate: _deadline,
      firstDate: today,
      lastDate: today.add(const Duration(days: 90)),
    );
    if (d != null && mounted) setState(() => _deadline = d);
  }

  String? _optionError(int i, String? v) {
    final t = (v ?? '').trim();
    if (t.isEmpty) return 'Enter an option';
    if (t.length > 100) return 'Keep it under 100 characters';
    final lower = t.toLowerCase();
    for (var j = 0; j < i; j++) {
      if (_options[j].text.trim().toLowerCase() == lower) return 'This option is repeated';
    }
    return null;
  }

  Future<void> _submit() async {
    if (_saving || !_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final desc = _desc.text.trim();
      await ref.read(pollsRepositoryProvider).create(
            title: _title.text.trim(),
            description: desc.isEmpty ? null : desc,
            audience: _audience,
            options: [for (final c in _options) c.text.trim()],
            closesAtUtcIso:
                DateTime(_deadline.year, _deadline.month, _deadline.day, 23, 59).toUtc().toIso8601String(),
          );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showSnack(context, errorMessage(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New poll')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TextFormField(
                controller: _title,
                maxLength: 150,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Question'),
                validator: (v) => (v ?? '').trim().isEmpty ? 'Enter a title for the poll' : null,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _desc,
                maxLength: 1000,
                minLines: 3,
                maxLines: 6,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Description (optional)'),
              ),
              const SectionTitle('Who can vote'),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<String>(
                  style: SegmentedButton.styleFrom(
                    selectedBackgroundColor: AppColors.greenTint,
                    selectedForegroundColor: AppColors.greenDark,
                    minimumSize: const Size(0, 48),
                  ),
                  segments: const [
                    ButtonSegment(value: 'everyone', label: Text('Owners and tenants')),
                    ButtonSegment(value: 'owners', label: Text('Owners only')),
                  ],
                  selected: {_audience},
                  onSelectionChanged: (s) => setState(() => _audience = s.first),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _audience == 'owners'
                      ? 'Only flat owners can vote. Tenants will see the results after it closes.'
                      : 'Every resident, owners and tenants, can vote once.',
                  style: const TextStyle(fontSize: 13, color: AppColors.muted),
                ),
              ),
              const SectionTitle('Options'),
              for (var i = 0; i < _options.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _options[i],
                          maxLength: 100,
                          buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: InputDecoration(labelText: 'Option ${i + 1}'),
                          validator: (v) => _optionError(i, v),
                        ),
                      ),
                      if (i >= 2)
                        SizedBox(
                          width: 48,
                          height: 48,
                          child: IconButton(
                            tooltip: 'Remove option',
                            icon: const Icon(Icons.close),
                            onPressed: () => setState(() => _options.removeAt(i)),
                          ),
                        )
                      else
                        const SizedBox(width: 48),
                    ],
                  ),
                ),
              if (_options.length < 6)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => setState(() => _options.add(TextEditingController())),
                    icon: const Icon(Icons.add),
                    label: const Text('Add option'),
                  ),
                ),
              const SectionTitle('Voting closes'),
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: _pickDate,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 56),
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      suffixIcon: Icon(Icons.calendar_today_outlined),
                      helperText: 'Closes at the end of this day (11:59 PM)',
                    ),
                    child: Text(formatDate(toApiDate(_deadline)), style: const TextStyle(fontSize: 15)),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _saving ? null : _submit,
                child: _saving
                    ? const SizedBox(
                        width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5))
                    : const Text('Publish poll'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
