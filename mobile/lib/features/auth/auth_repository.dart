import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/api_client.dart';
import '../../models/models.dart';

/// Deep link Supabase redirects to after Google sign-in (also registered in
/// AndroidManifest.xml and the Supabase "Redirect URLs" allow-list).
const oauthRedirect = 'io.supabase.societyos://login-callback/';

class AuthRepository {
  AuthRepository(this._auth);
  final GoTrueClient _auth;

  Future<void> signInWithGoogle() async {
    await _auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: kIsWeb ? null : oauthRedirect,
      authScreenLaunchMode: LaunchMode.externalApplication,
    );
  }

  /// Creates the account. Supabase emails a confirmation link; the person
  /// cannot sign in (and the backend grants nothing) until it is clicked.
  Future<void> signUp(String email, String password, {required String fullName}) async {
    await _auth.signUp(
      email: email.trim(),
      password: password,
      emailRedirectTo: kIsWeb ? null : oauthRedirect,
      // The backend reads this to name the profile: it appears on bills and invoices.
      data: {'full_name': fullName.trim()},
    );
  }

  Future<void> signInWithPassword(String email, String password) async {
    await _auth.signInWithPassword(email: email.trim(), password: password);
  }

  Future<void> signOut() => _auth.signOut(scope: SignOutScope.local);
}

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(Supabase.instance.client.auth),
);

/// Public check: did the admin pre-register this email?
Future<bool> isEmailInvited(Dio dio, String email) async {
  final r = await dio.post('/auth/check-invite', data: {'email': email.trim()});
  return (r.data as Map<String, dynamic>)['invited'] as bool;
}

/// Emits the current session, then every change.
final sessionProvider = StreamProvider<Session?>((ref) async* {
  final auth = Supabase.instance.client.auth;
  yield auth.currentSession;
  yield* auth.onAuthStateChange.map((event) => event.session);
});

/// The signed-in person's profile + roles from our backend.
/// Re-fetched only when the *user* changes, not on every token refresh.
final meProvider = FutureProvider<Me?>((ref) async {
  final userId = ref.watch(sessionProvider.select((s) => s.value?.user.id));
  if (userId == null) return null;
  final response = await ref.read(dioProvider).get('/me');
  return Me.fromJson(response.data as Map<String, dynamic>);
});

/// Roles a person can act as in the app. A person may hold several.
enum AppRole {
  resident('Resident'),
  secretary('Admin'),
  guard('Guard');

  const AppRole(this.label);
  final String label;
}

List<AppRole> availableRoles(Me me) => [
      if (me.isSecretary) AppRole.secretary,
      if (me.isResident) AppRole.resident,
      if (me.isGuard) AppRole.guard,
    ];

/// The role the user picked in the switcher (null = use the first available).
class SelectedRole extends Notifier<AppRole?> {
  @override
  AppRole? build() => null;
  void select(AppRole role) => state = role;
}

final selectedRoleProvider =
    NotifierProvider<SelectedRole, AppRole?>(SelectedRole.new);

/// The role actually shown: the picked one if still valid, else the first.
final activeRoleProvider = Provider<AppRole?>((ref) {
  final me = ref.watch(meProvider).value;
  if (me == null) return null;
  final roles = availableRoles(me);
  if (roles.isEmpty) return null;
  final picked = ref.watch(selectedRoleProvider);
  return roles.contains(picked) ? picked : roles.first;
});
