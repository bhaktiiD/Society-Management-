import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'booking_planner.dart';
import 'bookings_repository.dart';

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

String _short(String iso) {
  final d = DateTime.tryParse(iso);
  if (d == null) return iso;
  return '${d.day} ${_months[d.month - 1]} ${d.year}';
}

bool _isUpcoming(String iso) {
  final d = DateTime.tryParse(iso);
  if (d == null) return false;
  final now = DateTime.now();
  return !DateTime(d.year, d.month, d.day).isBefore(DateTime(now.year, now.month, now.day));
}

Future<bool> _confirmCancel(BuildContext context, String what) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Cancel booking?'),
      content: Text(what),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep it')),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: TextButton.styleFrom(foregroundColor: AppColors.error),
          child: const Text('Cancel booking'),
        ),
      ],
    ),
  );
  return ok == true;
}

class BookingsScreen extends ConsumerWidget {
  const BookingsScreen({super.key, required this.isAdmin});
  final bool isAdmin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(title: const Text('Community hall')),
      body: isAdmin ? const _AdminView() : const _ResidentView(),
    );
  }
}

// ---------------------------------------------------------------- admin
class _AdminView extends ConsumerWidget {
  const _AdminView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(adminBookingsProvider);
    return AsyncBody<List<HallBooking>>(
      value: value,
      onRetry: () => ref.invalidate(adminBookingsProvider),
      builder: (all) {
        final pending = all.where((b) => b.isPending).toList()..sort(_byDate);
        final upcoming = all.where((b) => b.confirmed && _isUpcoming(b.date)).toList()..sort(_byDate);
        final closed = all.where((b) => !b.isPending && !(b.confirmed && _isUpcoming(b.date))).toList()
          ..sort((a, b) => _byDate(b, a));
        Widget section(String title, List<HallBooking> list) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SectionHeader(title),
                for (final b in list)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _AdminCard(booking: b, onTap: () => _openRequestSheet(context, b)),
                  ),
              ],
            );
        return RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(adminBookingsProvider);
            await refreshProvider(() => ref.read(adminBookingsProvider.future));
          },
          child: all.isEmpty
              ? ListView(children: const [
                  SizedBox(height: 120),
                  EmptyState(icon: Icons.event_available_outlined, message: 'No bookings yet.'),
                ])
              : ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  children: [
                    if (pending.isNotEmpty) section('Needs your decision', pending),
                    if (upcoming.isNotEmpty) section('Upcoming', upcoming),
                    if (closed.isNotEmpty) section('Earlier / closed', closed),
                  ],
                ),
        );
      },
    );
  }
}

int _byDate(HallBooking a, HallBooking b) {
  final d = a.date.compareTo(b.date);
  return d != 0 ? d : (a.startTime ?? '').compareTo(b.startTime ?? '');
}

/// Opens the booking details / approval wizard sheet. The sheet reads
/// providers from the enclosing ProviderScope and invalidates them itself.
Future<void> showBookingSheet(BuildContext context, HallBooking booking, {required bool isAdmin}) =>
    _openRequestSheet(context, booking);

Future<void> _openRequestSheet(BuildContext context, HallBooking b) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Colors.white,
    builder: (_) => _RequestSheet(booking: b),
  );
}

(String, ChipTone) _adminChip(HallBooking b) => switch (b.status) {
      'pending' => ('New request', ChipTone.warning),
      'confirmed' => ('Confirmed', ChipTone.success),
      'reschedule' => ('Asked to pick new date', ChipTone.warning),
      'declined' => ('Declined', ChipTone.error),
      _ => ('Cancelled', ChipTone.neutral),
    };

class _DateBlock extends StatelessWidget {
  const _DateBlock(this.iso);
  final String iso;

  @override
  Widget build(BuildContext context) {
    final d = DateTime.tryParse(iso);
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(color: AppColors.greenTint, borderRadius: BorderRadius.circular(16)),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Text(d == null ? '-' : '${d.day}',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: AppColors.greenDark, height: 1.1)),
        Text(d == null ? '' : _months[d.month - 1].toUpperCase(),
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.greenDark)),
      ]),
    );
  }
}

