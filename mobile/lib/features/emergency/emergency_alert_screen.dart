import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vibration/vibration.dart';

import '../../core/api_client.dart';
import '../../core/widgets.dart';
import '../auth/auth_repository.dart';
import 'emergency_repository.dart';

/// Emergency ids the person has acknowledged on this device.
final dismissedEmergenciesProvider =
    Provider<ValueNotifier<Set<int>>>((ref) => ValueNotifier<Set<int>>(<int>{}));

/// Alert screens currently open, by emergency id. Prevents stacking a second
/// alert and lets the watcher close one when its emergency is resolved.
final Map<int, Route<void>> openAlertRoutes = {};

/// Pushes [EmergencyAlertScreen] unless an alert is already on screen.
Future<void> showEmergencyAlert(NavigatorState navigator, Emergency e) async {
  if (openAlertRoutes.isNotEmpty) return;
  final route = MaterialPageRoute<void>(
    fullscreenDialog: true,
    builder: (_) => EmergencyAlertScreen(emergency: e),
  );
  openAlertRoutes[e.id] = route;
  try {
    await navigator.push<void>(route);
  } finally {
    openAlertRoutes.remove(e.id);
  }
}

const _red1 = Color(0xFFB42318);
const _red2 = Color(0xFFE5484D);

String _ago(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'Just now';
  if (d.inMinutes < 60) return '${d.inMinutes} min ago';
  final h = d.inHours;
  return '$h hour${h == 1 ? '' : 's'} ago';
}

class EmergencyAlertScreen extends ConsumerStatefulWidget {
  const EmergencyAlertScreen({super.key, required this.emergency});
  final Emergency emergency;

  @override
  ConsumerState<EmergencyAlertScreen> createState() => _EmergencyAlertScreenState();
}

class _EmergencyAlertScreenState extends ConsumerState<EmergencyAlertScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  late final ValueNotifier<Set<int>> _dismissed;
  Timer? _hapticTimer;
  Timer? _clock;
  bool _busy = false;

  Emergency get _e => widget.emergency;

  @override
  void initState() {
    super.initState();
    _dismissed = ref.read(dismissedEmergenciesProvider);
    _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
    _clock = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
    _startVibration();
  }

  /// Vibration (not sound) so it still works in silent mode.
  Future<void> _startVibration() async {
    try {
      final has = await Vibration.hasVibrator();
      if (!mounted) return;
      if (has) {
        final amp = await Vibration.hasAmplitudeControl();
        if (!mounted) return;
        await Vibration.vibrate(
          pattern: const [0, 800, 400, 800, 400, 1200],
          intensities: amp ? const [0, 255, 0, 255, 0, 255] : const [],
          repeat: 0,
        );
        if (!mounted) Vibration.cancel();
        return;
      }
    } catch (_) {
      // fall through to haptics
    }
    if (!mounted) return;
    _hapticTimer = Timer.periodic(const Duration(seconds: 2), (_) => HapticFeedback.heavyImpact());
    HapticFeedback.heavyImpact();
  }

  @override
  void dispose() {
    _hapticTimer?.cancel();
    _clock?.cancel();
    _pulse.dispose();
    try {
      Vibration.cancel();
    } catch (_) {}
    super.dispose();
  }

  void _markSeen() {
    _dismissed.value = {..._dismissed.value, _e.id};
  }

  Future<void> _resolve() async {
    if (_busy) return;
    setState(() => _busy = true);
    final ctx = context;
    final navigator = Navigator.of(context);
    try {
      await ref.read(emergencyRepositoryProvider).resolve(_e.id);
      ref.invalidate(activeEmergenciesProvider);
      if (!mounted) return;
      navigator.pop();
    } catch (err) {
      if (!mounted) return;
      setState(() => _busy = false);
      // ignore: use_build_context_synchronously
      showSnack(ctx, errorMessage(err), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = ref.watch(activeRoleProvider) == AppRole.secretary;
    final canResolve = _e.mine || isAdmin;
    final e = _e;

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _markSeen();
      },
      child: Scaffold(
        backgroundColor: _red1,
        body: Container(
          width: double.infinity,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [_red1, _red2],
            ),
          ),
          child: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
              child: Column(
                children: [
                  ScaleTransition(
                    scale: Tween<double>(begin: 0.9, end: 1.2)
                        .animate(CurvedAnimation(parent: _pulse, curve: Curves.easeInOut)),
                    child: Semantics(
                      label: 'Emergency siren',
                      child: const Icon(Icons.crisis_alert, size: 96, color: Colors.white),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text('EMERGENCY',
                      style: TextStyle(
                          color: Colors.white70, fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: 4)),
                  const SizedBox(height: 6),
                  Text(e.kindLabel,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: Colors.white, fontSize: 52, fontWeight: FontWeight.w900, height: 1.05)),
                  const SizedBox(height: 16),
                  Text(e.mine ? '${e.raisedByName} (you)' : e.raisedByName,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Text(e.whereLabel,
                      style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    alignment: WrapAlignment.center,
                    children: [
                      if (e.roleLabel.isNotEmpty) _Pill(e.roleLabel),
                      _Pill(_ago(e.createdAt)),
                    ],
                  ),
                  if (e.message != null) ...[
                    const SizedBox(height: 18),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Text(e.message!,
                          style: const TextStyle(color: Colors.white, fontSize: 18, height: 1.35)),
                    ),
                  ],
                  const SizedBox(height: 18),
                  _CallTile(name: e.raisedByName, phone: e.phone),
                  const SizedBox(height: 18),
                  if (canResolve)
                    _WhiteButton(
                      label: e.mine ? 'I am safe / Mark as resolved' : 'Mark as resolved',
                      busy: _busy,
                      filled: true,
                      onPressed: _resolve,
                    ),
                  if (!e.mine) ...[
                    if (canResolve) const SizedBox(height: 12),
                    _WhiteButton(
                      label: 'I have seen this',
                      filled: !canResolve,
                      onPressed: () {
                        _markSeen();
                        Navigator.of(context).pop();
                      },
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.22),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
      );
}

class _CallTile extends StatelessWidget {
  const _CallTile({required this.name, required this.phone});
  final String name;
  final String? phone;

  @override
  Widget build(BuildContext context) {
    final first = name.trim().split(' ').first;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
      child: Row(
        children: [
          const Icon(Icons.call, size: 32, color: _red1),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Call $first', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                phone == null
                    ? const Text('No phone number available', style: TextStyle(fontSize: 15))
                    : SelectableText(phone!, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WhiteButton extends StatelessWidget {
  const _WhiteButton({required this.label, required this.onPressed, this.filled = false, this.busy = false});
  final String label;
  final VoidCallback onPressed;
  final bool filled;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final child = busy
        ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 3, color: _red1))
        : Text(label, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800));
    final size = const Size.fromHeight(56);
    return SizedBox(
      width: double.infinity,
      child: filled
          ? FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: _red1, minimumSize: size),
              onPressed: busy ? null : onPressed,
              child: child,
            )
          : OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white, width: 2),
                minimumSize: size,
              ),
              onPressed: onPressed,
              child: child,
            ),
    );
  }
}
