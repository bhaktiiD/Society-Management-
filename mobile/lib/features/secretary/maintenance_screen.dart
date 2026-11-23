import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../models/models.dart';
import 'secretary_repository.dart';

/// Admin: the standing monthly maintenance rate and late fee for each flat
/// type, and the due day. Set once, edit any time; bills are then created
/// automatically every month.
class MaintenanceScreen extends ConsumerStatefulWidget {
  const MaintenanceScreen({super.key});

  @override
  ConsumerState<MaintenanceScreen> createState() => _MaintenanceScreenState();
}

class _MaintenanceScreenState extends ConsumerState<MaintenanceScreen> {
  final _busy = ValueNotifier<bool>(false);

  @override
  void dispose() {
    _busy.dispose();
    super.dispose();
  }

  void _refresh(WidgetRef ref) {
    ref.invalidate(billingSettingsProvider);
    ref.invalidate(secretaryChargesProvider);
    ref.invalidate(collectionsProvider);
  }

  Future<void> _editRate(BuildContext context, WidgetRef ref, PlanRate plan) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (_) => _RateSheet(plan: plan),
    );
    if (saved == true) {
      _refresh(ref);
      if (context.mounted) showSnack(context, '${plan.flatType} rate saved');
    }
  }

  Future<void> _editDueDay(BuildContext context, WidgetRef ref, int current) async {
    final day = await showDialog<int>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Due day of the month'),
        children: [
          SizedBox(
            width: double.maxFinite,
            height: 320,
            child: ListView.builder(
              itemCount: 28,
              itemBuilder: (_, i) {
                final d = i + 1;
                return ListTile(
                  title: Text(ordinal(d)),
                  trailing: d == current
                      ? const Icon(Icons.check, color: AppColors.greenDark)
                      : null,
                  onTap: () => Navigator.pop(ctx, d),
                );
              },
            ),
          ),
        ],
      ),
    );
    if (day == null || day == current || !context.mounted) return;
    try {
      await ref.read(secretaryRepositoryProvider).setDueDay(day);
      _refresh(ref);
      if (context.mounted) showSnack(context, 'Bills now fall due on the ${ordinal(day)}');
    } catch (error) {
      if (context.mounted) showSnack(context, errorMessage(error), error: true);
    }
  }

  Future<void> _generate(BuildContext context, WidgetRef ref) async {
    if (_busy.value) return;
    _busy.value = true;
    try {
      final r = await ref.read(secretaryRepositoryProvider).runBilling();
      _refresh(ref);
      if (!context.mounted) return;
      final bills = r['bills_created'] as int;
      final fees = r['late_fees_created'] as int;
      showSnack(
        context,
        bills == 0 && fees == 0
            ? 'Everything is up to date'
            : 'Created $bills bills and $fees late fees',
      );
    } catch (error) {
      if (context.mounted) showSnack(context, errorMessage(error), error: true);
    } finally {
      _busy.value = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(billingSettingsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Maintenance')),
      body: AsyncBody<BillingSettings>(
        value: settings,
        onRetry: () => ref.invalidate(billingSettingsProvider),
        builder: (s) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            const _NoteBox(
              'Set your rates once. New bills use them every month; bills already sent keep their old amount.',
            ),
            if (s.untypedFlats > 0) ...[
              const SizedBox(height: 16),
              _WarningCard(
                '${s.untypedFlats} ${s.untypedFlats == 1 ? 'flat has' : 'flats have'} no type yet '
                'and will not be billed. Set it in the Flats tab.',
              ),
            ],
            if (!s.anyRateSet) ...[
              const SizedBox(height: 16),
              const _WarningCard('Set at least one rate to start monthly billing.'),
            ],
            const _Label('Rates by flat type'),
            for (var i = 0; i < s.plans.length; i++) ...[
              if (i > 0) const SizedBox(height: 12),
              _RateCard(
                plan: s.plans[i],
                accent: _accents[i % _accents.length],
                onEdit: () => _editRate(context, ref, s.plans[i]),
              ),
            ],
            const SizedBox(height: 24),
            const _Label('Due date'),
            _DueCard(day: s.dueDay, onEdit: () => _editDueDay(context, ref, s.dueDay)),
            const SizedBox(height: 8),
            const Text(
              'A fixed late fee is added once to any bill still unpaid after this day.',
              style: TextStyle(fontSize: 13, height: 1.4, color: AppColors.muted, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 24),
            ValueListenableBuilder<bool>(
              valueListenable: _busy,
              builder: (_, busy, _) => OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.greenDark,
                  backgroundColor: AppColors.greenTint,
                  side: const BorderSide(color: AppColors.green, width: 1.5),
                ),
                onPressed: busy ? null : () => _generate(context, ref),
                icon: busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh),
                label: const Text('Generate bills now'),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Creates any bills that are due.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: AppColors.muted, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 24, bottom: 8),
        child: Text(
          text,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.muted),
        ),
      );
}

/// One soft colour per flat type: icon colour + pastel gradient.
class _Accent {
  const _Accent(this.color, this.gradient, this.icon);
  final Color color;
  final List<Color> gradient;
  final IconData icon;
}

