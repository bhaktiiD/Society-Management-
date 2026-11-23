import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../features/auth/auth_repository.dart';
import '../features/auth/login_screen.dart';
import '../features/auth/signup_screen.dart';
import '../features/auth/status_screens.dart';
import '../features/home/home_shell.dart';

/// Routing is driven by two facts: is there a session, and what does the
/// backend say about this person (pending / has roles)?
final routerProvider = Provider<GoRouter>((ref) {
  // go_router re-runs `redirect` whenever this notifier changes.
  final refresh = ValueNotifier<int>(0);
  ref.listen(sessionProvider.select((s) => s.value?.user.id), (_, _) => refresh.value++);
  ref.listen(meProvider, (_, _) => refresh.value++);
  ref.onDispose(refresh.dispose);

  const authPages = {'/login', '/signup', '/loading', '/error', '/pending'};

  final router = GoRouter(
    initialLocation: '/loading',
    refreshListenable: refresh,
    redirect: (context, state) {
      final location = state.matchedLocation;
      final signedIn = Supabase.instance.client.auth.currentSession != null;

      if (!signedIn) return (location == '/login' || location == '/signup') ? null : '/login';

      final me = ref.read(meProvider);
      if (me.isLoading && !me.hasValue) return location == '/loading' ? null : '/loading';
      if (me.hasError && !me.hasValue) return location == '/error' ? null : '/error';

      final profile = me.value;
      if (profile == null) return location == '/loading' ? null : '/loading';
      if (profile.isPending) return location == '/pending' ? null : '/pending';

      // Signed in with a role: keep people out of the auth pages.
      return authPages.contains(location) ? '/home' : null;
    },
    routes: [
      GoRoute(path: '/loading', builder: (_, _) => const LoadingScreen()),
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      GoRoute(path: '/signup', builder: (_, _) => const SignUpScreen()),
      GoRoute(path: '/error', builder: (_, _) => const ProfileErrorScreen()),
      GoRoute(path: '/pending', builder: (_, _) => const PendingScreen()),
      GoRoute(path: '/home', builder: (_, _) => const HomeShell()),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});
