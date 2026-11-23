import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'meeting_widgets.dart';
import 'meetings_repository.dart';
import 'meetings_screen.dart';

class UpcomingMeetingSection extends ConsumerWidget {
  const UpcomingMeetingSection({super.key, required this.isAdmin});
  final bool isAdmin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final meetings = ref.watch(isAdmin ? adminMeetingsProvider : meetingsProvider).asData?.value;
    if (meetings == null) return const SizedBox.shrink();
    final now = DateTime.now();
    final upcoming = meetings.where((m) => m.isUpcoming).toList()
      ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
    if (upcoming.isEmpty) return const SizedBox.shrink();
    final next = upcoming.first;
    if (next.scheduledAt.difference(now).inDays >= 14) return const SizedBox.shrink();

    void open() => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => MeetingsScreen(isAdmin: isAdmin)),
        );
    final location = next.location?.trim() ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader('Next meeting', actionLabel: 'See all', onAction: open),
        Card(
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => showMeetingSheet(context, next, isAdmin: isAdmin),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  DateBlock(next.scheduledAt),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(next.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 2),
                        Text(friendlyWhen(next.scheduledAt, now),
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.muted)),
                        if (location.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              const Icon(Icons.place_outlined, size: 16, color: AppColors.muted),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(location,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 14, color: AppColors.muted)),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
