import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../models/models.dart';
import 'gate_pass_repository.dart';
import 'guests_repository.dart';

/// Guard's gate screen: request entry, then check guests in and out.
class GuardScreen extends ConsumerStatefulWidget {
  const GuardScreen({super.key});

  @override
  ConsumerState<GuardScreen> createState() => _GuardScreenState();
}

class _GuardScreenState extends ConsumerState<GuardScreen> {
  Timer? _poll;
  final _working = <int>{};

  @override
  void initState() {
    super.initState();
    // Pick up residents' decisions without needing push notifications.
    _poll = Timer.periodic(const Duration(seconds: 8), (_) {
      if (mounted) ref.invalidate(guardGuestsProvider);
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _act(GuestRequest g, Future<void> Function() action, String done) async {
    setState(() => _working.add(g.id));
    try {
      await action();
      if (mounted) showSnack(context, done);
    } catch (error) {
      if (mounted) showSnack(context, errorMessage(error), error: true);
    } finally {
      if (mounted) {
        ref.invalidate(guardGuestsProvider);
        setState(() => _working.remove(g.id));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final guests = ref.watch(guardGuestsProvider);
    final repo = ref.read(guestsRepositoryProvider);

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final sent = await Navigator.of(context).push<bool>(
            MaterialPageRoute(builder: (_) => const GuestFormScreen()),
          );
          if (sent == true && mounted) ref.invalidate(guardGuestsProvider);
        },
        icon: const Icon(Icons.add),
        label: const Text('New guest'),
      ),
      body: AsyncBody<List<GuestRequest>>(
        value: guests,
        onRetry: () => ref.invalidate(guardGuestsProvider),
        builder: (list) {
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(guardGuestsProvider);
              ref.invalidate(guardPassesTodayProvider);
              await refreshProvider(() => ref.read(guardGuestsProvider.future));
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              children: [
                const _VerifyCard(),
                const _ExpectedToday(),
                if (list.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 32),
                    child: EmptyState(
                      icon: Icons.door_front_door_outlined,
                      message: 'No guests yet.\nTap "New guest" when someone arrives.',
                    ),
                  ),
                for (final g in list)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: _GuestCard(
                      guest: g,
                      busy: _working.contains(g.id),
                      onCheckIn: () => _act(g, () => repo.checkIn(g.id), 'Checked in'),
                      onCheckOut: () => _act(g, () => repo.checkOut(g.id), 'Checked out'),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _GuestCard extends StatelessWidget {
  const _GuestCard({
    required this.guest,
    required this.busy,
    required this.onCheckIn,
    required this.onCheckOut,
  });
  final GuestRequest guest;
  final bool busy;
  final VoidCallback onCheckIn;
  final VoidCallback onCheckOut;

  @override
  Widget build(BuildContext context) {
    final (label, tone) = switch (guest.status) {
      'pending' => ('Waiting for resident', ChipTone.warning),
      'approved' => ('Approved', ChipTone.success),
      'checked_in' => ('Inside', ChipTone.info),
      'checked_out' => ('Left', ChipTone.neutral),
      'denied' => ('Denied', ChipTone.error),
      'expired' => ('Expired', ChipTone.neutral),
      _ => (guest.status, ChipTone.neutral),
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const IconBadge(Icons.person_outline),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        guest.guestName,
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Flat ${guest.flatNumber ?? '-'} · ${formatDateTime(guest.createdAt)}',
                        style: const TextStyle(color: AppColors.muted, fontSize: 14),
                      ),
                      const SizedBox(height: 6),
                      StatusChip(label, tone: tone),
                    ],
                  ),
                ),
              ],
            ),
            if (guest.status == 'approved') ...[
              const SizedBox(height: 12),
              FilledButton(
                onPressed: busy ? null : onCheckIn,
                child: const Text('Check in'),
              ),
            ],
            if (guest.status == 'checked_in') ...[
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: busy ? null : onCheckOut,
                child: const Text('Check out'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _VerifyCard extends StatelessWidget {
  const _VerifyCard();

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.green,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          showDragHandle: true,
          backgroundColor: Colors.white,
          builder: (_) => const _VerifySheet(),
        ),
        child: const Padding(
          padding: EdgeInsets.all(18),
          child: Row(
            children: [
              Icon(Icons.vpn_key_rounded, color: AppColors.onGreen, size: 30),
              SizedBox(width: 14),
              Expanded(
                child: Text(
                  'Verify gate pass',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.onGreen),
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: AppColors.onGreen),
            ],
          ),
        ),
      ),
    );
  }
}

class _ExpectedToday extends ConsumerWidget {
  const _ExpectedToday();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(guardPassesTodayProvider).asData?.value ?? const <GatePass>[];
    if (list.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('Expected today'),
        for (final p in list)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: TileCard(
              leading: const IconBadge(Icons.badge_outlined),
              title: p.visitorName,
              subtitle: 'Flat ${p.flatNumber ?? '-'} · ${validityText(p.validDays)}',
            ),
          ),
      ],
    );
  }
}