class _AdminCard extends StatelessWidget {
  const _AdminCard({required this.booking, required this.onTap});
  final HallBooking booking;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final b = booking;
    final d = DateTime.tryParse(b.date);
    final dayMonth = d == null ? b.date : '${d.day} ${_months[d.month - 1]}';
    final (label, tone) = _adminChip(b);
    final purpose = (b.purpose ?? '').trim();
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _DateBlock(b.date),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(b.bookerName ?? 'Resident',
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text('Flat ${b.flatNumber ?? '-'} · ${b.displayTime} · $dayMonth',
                    style: const TextStyle(fontSize: 14, color: AppColors.muted)),
                Text(purpose.isEmpty ? 'Occasion not mentioned' : purpose,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14, color: AppColors.muted)),
                const SizedBox(height: 8),
                StatusChip(label, tone: tone),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

enum _Step { details, reschedule, decline }

class _RequestSheet extends ConsumerStatefulWidget {
  const _RequestSheet({required this.booking});
  final HallBooking booking;

  @override
  ConsumerState<_RequestSheet> createState() => _RequestSheetState();
}

class _RequestSheetState extends ConsumerState<_RequestSheet> {
  final _note = TextEditingController();
  final _reason = TextEditingController();
  _Step _step = _Step.details;
  bool _busy = false;
  bool _reasonError = false;

  HallBooking get b => widget.booking;

  @override
  void dispose() {
    _note.dispose();
    _reason.dispose();
    super.dispose();
  }

  void _refreshAll() {
    ref.invalidate(adminBookingsProvider);
    ref.invalidate(myBookingsProvider);
    ref.invalidate(availabilityProvider);
  }

  Future<void> _run(Future<void> Function() call, String success) async {
    setState(() => _busy = true);
    try {
      await call();
      if (!mounted) return;
      _refreshAll();
      showSnack(context, success);
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      showSnack(context, errorMessage(e), error: true);
      if (e is DioException && e.response?.statusCode == 409) {
        _refreshAll();
        Navigator.pop(context);
        return;
      }
      setState(() => _busy = false);
    }
  }

  Future<void> _approve() => _run(() => ref.read(bookingsRepositoryProvider).approve(b.id), 'Booking approved');

  Future<void> _sendReschedule() => _run(
      () => ref.read(bookingsRepositoryProvider).reschedule(b.id, note: _note.text),
      'Resident asked to pick a new date');

  Future<void> _sendDecline() {
    if (_reason.text.trim().length < 5) {
      setState(() => _reasonError = true);
      return Future.value();
    }
    return _run(() => ref.read(bookingsRepositoryProvider).decline(b.id, _reason.text), 'Request declined');
  }

  Future<void> _cancel() async {
    if (!await _confirmCancel(
        context, '${b.displayTime} on ${_short(b.date)} for flat ${b.flatNumber}. The booker is notified.')) {
      return;
    }
    if (!mounted) return;
    await _run(() => ref.read(bookingsRepositoryProvider).adminCancel(b.id), 'Booking cancelled');
  }

