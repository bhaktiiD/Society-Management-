import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';
import 'design.dart';
import 'theme.dart';

// Design-system widgets (PageHeader, HeroCard, TileCard, ...) live in design.dart.
export 'design.dart';

/// Renders an [AsyncValue] with consistent loading / error / data states.
class AsyncBody<T> extends StatelessWidget {
  const AsyncBody({
    super.key,
    required this.value,
    required this.onRetry,
    required this.builder,
  });

  final AsyncValue<T> value;
  final VoidCallback onRetry;
  final Widget Function(T data) builder;

  @override
  Widget build(BuildContext context) {
    // Keep showing previous data if a refresh fails; error state only without data.
    return value.when(
      skipLoadingOnReload: true,
      skipError: true,
      loading: () => const AppLoader(),
      error: (error, _) => ErrorState(message: errorMessage(error), onRetry: onRetry),
      data: builder,
    );
  }
}

/// Awaits a provider load for pull-to-refresh, ignoring errors (the
/// AsyncValue already shows them).
Future<void> refreshProvider(Future<Object?> Function() load) async {
  try {
    await load();
  } catch (_) {}
}

class ErrorState extends StatelessWidget {
  const ErrorState({super.key, required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined, size: 48, color: AppColors.muted),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            SizedBox(
              width: 160,
              child: OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
            ),
          ],
        ),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.message});
  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: AppColors.border),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.muted, fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }
}

enum ChipTone { success, warning, error, info, neutral }

/// Small coloured pill used for statuses (Paid, Overdue, Pending, ...).
class StatusChip extends StatelessWidget {
  const StatusChip(this.label, {super.key, this.tone = ChipTone.neutral});
  final String label;
  final ChipTone tone;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (tone) {
      ChipTone.success => (AppColors.greenTint, AppColors.greenDark),
      ChipTone.warning => (AppColors.warningTint, const Color(0xFF7A5C00)),
      ChipTone.error => (AppColors.errorTint, AppColors.error),
      ChipTone.info => (AppColors.infoTint, const Color(0xFF0B6A99)),
      ChipTone.neutral => (AppColors.surface, AppColors.muted),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(
        label,
        style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w700),
      ),
    );
  }
}

void showSnack(BuildContext context, String message, {bool error = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? AppColors.error : AppColors.ink,
      ),
    );
}

/// Section heading used inside screens.
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(0, 24, 0, 10), // flush with card edges
        child: Text(
          text,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.muted),
        ),
      );
}