const _accents = [
  _Accent(AppColors.teal, AppGradients.teal, Icons.single_bed_outlined),
  _Accent(AppColors.purple, AppGradients.purple, Icons.bed_outlined),
  _Accent(AppColors.orange, AppGradients.orange, Icons.weekend_outlined),
  _Accent(AppColors.rose, AppGradients.rose, Icons.chair_outlined),
];

class _NoteBox extends StatelessWidget {
  const _NoteBox(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: AppGradients.green),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.auto_awesome_rounded, size: 20, color: AppColors.greenDark),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(fontSize: 13, height: 1.4, fontWeight: FontWeight.w600, color: AppColors.greenDark),
              ),
            ),
          ],
        ),
      );
}

class _RateCard extends StatelessWidget {
  const _RateCard({required this.plan, required this.accent, required this.onEdit});
  final PlanRate plan;
  final _Accent accent;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onEdit,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 6, 10, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: accent.gradient),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(accent.icon, size: 20, color: accent.color),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        plan.flatType,
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                      ),
                    ),
                    if (plan.isSet) TextButton(onPressed: onEdit, child: const Text('Edit')),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 56),
                  child: plan.isSet
                      ? IntrinsicHeight(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(
                                child: _Figure(
                                  'Monthly maintenance',
                                  formatRupees(plan.amountPaise!),
                                  color: AppColors.greenDark,
                                ),
                              ),
                              const VerticalDivider(width: 24),
                              Expanded(
                                child: _Figure(
                                  'Late fee',
                                  formatRupees(plan.penaltyPaise ?? 0),
                                  color: AppColors.orange,
                                ),
                              ),
                            ],
                          ),
                        )
                      : Row(
                          children: [
                            const Expanded(
                              child: Text(
                                'Not set yet',
                                style: TextStyle(fontSize: 14, color: AppColors.muted, fontWeight: FontWeight.w500),
                              ),
                            ),
                            const SizedBox(width: 12),
                            FilledButton(
                              onPressed: onEdit,
                              style: FilledButton.styleFrom(
                                minimumSize: const Size(0, 44),
                                padding: const EdgeInsets.symmetric(horizontal: 20),
                              ),
                              child: const Text('Set rate'),
                            ),
                          ],
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure(this.label, this.value, {this.color = AppColors.ink});
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 13, fontWeight: FontWeight.w500)),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: color)),
        ),
      ],
    );
  }
}

class _DueCard extends StatelessWidget {
  const _DueCard({required this.day, required this.onEdit});
  final int day;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onEdit,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 10, 14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: AppGradients.teal),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.event_available_rounded, color: AppColors.teal),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Bills fall due on',
                      style: TextStyle(color: AppColors.muted, fontSize: 13, fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'The ${ordinal(day)} of every month',
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.teal),
                    ),
                  ],
                ),
              ),
              TextButton(onPressed: onEdit, child: const Text('Edit')),
            ],
          ),
        ),
      ),
    );
  }
}

class _WarningCard extends StatelessWidget {
  const _WarningCard(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.warningTint, borderRadius: BorderRadius.circular(20)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber_rounded, color: AppColors.warningDark, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(height: 1.4, fontSize: 13, fontWeight: FontWeight.w500))),
        ],
      ),
    );
  }
}

/// Bottom sheet to set or change one flat type's monthly rate and late fee.
class _RateSheet extends ConsumerStatefulWidget {
  const _RateSheet({required this.plan});
  final PlanRate plan;

  @override
  ConsumerState<_RateSheet> createState() => _RateSheetState();
}

class _RateSheetState extends ConsumerState<_RateSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amount;
  late final TextEditingController _penalty;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _amount = TextEditingController(
      text: widget.plan.amountPaise == null ? '' : paiseToInput(widget.plan.amountPaise!),
    );
    _penalty = TextEditingController(
      text: widget.plan.penaltyPaise == null ? '' : paiseToInput(widget.plan.penaltyPaise!),
    );
  }

  @override
  void dispose() {
    _amount.dispose();
    _penalty.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await ref.read(secretaryRepositoryProvider).setPlan(
            widget.plan.flatType,
            amountPaise: parseRupeesToPaise(_amount.text)!,
            penaltyPaise: parseRupeesAllowZero(_penalty.text)!,
          );
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
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 4, 20, 20 + bottom),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${widget.plan.flatType} flats',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _amount,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Monthly maintenance',
                prefixText: '₹ ',
              ),
              validator: (v) =>
                  parseRupeesToPaise(v ?? '') == null ? 'Enter an amount, e.g. 2500' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _penalty,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _save(),
              decoration: const InputDecoration(
                labelText: 'Late fee if unpaid after the due date',
                prefixText: '₹ ',
                helperText: 'Enter 0 for no late fee.',
              ),
              validator: (v) =>
                  parseRupeesAllowZero(v ?? '') == null ? 'Enter an amount, or 0' : null,
            ),
            const SizedBox(height: 20),
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
        )),
      ),
    );
  }
}
