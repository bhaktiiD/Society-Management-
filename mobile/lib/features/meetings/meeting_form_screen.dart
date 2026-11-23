import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'meeting_widgets.dart';
import 'meetings_repository.dart';

class MeetingFormScreen extends ConsumerStatefulWidget {
  const MeetingFormScreen({super.key});

  @override
  ConsumerState<MeetingFormScreen> createState() => _MeetingFormScreenState();
}

class _MeetingFormScreenState extends ConsumerState<MeetingFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _agenda = TextEditingController();
  final _location = TextEditingController();
  DateTime? _date;
  TimeOfDay? _time;
  String _audience = 'everyone';
  bool _busy = false;
  bool _submitted = false;

  @override
  void dispose() {
    _title.dispose();
    _agenda.dispose();
    _location.dispose();
    super.dispose();
  }

  DateTime? get _when => (_date == null || _time == null)
      ? null
      : DateTime(_date!.year, _date!.month, _date!.day, _time!.hour, _time!.minute);

  String? get _whenError {
    if (!_submitted) return null;
    final w = _when;
    if (w == null) return 'Pick a date and time';
    if (!w.isAfter(DateTime.now())) return 'Pick a time in the future';
    return null;
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _date ?? now,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (d != null && mounted) setState(() => _date = d);
  }

  Future<void> _pickTime() async {
    final t = await showTimePicker(
      context: context,
      initialTime: _time ?? const TimeOfDay(hour: 18, minute: 0),
    );
    if (t != null && mounted) setState(() => _time = t);
  }

  Future<void> _submit() async {
    setState(() => _submitted = true);
    final valid = _formKey.currentState!.validate();
    final when = _when;
    if (!valid || when == null || !when.isAfter(DateTime.now())) return;
    setState(() => _busy = true);
    try {
      final agenda = _agenda.text.trim();
      final location = _location.text.trim();
      await ref.read(meetingsRepositoryProvider).create(
            title: _title.text.trim(),
            agenda: agenda.isEmpty ? null : agenda,
            location: location.isEmpty ? null : location,
            scheduledAt: when,
            audience: _audience,
          );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      showSnack(context, errorMessage(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final err = _whenError;
    return Scaffold(
      appBar: AppBar(title: const Text('Schedule a meeting')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              TextFormField(
                controller: _title,
                maxLength: 150,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Title'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Give the meeting a title' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _agenda,
                maxLength: 2000,
                minLines: 4,
                maxLines: 8,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Agenda (optional)',
                  helperText: 'What will be discussed?',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _location,
                maxLength: 150,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Location (optional)',
                  hintText: 'e.g. Community hall',
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _PickerField(
                      label: 'Date',
                      icon: Icons.calendar_today_outlined,
                      text: _date == null ? 'Select' : formatDate(toApiDate(_date!)),
                      error: err != null && _date == null,
                      onTap: _pickDate,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _PickerField(
                      label: 'Time',
                      icon: Icons.schedule_rounded,
                      text: _time == null ? 'Select' : timeText(DateTime(0, 1, 1, _time!.hour, _time!.minute)),
                      error: err != null && _time == null,
                      onTap: _pickTime,
                    ),
                  ),
                ],
              ),
              if (err != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6, left: 4),
                  child: Text(err, style: const TextStyle(fontSize: 12, color: AppColors.error)),
                ),
              const SizedBox(height: 20),
              const Text('Who is invited', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                showSelectedIcon: false,
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
              const SizedBox(height: 6),
              Text(
                _audience == 'owners'
                    ? 'Only flat owners will be told about this meeting.'
                    : 'Every owner and tenant will be told about this meeting.',
                style: const TextStyle(fontSize: 13, color: AppColors.muted),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _busy ? null : _submit,
                child: _busy
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.onGreen),
                      )
                    : const Text('Schedule meeting'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PickerField extends StatelessWidget {
  const _PickerField({
    required this.label,
    required this.icon,
    required this.text,
    required this.onTap,
    this.error = false,
  });
  final String label;
  final IconData icon;
  final String text;
  final bool error;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, size: 20),
          errorText: null,
          enabledBorder: error
              ? OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: AppColors.error, width: 1.5),
                )
              : null,
        ),
        child: Text(text, style: const TextStyle(fontSize: 15), maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
    );
  }
}
