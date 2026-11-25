import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/emergency/emergency_repository.dart';
import 'api_client.dart';

/// Android channel the backend targets for emergencies (see push.py).
/// Alarm audio usage plays on the alarm volume, so it sounds even when the
/// phone is on silent or vibrate. The id is new because Android freezes a
/// channel's sound settings once it is created.
const emergencyChannelId = 'emergency_alarm';
const _emergencyChannel = AndroidNotificationChannel(
  emergencyChannelId,
  'Emergency alarm',
  description: 'Loud alarm for fire, medical and security alerts from your society',
  importance: Importance.max,
  playSound: true,
  sound: RawResourceAndroidNotificationSound('siren'),
  audioAttributesUsage: AudioAttributesUsage.alarm,
  enableVibration: true,
  enableLights: true,
  showBadge: true,
);

final _local = FlutterLocalNotificationsPlugin();

/// Call once from main(). Never throws: push is a convenience, the app works without it.
Future<void> initPush() async {
  try {
    await Firebase.initializeApp();
    await _local.initialize(
      settings: const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')),
    );
    final android =
        _local.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await android?.createNotificationChannel(_emergencyChannel);
    await android?.deleteNotificationChannel(channelId: 'emergency');
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
      if (m.data['type'] != 'emergency') return;
      ref.invalidate(activeEmergenciesProvider);
      // FCM shows nothing while the app is open, so sound the alarm ourselves.
      unawaited(_local.show(
        id: 911,
        title: m.notification?.title ?? 'EMERGENCY',
        body: m.notification?.body,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            emergencyChannelId,
            _emergencyChannel.name,
            importance: Importance.max,
            priority: Priority.max,
            sound: _emergencyChannel.sound,
            audioAttributesUsage: AudioAttributesUsage.alarm,
            category: AndroidNotificationCategory.alarm,
            fullScreenIntent: true,
          ),
        ),
      ));
    });
    ref.onDispose(() {
      refreshSub.cancel();
      msgSub.cancel();
    });
  } catch (e) {
    debugPrint('Push registration skipped: $e');
  }
});
