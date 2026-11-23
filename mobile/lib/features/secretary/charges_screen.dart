import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../models/models.dart';
import 'maintenance_screen.dart';
import 'secretary_repository.dart';

/// All charges in the society, with a button to create a new one.
enum _View { maintenance, society }

class SecretaryChargesScreen extends ConsumerStatefulWidget {
  const SecretaryChargesScreen({super.key});

  @override
  ConsumerState<SecretaryChargesScreen> createState() => _SecretaryChargesScreenState();
}

class _SecretaryChargesScreenState extends ConsumerState<SecretaryChargesScreen> {
  _View _view = _View.maintenance;

  @override
  Widget build(BuildContext context) {
    final charges = ref.watch(secretaryChargesProvider);
    // History only: charges are created from Services > New society charge.
    return Scaffold(
      body: AsyncBody<List<Charge>>(
        value: charges,
        onRetry: () => ref.invalidate(secretaryChargesProvider),
        builder: (list) {
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(secretaryChargesProvider);
              ref.invalidate(billingSettingsProvider);
              await refreshProvider(() => ref.read(secretaryChargesProvider.future));
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: [
                const _MaintenanceCard(),
                const SizedBox(height: 16),
                _ViewToggle(
                  society: _view == _View.society,
                  onChanged: (society) =>
                      setState(() => _view = society ? _View.society : _View.maintenance),
                ),
                const SizedBox(height: 20),
                if (_view == _View.maintenance)
                  _MaintenanceHistory(list)
                else
                  _SocietyRecords(list),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Two equal tabs in a rounded track; a white pill slides under the selected one.
class _ViewToggle extends StatelessWidget {
  const _ViewToggle({required this.society, required this.onChanged});
  final bool society;
  final ValueChanged<bool> onChanged;

  Widget _tab(String label, bool selected, bool value) {
    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        excludeSemantics: true,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => onChanged(value),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    color: selected ? AppColors.greenDark : AppColors.muted,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Stack(
        children: [
          AnimatedAlign(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            alignment: society ? Alignment.centerRight : Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: 0.5,
              heightFactor: 1,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: const [
                    BoxShadow(color: Color(0x1A000000), blurRadius: 8, offset: Offset(0, 2)),
                  ],
                ),
              ),
            ),
          ),
          Row(
            children: [
              _tab('Maintenance', !society, false),
              _tab('Society charges', society, true),
            ],
          ),
        ],
      ),
    );
  }
}

const _months = [
  'January', 'February', 'March', 'April', 'May', 'June', 'July',
  'August', 'September', 'October', 'November', 'December',
];
final _monthRe = RegExp('(${_months.join('|')}) (\\d{4})');

Widget _progressBar(int done, int total) {
  return ClipRRect(
    borderRadius: BorderRadius.circular(4),
    child: LinearProgressIndicator(
      value: total <= 0 ? 0 : (done / total).clamp(0.0, 1.0),
      minHeight: 6,
      color: AppColors.greenDark,
      backgroundColor: AppColors.greenTint,
    ),
  );
}

/// Maintenance bills + late fees, grouped by month, newest first.
class _MaintenanceHistory extends StatelessWidget {
  const _MaintenanceHistory(this.all);
  final List<Charge> all;

  /// Sortable key (year * 12 + month index) and display label.
  (int, String) _month(Charge c) {
    final m = _monthRe.firstMatch(c.title);
    int year, month;
    if (m != null) {
      month = _months.indexOf(m.group(1)!);
      year = int.parse(m.group(2)!);
    } else {
      final d = DateTime.tryParse(c.dueDate) ?? DateTime.now();
      month = d.month - 1;
      year = d.year;
    }
    return (year * 12 + month, '${_months[month]} $year');
  }

  @override
  Widget build(BuildContext context) {
    final groups = <int, (String, List<Charge>)>{};
    for (final c in all) {
      if (c.chargeType != 'maintenance' && c.chargeType != 'late_fee') continue;
      final (key, label) = _month(c);
      groups.putIfAbsent(key, () => (label, <Charge>[])).$2.add(c);
    }
    if (groups.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: EmptyState(icon: Icons.receipt_long_outlined, message: 'No maintenance bills yet'),
      );
    }
    final keys = groups.keys.toList()..sort((a, b) => b.compareTo(a));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final k in keys) ...[
          _MonthBlock(label: groups[k]!.$1, charges: groups[k]!.$2),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _MonthBlock extends StatelessWidget {
  const _MonthBlock({required this.label, required this.charges});
  final String label;
  final List<Charge> charges;

  @override
  Widget build(BuildContext context) {
    final collected = charges.fold<int>(0, (s, c) => s + c.paidPaise);
    final billed = charges.fold<int>(0, (s, c) => s + c.amountPaise);
    final bills = charges.where((c) => c.chargeType == 'maintenance').toList();
    final paid = bills.where((c) => c.status == 'paid').length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        const SizedBox(height: 2),
        Row(
          children: [
            Expanded(
              child: Text(
                'Collected ${formatRupees(collected)} of ${formatRupees(billed)}',
                style: const TextStyle(fontSize: 14, color: AppColors.muted),
              ),
            ),
            Text(
              '$paid of ${bills.length} paid',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.greenDark),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _progressBar(collected, billed),
        const SizedBox(height: 10),
        for (final c in charges) ...[
          _MaintenanceRow(c),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

/// Festival / repair charges, one record per (title, due date).
class _SocietyRecords extends StatelessWidget {
  const _SocietyRecords(this.all);
  final List<Charge> all;

  @override
  Widget build(BuildContext context) {
    final groups = <String, List<Charge>>{};
    for (final c in all) {
      if (c.chargeType != 'festival' && c.chargeType != 'repair') continue;
      groups.putIfAbsent('${c.title}|${c.dueDate}', () => []).add(c);
    }
    if (groups.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: EmptyState(icon: Icons.celebration_outlined, message: 'No society charges yet'),
      );
    }
    final records = groups.values.toList()
      ..sort((a, b) => b.first.dueDate.compareTo(a.first.dueDate));
    return Column(
      children: [
        for (final r in records) ...[
          _RecordCard(r),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

_FlatStatus _statusOf(Charge c) => switch (c.status) {
      'paid' => const _FlatStatus('Paid', ChipTone.success),
      'partial' => const _FlatStatus('Partly paid', ChipTone.warning),
      _ => c.overdue
          ? const _FlatStatus('Overdue', ChipTone.error)
          : const _FlatStatus('Unpaid', ChipTone.neutral),
    };

class _FlatStatus {
  const _FlatStatus(this.label, this.tone);
  final String label;
  final ChipTone tone;
}

class _RecordCard extends StatelessWidget {
  const _RecordCard(this.group);
  final List<Charge> group;

  void _open(BuildContext context) {
    final flats = [...group]..sort((a, b) {
        final x = a.flatNumber ?? '';
        final y = b.flatNumber ?? '';
        final nx = int.tryParse(x), ny = int.tryParse(y);
        return (nx != null && ny != null) ? nx.compareTo(ny) : x.compareTo(y);
      });
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(group.first.title,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final c in flats)
                      ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 48),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text('Flat ${c.flatNumber ?? '-'}',
                                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                            ),
                            StatusChip(_statusOf(c).label, tone: _statusOf(c).tone),
                            const SizedBox(width: 12),
                            Text(
                              '${formatRupees(c.paidPaise)} / ${formatRupees(c.amountPaise)}',
                              style: const TextStyle(fontSize: 14),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final first = group.first;
    final collected = group.fold<int>(0, (s, c) => s + c.paidPaise);
    final total = group.fold<int>(0, (s, c) => s + c.amountPaise);
    final paid = group.where((c) => c.status == 'paid').length;
    final festival = first.chargeType == 'festival';
    return Card(
      color: Colors.white,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _open(context),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  IconBadge(
                    festival ? Icons.celebration_outlined : Icons.build_outlined,
                    color: AppColors.greenDark,
                    background: AppColors.greenTint,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(first.title,
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                        Text(
                          'Due ${formatDate(first.dueDate)} - ${formatRupees(first.amountPaise)} per flat',
                          style: const TextStyle(fontSize: 14, color: AppColors.muted),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right),
                ],
              ),
              const SizedBox(height: 12),
              _progressBar(collected, total),
              const SizedBox(height: 6),
              Text(
                '$paid of ${group.length} flats paid - ${formatRupees(collected)} of ${formatRupees(total)}',
                style: const TextStyle(fontSize: 14),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Entry to the monthly maintenance settings: title, due day, and one small
/// pill per flat type showing its rate.
class _MaintenanceCard extends ConsumerWidget {
  const _MaintenanceCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(billingSettingsProvider).value;
    final notSetUp = s != null && !s.anyRateSet;
    final line = notSetUp
        ? 'Set your rates to start monthly billing.'
        : 'Set the rates, due date and late fees once. Bills go out every month on their own.';

    return Material(
      color: notSetUp ? AppColors.warningTint : Colors.white,
      borderRadius: BorderRadius.circular(20),
      elevation: 2,
      shadowColor: const Color(0x1A000000),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () async {
          await Navigator.of(context).push<void>(
            MaterialPageRoute(builder: (_) => const MaintenanceScreen()),
          );
          ref.invalidate(billingSettingsProvider);
          ref.invalidate(secretaryChargesProvider);
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 12, 16),
          child: Row(
            children: [
              IconBadge(
                Icons.calendar_month_outlined,
                color: notSetUp ? AppColors.warningDark : AppColors.greenDark,
                background: notSetUp ? Colors.white : AppColors.greenTint,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Monthly maintenance',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      line,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14, height: 1.3, color: AppColors.muted),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppColors.muted),
            ],
          ),
        ),
      ),
    );
  }
}

/// One flat's bill inside a month: flat and due date on the left, amount and
/// status on the right.
class _MaintenanceRow extends StatelessWidget {
  const _MaintenanceRow(this.c);
  final Charge c;

  @override
  Widget build(BuildContext context) {
    final chip = switch (c.status) {
      'paid' => const StatusChip('Paid', tone: ChipTone.success),
      'partial' => const StatusChip('Partly paid', tone: ChipTone.warning),
      _ => c.overdue
          ? const StatusChip('Overdue', tone: ChipTone.error)
          : const StatusChip('Unpaid', tone: ChipTone.neutral),
    };
    final (icon, fg, bg) = switch (c.chargeType) {
      'festival' => (Icons.celebration_outlined, AppColors.greenDark, AppColors.greenTint),
      'repair' => (Icons.build_outlined, AppColors.greenDark, AppColors.greenTint),
      'late_fee' => (Icons.schedule, AppColors.warningDark, AppColors.warningTint),
      _ => (Icons.apartment, AppColors.greenDark, AppColors.greenTint),
    };
    return TileCard(
      leading: IconBadge(icon, color: fg, background: bg),
      title: c.chargeType == 'late_fee' ? 'Flat ${c.flatNumber ?? '-'} · Late fee' : 'Flat ${c.flatNumber ?? '-'}',
      // 'Due 10 Nov' (the year is already in the month heading).
      subtitle: 'Due ${formatDate(c.dueDate).replaceFirst(RegExp(r' \d{4}$'), '')}',
      trailing: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            formatRupees(c.amountPaise),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          chip,
        ],
      ),
    );
  }
}

class ChargeFormScreen extends ConsumerStatefulWidget {
  const ChargeFormScreen({super.key});

  @override
  ConsumerState<ChargeFormScreen> createState() => _ChargeFormScreenState();
}

class _ChargeFormScreenState extends ConsumerState<ChargeFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _amount = TextEditingController();

  String _type = 'festival';
  String _responsible = 'owner';
  DateTime _due = DateTime.now().add(const Duration(days: 10));
  bool _busy = false;

  @override
  void dispose() {
    _title.dispose();
    _amount.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _due,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
    );
    if (picked != null) setState(() => _due = picked);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final amount = parseRupeesToPaise(_amount.text)!;
    final flatCount = ref.read(flatsProvider).value?.length;

    // Billing everyone is hard to undo, so confirm first.
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Bill all flats?'),
        content: Text(
          '"${_title.text.trim()}" will be added to ${flatCount == null ? 'every flat' : '$flatCount flats'} '
          'at ${formatRupees(amount)} each'
          '${flatCount == null ? '' : ' (${formatRupees(amount * flatCount)} in total)'}.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Bill all flats')),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _busy = true);
    try {
      final result = await ref.read(secretaryRepositoryProvider).createSocietyCharge(
            chargeType: _type,
            title: _title.text.trim(),
            amountPaise: amount,
            dueDate: _due,
            responsible: _responsible,
          );
      if (mounted) Navigator.pop(context, result);
    } catch (error) {
      if (mounted) {
        showSnack(context, errorMessage(error), error: true);
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final flatCount = ref.watch(flatsProvider).value?.length;
    return Scaffold(
      appBar: AppBar(title: const Text('New charge')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // No flat picker: a festival / repair charge applies to the whole society.
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.greenTint,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.groups_outlined, color: AppColors.greenDark),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          flatCount == null
                              ? 'This charge is added to every flat in the society.'
                              : 'This charge is added to all $flatCount flats in the society.',
                          style: const TextStyle(fontSize: 14, height: 1.35),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                SegmentedButton<String>(
                  // Monthly maintenance is automatic (Maintenance settings).
                  segments: const [
                    ButtonSegment(value: 'festival', label: Text('Festival')),
                    ButtonSegment(value: 'repair', label: Text('Repair')),
                  ],
                  selected: {_type},
                  onSelectionChanged: (s) => setState(() => _type = s.first),
                  style: SegmentedButton.styleFrom(
                    selectedBackgroundColor: AppColors.greenTint,
                    selectedForegroundColor: AppColors.greenDark,
                  ),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: _responsible,
                  decoration: const InputDecoration(labelText: 'Who pays?'),
                  items: const [
                    DropdownMenuItem(value: 'owner', child: Text('Owner')),
                    DropdownMenuItem(value: 'tenant', child: Text('Tenant')),
                  ],
                  onChanged: (v) => setState(() => _responsible = v ?? 'owner'),
                ),
                if (_responsible == 'tenant')
                  const Padding(
                    padding: EdgeInsets.only(top: 6, left: 4),
                    child: Text(
                      'Flats without a tenant are billed to their owner.',
                      style: TextStyle(color: AppColors.muted, fontSize: 13),
                    ),
                  ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _title,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(labelText: 'Title', hintText: 'e.g. Diwali celebration'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter a title' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _amount,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Amount', prefixText: '₹ '),
                  validator: (v) => parseRupeesToPaise(v ?? '') == null
                      ? 'Enter a valid amount, e.g. 1500 or 1500.50'
                      : null,
                ),
                const SizedBox(height: 12),
                InkWell(
                  onTap: _pickDate,
                  borderRadius: BorderRadius.circular(14),
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Due date',
                      suffixIcon: Icon(Icons.calendar_today_outlined),
                    ),
                    child: Text(formatDate(toApiDate(_due))),
                  ),
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
                      : const Text('Bill all flats'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
