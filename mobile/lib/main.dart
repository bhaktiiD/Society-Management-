import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/push_service.dart';
import 'core/router.dart';
import 'core/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // The publishable key is designed to ship in the client; it is not a secret.
  await Supabase.initialize(
    url: 'https://tdzajtscinvnbcdthszg.supabase.co',
    publishableKey: 'sb_publishable_QX3faeAF2xk4uz_axcTICw_zs6QtWFM',
  );

  await initPush();

  runApp(const ProviderScope(child: SocietyOSApp()));
}

class SocietyOSApp extends ConsumerWidget {
  const SocietyOSApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'SocietyOS',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      themeMode: ThemeMode.light, // light by default
      routerConfig: ref.watch(routerProvider),
      // Respect the user's font size, but cap it so layouts cannot break.
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.4),
        ),
        child: child!,
      ),
    );
  }
}
