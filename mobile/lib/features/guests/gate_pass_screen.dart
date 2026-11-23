import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'gate_pass_form_screen.dart';
import 'gate_pass_repository.dart';

(String, ChipTone) passStatus(String status) => switch (status) {
      'active' => ('Active', ChipTone.success),
      'used' => ('Used', ChipTone.neutral),
      'expired' => ('Expired', ChipTone.warning),
      'cancelled' => ('Cancelled', ChipTone.error),
      _ => (status, ChipTone.neutral),
    };

const _howItWorks = 'Share this code with your visitor. The guard will check it at the gate.';

/// Pass list + create button WITHOUT a Scaffold (embedded in the Visitors tab).
class GatePassBody extends ConsumerWidget {
  const GatePassBody({super.key});

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    GatePass? created;
    final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => GatePassFormScreen(onCreated: (p) => created = p),
    ));
    if (ok != true) return;
    ref.invalidate(gatePassesProvider);
    if (created != null && context.mounted) await showPassCreatedSheet(context, created!);
  }

  Future<void> _cancel(BuildContext context, WidgetRef ref, GatePass p) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel this pass?'),
        content: Text('${p.visitorName} will no longer be able to enter with this code.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep it')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Cancel pass'),
          ),
        ],
      ),
    );
    if (yes != true) return;
    try {
      await ref.read(gatePassRepositoryProvider).cancel(p.id);
      if (context.mounted) showSnack(context, 'Pass cancelled');
    } catch (e) {
      if (context.mounted) showSnack(context, errorMessage(e), error: true);
    } finally {
      ref.invalidate(gatePassesProvider);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final passes = ref.watch(gatePassesProvider);
    return Stack(
      children: [
        AsyncBody<List<GatePass>>(
          value: passes,
          onRetry: () => ref.invalidate(gatePassesProvider),
          builder: (list) {
            Future<void> refresh() async {
              ref.invalidate(gatePassesProvider);
              await refreshProvider(() => ref.read(gatePassesProvider.future));
            }

            if (list.isEmpty) {
              return RefreshIndicator(
                onRefresh: refresh,
                child: LayoutBuilder(
                  builder: (_, box) => ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      SizedBox(
                        height: box.maxHeight,
                        child: const EmptyState(
                          icon: Icons.vpn_key_outlined,
                          message: 'No gate passes yet\n\n$_howItWorks',
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }
            final active = list.where((p) => p.isActive).toList();
            final earlier = list.where((p) => !p.isActive).toList();
            Widget card(GatePass p) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: PassCard(
                    pass: p,
                    onTap: () => showPassDetails(context, p),
                    onCancel: p.isActive ? () => _cancel(context, ref, p) : null,
                  ),
                );
            return RefreshIndicator(
              onRefresh: refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                children: [
                  if (active.isNotEmpty) ...[
                    const SectionHeader('Active passes'),
                    for (final p in active) card(p),
                  ],
                  if (earlier.isNotEmpty) ...[
                    const SectionHeader('Earlier'),
                    for (final p in earlier) card(p),
                  ],
                ],
              ),
            );
          },
        ),
        // Bottom-right, like every other add button (SOS only shows on the Home tab).
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton.extended(
            heroTag: 'new-gate-pass',
            onPressed: () => _create(context, ref),
            icon: const Icon(Icons.add),
            label: const Text('New gate pass'),
          ),
        ),
      ],
    );
  }
}

class GatePassScreen extends StatelessWidget {
  const GatePassScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      Scaffold(appBar: AppBar(title: const Text('Gate passes')), body: const GatePassBody());
}

/// Big grouped code with a copy button.
class PassCodeChip extends StatelessWidget {
  const PassCodeChip(this.code, {super.key, this.fontSize = 22});
  final String code;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(left: 16),
      decoration: BoxDecoration(color: AppColors.greenTint, borderRadius: BorderRadius.circular(16)),
      child: Row(
        children: [
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: SelectableText(
                formatPassCode(code),
                maxLines: 1,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: fontSize,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 2,
                  color: AppColors.greenDark,
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Copy code',
            icon: const Icon(Icons.copy_rounded, color: AppColors.greenDark),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: code));
              if (context.mounted) showSnack(context, 'Code copied');
            },
          ),
        ],
      ),
    );
  }
}

class PassCard extends StatelessWidget {
  const PassCard({super.key, required this.pass, required this.onTap, this.onCancel});
  final GatePass pass;
  final VoidCallback onTap;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final (label, tone) = passStatus(pass.status);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(pass.visitorName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                  ),
                  const SizedBox(width: 8),
                  StatusChip(label, tone: tone),
                ],
              ),
              const SizedBox(height: 4),
              Text('${formatPassDate(pass.visitDate)}, ${validityText(pass.validDays)}',
                  style: const TextStyle(color: AppColors.muted, fontSize: 14)),
              if (pass.purpose != null)
                Text(pass.purpose!, style: const TextStyle(color: AppColors.muted, fontSize: 14)),
              if (pass.passCode != null) ...[
                const SizedBox(height: 12),
                PassCodeChip(pass.passCode!),
              ],
              if (onCancel != null)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: onCancel,
                    style: TextButton.styleFrom(foregroundColor: AppColors.error),
                    child: const Text('Cancel pass'),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> showPassDetails(BuildContext context, GatePass p) {
  final (label, tone) = passStatus(p.status);
  Widget row(String k, String? v) => v == null
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                  width: 110,
                  child: Text(k, style: const TextStyle(color: AppColors.muted, fontSize: 14))),
              Expanded(
                  child: Text(v, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700))),
            ],
          ),
        );
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Colors.white,
    builder: (_) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(children: [
              Expanded(
                  child: Text(p.visitorName,
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800))),
              StatusChip(label, tone: tone),
            ]),
            if (p.passCode != null) ...[
              const SizedBox(height: 12),
              PassCodeChip(p.passCode!),
            ],
            const SizedBox(height: 8),
            row('Phone', p.visitorPhone),
            row('Email', p.visitorEmail),
            row('Vehicle', p.vehicleNumber),
            row('Purpose', p.purpose),
            row('Visit date', '${formatPassDate(p.visitDate)}, ${validityText(p.validDays)}'),
            row('Valid until', formatPassDate(p.validUntil)),
            row('Flat', p.flatNumber),
            row('Created by', p.createdByName),
            row('Used at', p.usedAt),
            const SizedBox(height: 12),
            const Text('How it works',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.muted)),
            const SizedBox(height: 4),
            const Text(_howItWorks, style: TextStyle(color: AppColors.muted, fontSize: 14)),
          ],
        ),
      ),
    ),
  );
}

Future<void> showPassCreatedSheet(BuildContext context, GatePass p) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    backgroundColor: Colors.white,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Gate pass created',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 16),
            if (p.passCode != null) PassCodeChip(p.passCode!, fontSize: 30),
            const SizedBox(height: 12),
            Text('Share this code with ${p.visitorName}',
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.muted, fontSize: 15)),
            const SizedBox(height: 16),
            if (p.passCode != null)
              OutlinedButton.icon(
                icon: const Icon(Icons.copy_rounded),
                label: const Text('Copy'),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: p.passCode!));
                  if (ctx.mounted) showSnack(ctx, 'Code copied');
                },
              ),
            const SizedBox(height: 8),
            FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Done')),
          ],
        ),
      ),
    ),
  );
}