class _VerifySheet extends ConsumerStatefulWidget {
  const _VerifySheet();

  @override
  ConsumerState<_VerifySheet> createState() => _VerifySheetState();
}

class _VerifySheetState extends ConsumerState<_VerifySheet> {
  final _code = TextEditingController();
  PassVerification? _result;
  bool _busy = false;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    final code = _code.text.replaceAll(RegExp(r'\s'), '').toUpperCase();
    if (code.isEmpty) return;
    setState(() {
      _busy = true;
      _result = null;
    });
    try {
      final r = await ref.read(gatePassRepositoryProvider).verify(code);
      if (mounted) setState(() => _result = r);
    } catch (e) {
      if (mounted) showSnack(context, errorMessage(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _allow() async {
    final r = _result;
    if (r == null) return;
    setState(() => _busy = true);
    try {
      await ref.read(gatePassRepositoryProvider).checkIn(r.pass.id);
      ref.invalidate(guardGuestsProvider);
      ref.invalidate(guardPassesTodayProvider);
      if (mounted) {
        showSnack(context, 'Visitor checked in');
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        showSnack(context, errorMessage(e), error: true);
        setState(() => _busy = false);
      }
    }
  }

  Widget _line(String k, String? v) => v == null || v.isEmpty
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 90, child: Text(k, style: const TextStyle(color: AppColors.muted))),
              Expanded(child: Text(v, style: const TextStyle(fontWeight: FontWeight.w700))),
            ],
          ),
        );

  @override
  Widget build(BuildContext context) {
    final r = _result;
    final p = r?.pass;
    const spinner = SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 3));
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Verify gate pass', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 14),
              TextField(
                controller: _code,
                autofocus: true,
                maxLength: 9,
                textCapitalization: TextCapitalization.characters,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) {
                  if (!_busy) _check();
                },
                inputFormatters: [_UpperCaseFormatter()],
                style: const TextStyle(
                    fontFamily: 'monospace', fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: 3),
                decoration: const InputDecoration(labelText: 'Enter pass code', counterText: ''),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _busy ? null : _check,
                child: _busy && r == null ? spinner : const Text('Check pass'),
              ),
              if (r != null && p != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: r.valid ? AppColors.greenTint : AppColors.errorTint,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(p.visitorName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                      if (!r.valid)
                        Padding(
                          padding: const EdgeInsets.only(top: 4, bottom: 6),
                          child: Text(
                            r.reason ?? 'This pass cannot be used.',
                            style: const TextStyle(
                                color: AppColors.error, fontWeight: FontWeight.w800, fontSize: 15),
                          ),
                        ),
                      const SizedBox(height: 6),
                      _line('Phone', p.visitorPhone),
                      _line('Flat', p.flatNumber),
                      _line('Resident', p.ownerNames.isEmpty ? null : p.ownerNames.join(', ')),
                      _line('Purpose', p.purpose),
                      _line('Vehicle', p.vehicleNumber),
                      _line('Valid', '${formatPassDate(p.visitDate)} to ${formatPassDate(p.validUntil)}'),
                    ],
                  ),
                ),
                if (r.valid) ...[
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: _busy ? null : _allow,
                    child: _busy ? spinner : const Text('Allow entry'),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _UpperCaseFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue old, TextEditingValue n) =>
      n.copyWith(text: n.text.toUpperCase());
}

class GuestFormScreen extends ConsumerStatefulWidget {
  const GuestFormScreen({super.key});

  @override
  ConsumerState<GuestFormScreen> createState() => _GuestFormScreenState();
}

class _GuestFormScreenState extends ConsumerState<GuestFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _flat = TextEditingController();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _purpose = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _flat.dispose();
    _name.dispose();
    _phone.dispose();
    _purpose.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await ref.read(guestsRepositoryProvider).requestEntry(
            flatNumber: _flat.text.trim(),
            guestName: _name.text.trim(),
            phone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
            purpose: _purpose.text.trim().isEmpty ? null : _purpose.text.trim(),
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
    String? required(String? v, String msg) => (v == null || v.trim().isEmpty) ? msg : null;
    return Scaffold(
      appBar: AppBar(title: const Text('New guest')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _flat,
                  textInputAction: TextInputAction.next,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(labelText: 'Visiting flat', hintText: 'e.g. A-101'),
                  validator: (v) => required(v, 'Enter the flat number'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _name,
                  textInputAction: TextInputAction.next,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Guest name'),
                  validator: (v) => required(v, "Enter the guest's name"),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(labelText: 'Phone (optional)'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _purpose,
                  textInputAction: TextInputAction.done,
                  decoration: const InputDecoration(labelText: 'Purpose (optional)', hintText: 'Delivery, relative, ...'),
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
                      : const Text('Ask resident to approve'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
