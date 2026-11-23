import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/widgets.dart';
import 'emergency_alert_screen.dart';
import 'emergency_repository.dart';

const _prefsKey = 'dismissed_emergency_ids';

/// Foreground emergency watcher: polls active emergencies every 8 s while the
/// app is open, pushes the full-screen alert for new ones, closes it when the
/// emergency is resolved, and shows a banner for dismissed-but-active ones.
///
/// NOTE: this covers the app being open only. Delivery to a background or
/// locked phone needs Firebase push (the backend already sends urgent FCM
/// when configured).
class EmergencyWatcher extends ConsumerStatefulWidget {
  const EmergencyWatcher({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<EmergencyWatcher> createState() => _EmergencyWatcherState();
}

class _EmergencyWatcherState extends ConsumerState<EmergencyWatcher> with WidgetsBindingObserver {
  Timer? _timer;
  final Set<int> _seen = {};
  late final ValueNotifier<Set<int>> _dismissed;

  @override
  void initState() {
    super.initState();
    _dismissed = ref.read(dismissedEmergenciesProvider);
    _dismissed.addListener(_saveDismissed);
    WidgetsBinding.instance.addObserver(this);
    _loadDismissed();
    _startPolling();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _dismissed.removeListener(_saveDismissed);
    _timer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startPolling();
    } else {
      _timer?.cancel();
      _timer = null;
    }
  }

  void _startPolling() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 8), (_) => _poll());
    _poll();
  }

  void _poll() {
    if (!mounted) return;
    try {
      ref.invalidate(activeEmergenciesProvider);
    } catch (_) {}
  }

  Future<void> _loadDismissed() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ids = (prefs.getStringList(_prefsKey) ?? []).map(int.tryParse).whereType<int>();
      if (!mounted) return;
      _dismissed.value = {..._dismissed.value, ...ids};
    } catch (_) {}
  }

  Future<void> _saveDismissed() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Keep only the most recent ids so the list never grows without bound.
      final ids = _dismissed.value.toList()..sort();
      final keep = ids.length > 50 ? ids.sublist(ids.length - 50) : ids;
      await prefs.setStringList(_prefsKey, [for (final i in keep) '$i']);
    } catch (_) {}
  }

  void _onList(List<Emergency> list) {
    try {
      final ids = {for (final e in list) e.id};

      // Close any open alert whose emergency is gone (resolved).
      for (final id in openAlertRoutes.keys.toList()) {
        if (_seen.contains(id) && !ids.contains(id)) {
          final route = openAlertRoutes[id];
          if (route != null && route.navigator != null) {
            route.navigator!.removeRoute(route);
            showSnack(context, 'The emergency was marked resolved');
          }
        }
      }
      _seen
        ..removeWhere((id) => !ids.contains(id))
        ..addAll(ids);

      if (openAlertRoutes.isNotEmpty) return;
      for (final e in list) {
        if (!e.mine && !_dismissed.value.contains(e.id)) {
          unawaited(showEmergencyAlert(Navigator.of(context), e));
          break;
        }
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<List<Emergency>>>(activeEmergenciesProvider, (_, next) {
      final data = next.value;
      if (data != null && !next.isLoading) _onList(data);
    });
    final list = ref.watch(activeEmergenciesProvider).value ?? const <Emergency>[];

    return Column(
      children: [
        ValueListenableBuilder<Set<int>>(
          valueListenable: _dismissed,
          builder: (context, dismissed, _) {
            final waiting = list.where((e) => dismissed.contains(e.id)).toList();
            if (waiting.isEmpty || openAlertRoutes.isNotEmpty) return const SizedBox.shrink();
            final e = waiting.first;
            return _Banner(
              emergency: e,
              onTap: () => unawaited(showEmergencyAlert(Navigator.of(context), e)),
            );
          },
        ),
        Expanded(child: widget.child),
      ],
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.emergency, required this.onTap});
  final Emergency emergency;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = 'Emergency active - ${emergency.whereLabel} needs help. Tap to open';
    return Semantics(
      button: true,
      label: text,
      excludeSemantics: true,
      child: Material(
        color: const Color(0xFFD92D20),
        child: InkWell(
          onTap: onTap,
          child: Container(
            width: double.infinity,
            constraints: const BoxConstraints(minHeight: 44),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(text,
                      style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
