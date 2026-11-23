import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'auth_repository.dart';

Future<void> _signOut(BuildContext context, WidgetRef ref) async {
  try {
    await ref.read(authRepositoryProvider).signOut();
  } catch (e) {
    if (context.mounted) showSnack(context, errorMessage(e), error: true);
  }
}

/// Shown while the profile loads after login.
class LoadingScreen extends StatelessWidget {
  const LoadingScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: AppLoader(label: 'Getting your society ready...'));
}

/// Profile could not be loaded (server down, no network, ...).
class ProfileErrorScreen extends ConsumerWidget {
  const ProfileErrorScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final error = ref.watch(meProvider).error;
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ErrorState(
                message: error == null ? 'Something went wrong.' : errorMessage(error),
                onRetry: () => ref.invalidate(meProvider),
              ),
            ),
            TextButton(
              onPressed: () => _signOut(context, ref),
              child: const Text('Sign out'),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

/// Signed in with Google/email but not invited to any society yet.
class PendingScreen extends ConsumerWidget {
  const PendingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(meProvider).value;
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Center(
                  child: IconBadge(
                    Icons.hourglass_top_rounded,
                    size: 112,
                    color: AppColors.warningDark,
                    background: AppColors.warningTint,
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Waiting for access',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 12),
                Text(
                  'Ask your society secretary to invite ${me?.email ?? 'your email'}. '
                  'Once they do, tap the button below.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.muted, fontSize: 16, height: 1.4),
                ),
                const SizedBox(height: 28),
                FilledButton(
                  onPressed: () => ref.invalidate(meProvider),
                  child: const Text('Check again'),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: () => _signOut(context, ref),
                  child: const Text('Sign out'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