  Widget _row(IconData icon, String label, Widget value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          IconBadge(icon, size: 40),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: const TextStyle(fontSize: 13, color: AppColors.muted, fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              value,
            ]),
          ),
        ]),
      );

  static const _valueStyle = TextStyle(fontSize: 16, fontWeight: FontWeight.w700);

  Widget _details() {
    final purpose = (b.purpose ?? '').trim();
    final kind = b.bookerKind == null ? null : (b.bookerKind == 'tenant' ? 'Tenant' : 'Owner');
    final phone = (b.bookerPhone ?? '').trim();
    final noteLabel = b.status == 'declined' ? 'Reason' : 'Note';
    final note = (b.adminNote ?? '').trim();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _row(
        Icons.person_outline,
        'Requested by',
        Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text(b.bookerName ?? 'Resident', style: _valueStyle),
          if (kind != null) StatusChip(kind, tone: ChipTone.info),
        ]),
      ),
      _row(Icons.home_outlined, 'Flat number', Text(b.flatNumber ?? '-', style: _valueStyle)),
      _row(Icons.event_outlined, 'Date and time',
          Text('${_short(b.date)}\n${b.displayTime}', style: _valueStyle)),
      _row(Icons.celebration_outlined, 'Occasion',
          Text(purpose.isEmpty ? 'Not mentioned' : purpose, style: _valueStyle)),
      if (b.createdAt != null)
        _row(Icons.schedule_outlined, 'Requested on', Text(formatDateTime(b.createdAt!), style: _valueStyle)),
      if (phone.isNotEmpty) _row(Icons.call_outlined, 'Phone', SelectableText(phone, style: _valueStyle)),
      if (note.isNotEmpty && (b.status == 'declined' || b.needsReschedule || b.status == 'cancelled'))
        _row(Icons.sticky_note_2_outlined, noteLabel, Text(note, style: _valueStyle)),
      if (b.isPending && b.slotTaken) ...[
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: AppColors.warningTint, borderRadius: BorderRadius.circular(16)),
          child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.info_outline, color: AppColors.warningDark),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Another booking already overlaps this time. You can ask the resident to pick a new time.',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ),
          ]),
        ),
      ],
      const SizedBox(height: 16),
      if (b.isPending) ...[
        if (!b.slotTaken) ...[
          FilledButton(
            onPressed: _busy ? null : _approve,
            child: _busy ? const _Spinner() : const Text('Accept request'),
          ),
          const SizedBox(height: 10),
        ],
        OutlinedButton(
          onPressed: _busy ? null : () => setState(() => _step = _Step.reschedule),
          style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.orange, side: const BorderSide(color: AppColors.orange, width: 2)),
          child: const Text('Ask to pick another date'),
        ),
        const SizedBox(height: 6),
        TextButton(
          onPressed: _busy ? null : () => setState(() => _step = _Step.decline),
          style: TextButton.styleFrom(foregroundColor: AppColors.error, minimumSize: const Size.fromHeight(48)),
          child: const Text('Decline request'),
        ),
      ] else if (b.confirmed && _isUpcoming(b.date))
        OutlinedButton(
          onPressed: _busy ? null : _cancel,
          style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.error, side: const BorderSide(color: AppColors.error, width: 2)),
          child: _busy ? const _Spinner(color: AppColors.error) : const Text('Cancel booking'),
        ),
    ]);
  }

  Widget _rescheduleStep() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(
        'The resident will be told the hall is already booked on ${_short(b.date)}, ${b.displayTime}, '
        'and asked to choose a new date and time.',
        style: const TextStyle(fontSize: 16),
      ),
      const SizedBox(height: 16),
      TextField(
        controller: _note,
        maxLength: 300,
        minLines: 2,
        maxLines: 4,
        enabled: !_busy,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(labelText: 'Add a note (optional)'),
      ),
      const SizedBox(height: 8),
      FilledButton(
        onPressed: _busy ? null : _sendReschedule,
        child: _busy ? const _Spinner() : const Text('Send to resident'),
      ),
      const SizedBox(height: 6),
      TextButton(
        onPressed: _busy ? null : () => setState(() => _step = _Step.details),
        style: TextButton.styleFrom(minimumSize: const Size.fromHeight(48)),
        child: const Text('Back'),
      ),
    ]);
  }

  Widget _declineStep() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      TextField(
        controller: _reason,
        maxLength: 300,
        minLines: 3,
        maxLines: 5,
        enabled: !_busy,
        textCapitalization: TextCapitalization.sentences,
        onChanged: (_) {
          if (_reasonError && _reason.text.trim().length >= 5) setState(() => _reasonError = false);
        },
        decoration: InputDecoration(
          labelText: 'Reason',
          helperText: 'The resident will see this reason.',
          errorText: _reasonError ? 'Please give a short, genuine reason (at least 5 characters).' : null,
          errorMaxLines: 2,
        ),
      ),
      const SizedBox(height: 8),
      FilledButton(
        onPressed: _busy ? null : _sendDecline,
        style: FilledButton.styleFrom(backgroundColor: AppColors.error, foregroundColor: Colors.white),
        child: _busy ? const _Spinner(color: Colors.white) : const Text('Decline and send reason'),
      ),
      const SizedBox(height: 6),
      TextButton(
        onPressed: _busy ? null : () => setState(() => _step = _Step.details),
        style: TextButton.styleFrom(minimumSize: const Size.fromHeight(48)),
        child: const Text('Back'),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            switch (_step) {
              _Step.details => 'Booking request',
              _Step.reschedule => 'Ask to pick another date',
              _Step.decline => 'Decline request',
            },
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          switch (_step) {
            _Step.details => _details(),
            _Step.reschedule => _rescheduleStep(),
            _Step.decline => _declineStep(),
          },
        ]),
      ),
    );
  }
}

