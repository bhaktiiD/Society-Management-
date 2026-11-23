import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'gate_pass_repository.dart';

String? validatePhone(String? v) {
  final t = (v ?? '').trim();
  if (!RegExp(r'^\+?\d+$').hasMatch(t)) return 'Please enter a valid phone number.';
  final digits = t.replaceAll('+', '').length;
  return (digits < 10 || digits > 15) ? 'Please enter a valid phone number.' : null;
}

String? validateEmail(String? v) {
  final t = (v ?? '').trim();
  return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(t)
      ? null
      : 'Please enter a valid email address.';
}

/// Creates a gate pass. Pops with `true` on success; the caller refreshes the list.
/// The created pass is handed to [onCreated] so the caller can show its code.
class GatePassFormScreen extends ConsumerStatefulWidget {
  const GatePassFormScreen({super.key, this.onCreated});
  final ValueChanged<GatePass>? onCreated;

  @override
  ConsumerState<GatePassFormScreen> createState() => _GatePassFormScreenState();
}

class _GatePassFormScreenState extends ConsumerState<GatePassFormScreen> {
  static const _purposes = ['Guest', 'Delivery', 'Service', 'Cab', 'Other'];

  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _other = TextEditingController();
  final _vehicle = TextEditingController();
  String? _purpose;
  late DateTime _date = _today();
  int _days = 1;
  bool _busy = false;

  static DateTime _today() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _email.dispose();
    _other.dispose();
    _vehicle.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final today = _today();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: today,
      lastDate: today.add(const Duration(days: 30)),
    );
    if (picked != null && mounted) setState(() => _date = picked);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      String? purpose = _purpose;
      if (_purpose == 'Other' && _other.text.trim().isNotEmpty) purpose = _other.text.trim();
      final vehicle = _vehicle.text.trim().toUpperCase();
      final pass = await ref.read(gatePassRepositoryProvider).create(
            name: _name.text.trim(),
            phone: _phone.text.trim(),
            email: _email.text.trim(),
            purpose: purpose,
            vehicle: vehicle.isEmpty ? null : vehicle,
            visitDate: _date,
            validDays: _days,
          );
      widget.onCreated?.call(pass);
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
    const label = TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.muted);
    final dateIso = '${_date.year}-${_date.month.toString().padLeft(2, '0')}-'
        '${_date.day.toString().padLeft(2, '0')}';
    return Scaffold(
      appBar: AppBar(title: const Text('New gate pass')),
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
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Visitor name'),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? "Please enter the visitor's name." : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.next,
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+]'))],
                  decoration: const InputDecoration(labelText: 'Visitor phone'),
                  validator: validatePhone,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(labelText: 'Visitor email'),
                  validator: validateEmail,
                ),
                const SizedBox(height: 20),
                const Text('Purpose (optional)', style: label),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final p in _purposes)
                      ChoiceChip(
                        label: Text(p),
                        selected: _purpose == p,
                        selectedColor: AppColors.greenTint,
                        onSelected: (s) => setState(() => _purpose = s ? p : null),
                      ),
                  ],
                ),
                if (_purpose == 'Other') ...[
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _other,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(labelText: 'Describe the purpose'),
                  ),
                ],
                const SizedBox(height: 16),
                TextFormField(
                  controller: _vehicle,
                  textCapitalization: TextCapitalization.characters,
                  textInputAction: TextInputAction.done,
                  inputFormatters: [_UpperCase()],
                  decoration: const InputDecoration(labelText: 'Vehicle number (optional)'),
                ),
                const SizedBox(height: 20),
                const Text('Visit date', style: label),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _pickDate,
                  icon: const Icon(Icons.calendar_today_outlined),
                  label: Text(formatPassDate(dateIso)),
                ),
                const SizedBox(height: 20),
                const Text('Valid for', style: label),
                const SizedBox(height: 8),
                SegmentedButton<int>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: 1, label: Text('1 day')),
                    ButtonSegment(value: 2, label: Text('2 days')),
                    ButtonSegment(value: 3, label: Text('3 days')),
                  ],
                  selected: {_days},
                  onSelectionChanged: (s) => setState(() => _days = s.first),
                  style: SegmentedButton.styleFrom(
                    selectedBackgroundColor: AppColors.greenTint,
                    selectedForegroundColor: AppColors.greenDark,
                  ),
                ),
                const SizedBox(height: 28),
                FilledButton(
                  onPressed: _busy ? null : _submit,
                  child: _busy
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(strokeWidth: 3),
                        )
                      : const Text('Create gate pass'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _UpperCase extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue old, TextEditingValue n) =>
      n.copyWith(text: n.text.toUpperCase());
}
