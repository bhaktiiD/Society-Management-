import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/emergency/emergency_repository.dart';
import 'api_client.dart';

/// Android channel the backend targets for emergencies (see push.py).
/// Max importance: heads-up, sound and vibration. It buzzes in vibrate mode;
/// a fully silent phone or Do Not Disturb needs the user's own override.
const _emergencyChannel = AndroidNotificationChannel(
  'emergency',
  'Emergency alerts',
  description: 'Fire, medical and security alerts from your society',
  importance: Importance.max,
  playSound: true,
  enableVibration: true,
  enableLights: true,
  showBadge: true,
);

/// Call once from main(). Never throws: push is a convenience, the app works without it.
Future<void> initPush() async {
  try {
    await Firebase.initializeApp();
    final plugin = FlutterLocalNotificationsPlugin();
    await plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_emergencyChannel);
  } catch (e) {
    debugPrint('Push unavailable: $e');
  }
}

/// Asks for permission, sends this phone's token to the backend and keeps it fresh.
/// Watched once from the signed-in shell.
final pushRegistrationProvider = FutureProvider<void>((ref) async {
  try {
    final messaging = FirebaseMessaging.instance;
    await messaging.requestPermission(alert: true, sound: true, badge: true);
    final dio = ref.read(dioProvider);

    Future<void> send(String? token) async {
      if (token == null) return;
      try {
        await dio.post('/me/device-token', data: {'token': token});
      } catch (_) {/* retried on next start / refresh */}
    }

    await send(await messaging.getToken());
    final refreshSub = messaging.onTokenRefresh.listen(send);
    // App open: refresh the alert list right away instead of waiting for the next poll.
    final msgSub = FirebaseMessaging.onMessage.listen((m) {
      if (m.data['type'] == 'emergency') ref.invalidate(activeEmergenciesProvider);
    });
    ref.onDispose(() {
      refreshSub.cancel();
      msgSub.cancel();
    });
  } catch (e) {
    debugPrint('Push registration skipped: $e');
  }
});