class _Spinner extends StatelessWidget {
  const _Spinner({this.color = AppColors.onGreen});
  final Color color;

  @override
  Widget build(BuildContext context) =>
      SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 3, color: color));
}

// ------------------------------------------------------------- resident
class _ResidentView extends ConsumerWidget {
  const _ResidentView();

  Future<void> _refresh(WidgetRef ref) async {
    ref.invalidate(hallProvider);
    ref.invalidate(availabilityProvider);
    ref.invalidate(myBookingsProvider);
    await ref.read(availabilityProvider.future).catchError((_) => <DayAvailability>[]);
  }

  Future<void> _repick(BuildContext context, WidgetRef ref, Amenity hall, HallBooking old) async {
    final r = await showModalBottomSheet<BookingDraft>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (_) => _PickNewDateSheet(purpose: old.purpose ?? ''),
    );
    if (r == null || !context.mounted) return;
    await _submit(context, ref, hall, r, replaces: old.id);
  }

  Future<void> _submit(BuildContext context, WidgetRef ref, Amenity hall, BookingDraft d, {int? replaces}) async {
    try {
      await ref.read(bookingsRepositoryProvider).book(
          amenityId: hall.id,
          date: d.date,
          startTime: d.start,
          endTime: d.end,
          purpose: d.purpose.trim(),
          replacesBookingId: replaces);
      if (context.mounted) showSnack(context, 'Request sent. The secretary will confirm soon.');
    } catch (e) {
      if (context.mounted) showSnack(context, errorMessage(e), error: true);
    }
    if (!context.mounted) return;
    ref.invalidate(availabilityProvider);
    ref.invalidate(myBookingsProvider);
  }

  Future<void> _cancel(BuildContext context, WidgetRef ref, HallBooking b) async {
    if (!await _confirmCancel(context, '${b.displayTime} on ${_short(b.date)} will be freed for others.')) {
      return;
    }
    try {
      await ref.read(bookingsRepositoryProvider).cancelMine(b.id);
    } catch (e) {
      if (context.mounted) showSnack(context, errorMessage(e), error: true);
    }
    if (!context.mounted) return;
    ref.invalidate(availabilityProvider);
    ref.invalidate(myBookingsProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hallV = ref.watch(hallProvider);
    return AsyncBody<Amenity>(
      value: hallV,
      onRetry: () => ref.invalidate(hallProvider),
      builder: (hall) {
        final avail = ref.watch(availabilityProvider);
        final mine = ref.watch(myBookingsProvider);
        return RefreshIndicator(
          onRefresh: () => _refresh(ref),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(children: [
                    const IconBadge(Icons.celebration_outlined, size: 52),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(hall.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 4),
                        const Text('Pick a date and your own time. The secretary will confirm.',
                            style: TextStyle(fontSize: 13, height: 1.4, color: AppColors.muted)),
                      ]),
                    ),
                  ]),
                ),
              ),
              const SectionHeader('Plan your booking'),
              avail.when(
                skipLoadingOnReload: true,
                loading: () => const Padding(
                    padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator())),
                error: (e, _) =>
                    ErrorState(message: errorMessage(e), onRetry: () => ref.invalidate(availabilityProvider)),
                data: (days) => BookingPlanner(
                  days: days,
                  onSubmit: (d) => _submit(context, ref, hall, d),
                ),
              ),
              const SectionHeader('My bookings'),
              mine.when(
                loading: () => const Padding(
                    padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
                error: (e, _) =>
                    ErrorState(message: errorMessage(e), onRetry: () => ref.invalidate(myBookingsProvider)),
                data: (list) => list.isEmpty
                    ? const EmptyState(icon: Icons.event_outlined, message: 'No bookings yet.')
                    : Column(children: [
                        for (final b in list)
                          _MyBookingCard(
                            booking: b,
                            onCancel: (b.isPending || (b.confirmed && _isUpcoming(b.date)))
                                ? () => _cancel(context, ref, b)
                                : null,
                            onRepick: b.needsReschedule ? () => _repick(context, ref, hall, b) : null,
                          ),
                      ]),
              ),
            ],
          ),
        );
      },
    );
  }
}

