import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'emergency_alert_screen.dart';
import 'emergency_repository.dart';

const _sosRed = Color(0xFFE5484D);

/// Floating red SOS button (bottom right). Tap = hint, long press = open sheet.
class SosButton extends StatelessWidget {
  const SosButton({super.key});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Emergency SOS',
      hint: 'Press and hold to send an emergency alert',
      child: Material(
        color: _sosRed,
        elevation: 6,
        shadowColor: const Color(0x66E5484D),
        shape: const CircleBorder(side: BorderSide(color: Colors.white, width: 3)),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () => showSnack(context, 'Press and hold for 2 seconds to send an emergency alert'),
          onLongPress: () => showSosSheet(context),
          child: const SizedBox(
            width: 60,
            height: 60,
            child: Center(
              child: Text('SOS',
                  style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w900)),
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> showSosSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (_) => const SosSheet(),
  );
}

class _Kind {
  const _Kind(this.id, this.label, this.icon, this.tint);
  final String id;
  final String label;
  final IconData icon;
  final Color tint;
}

const _kinds = [
  _Kind('fire', 'Fire', Icons.local_fire_department, Color(0xFFFFE9E0)),
  _Kind('medical', 'Medical', Icons.medical_services, Color(0xFFFDE8E6)),
  _Kind('security', 'Security', Icons.shield, Color(0xFFFFF1DB)),
  _Kind('other', 'Other help', Icons.sos, Color(0xFFFCE4EC)),
];

class SosSheet extends ConsumerStatefulWidget {
  const SosSheet({super.key});

  @override
  ConsumerState<SosSheet> createState() => _SosSheetState();
}

class _SosSheetState extends ConsumerState<SosSheet> {
  final _text = TextEditingController();
  String _kind = 'fire';
  bool _sending = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_sending) return;
    setState(() => _sending = true);
    final navigator = Navigator.of(context);
    final ctx = context;
    try {
      final e = await raiseEmergency(ref, kind: _kind, message: _text.text);
      if (!mounted) return;
      navigator.pop();
      unawaited(showEmergencyAlert(navigator, e));
    } catch (err) {
      if (!mounted) return;
      setState(() => _sending = false);
      // ignore: use_build_context_synchronously
      showSnack(ctx, errorMessage(err), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 12, 20, 20 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.muted.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text('Send emergency alert', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
          const SizedBox(height: 6),
          const Text(
            'Everyone in your society will be alerted right away with your name and flat number.',
            style: TextStyle(fontSize: 15, color: AppColors.muted, height: 1.35),
          ),
          const SizedBox(height: 16),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.5,
            children: [
              for (final k in _kinds)
                _KindTile(kind: k, selected: _kind == k.id, onTap: () => setState(() => _kind = k.id)),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _text,
            maxLength: 200,
            maxLines: 2,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'What is happening? (optional)'),
          ),
          const SizedBox(height: 8),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: _sosRed,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(56),
            ),
            onPressed: _sending ? null : _send,
            child: _sending
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 3, color: Colors.white),
                  )
                : const Text('Send alert now', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }
}

class _KindTile extends StatelessWidget {
  const _KindTile({required this.kind, required this.selected, required this.onTap});
  final _Kind kind;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: kind.label,
      excludeSemantics: true,
      child: Material(
        color: kind.tint,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: selected ? _sosRed : Colors.transparent, width: 2.5),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(kind.icon, size: 34, color: AppColors.error),
              const SizedBox(height: 6),
              Text(kind.label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            ],
          ),
        ),
      ),
    );
  }
}