(String, ChipTone) _residentChip(HallBooking b) => switch (b.status) {
      'pending' => ('Waiting for approval', ChipTone.warning),
      'confirmed' => ('Confirmed', ChipTone.success),
      'reschedule' => ('Please pick a new date', ChipTone.warning),
      'declined' => ('Not approved', ChipTone.error),
      _ => ('Cancelled', ChipTone.neutral),
    };

class _MyBookingCard extends StatelessWidget {
  const _MyBookingCard({required this.booking, this.onCancel, this.onRepick});
  final HallBooking booking;
  final VoidCallback? onCancel;
  final VoidCallback? onRepick;

  @override
  Widget build(BuildContext context) {
    final b = booking;
    final (label, tone) = _residentChip(b);
    final purpose = (b.purpose ?? '').trim();
    final note = (b.adminNote ?? '').trim();
    final muted = b.status == 'cancelled';
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _DateBlock(b.date),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${_short(b.date)} · ${b.displayTime}',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w800, color: muted ? AppColors.muted : AppColors.ink)),
                  Text(purpose.isEmpty ? 'Occasion not mentioned' : purpose,
                      style: const TextStyle(fontSize: 14, color: AppColors.muted)),
                  const SizedBox(height: 8),
                  StatusChip(label, tone: tone),
                ]),
              ),
            ]),
            if (note.isNotEmpty && (b.status == 'declined' || b.needsReschedule)) ...[
              const SizedBox(height: 10),
              Text(b.status == 'declined' ? 'Reason: $note' : 'Note: $note', style: const TextStyle(fontSize: 14)),
            ],
            if (onRepick != null) ...[
              const SizedBox(height: 10),
              FilledButton(onPressed: onRepick, child: const Text('Pick new date and time')),
            ],
            if (onCancel != null)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: onCancel,
                  style: TextButton.styleFrom(foregroundColor: AppColors.error, minimumSize: const Size(48, 48)),
                  child: const Text('Cancel'),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}

class _PickNewDateSheet extends ConsumerWidget {
  const _PickNewDateSheet({required this.purpose});
  final String purpose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final avail = ref.watch(availabilityProvider);
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Pick a new date and time', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
          const SizedBox(height: 12),
          avail.when(
            skipLoadingOnReload: true,
            loading: () => const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
            error: (e, _) =>
                ErrorState(message: errorMessage(e), onRetry: () => ref.invalidate(availabilityProvider)),
            data: (days) => BookingPlanner(
              days: days,
              initialPurpose: purpose,
              onSubmit: (d) async => Navigator.pop(context, d),
            ),
          ),
        ]),
      ),
    );
  }
}
