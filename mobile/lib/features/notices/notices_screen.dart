import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../models/models.dart';
import 'notices_repository.dart';

/// Notice board. Everyone reads; only the secretary ([canManage]) can post
/// or delete (the server enforces this regardless of what the UI shows).
class NoticesScreen extends ConsumerWidget {
  const NoticesScreen({super.key, this.canManage = false});
  final bool canManage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notices = ref.watch(noticesProvider);
    return Scaffold(
      floatingActionButton: canManage
          ? FloatingActionButton.extended(
              onPressed: () async {
                final posted = await Navigator.of(context).push<bool>(
                  MaterialPageRoute(builder: (_) => const NoticeFormScreen()),
                );
                if (posted == true) ref.invalidate(noticesProvider);
              },
              icon: const Icon(Icons.add),
              label: const Text('New notice'),
            )
          : null,
      body: AsyncBody<List<Notice>>(
        value: notices,
        onRetry: () => ref.invalidate(noticesProvider),
        builder: (list) {
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(noticesProvider);
              await refreshProvider(() => ref.read(noticesProvider.future));
            },
            child: list.isEmpty
                ? LayoutBuilder(
                      builder: (_, box) => ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: [
                          SizedBox(
                            height: box.maxHeight,
                            child: const EmptyState(
                              icon: Icons.campaign_outlined,
                              message: 'No notices yet.',
                            ),
                          ),
                        ],
                      ),
                    )
                : ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              itemCount: list.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (_, i) {
                final n = list[i];
                return TileCard(
                  leading: _badge(n),
                  title: n.title,
                  subtitle: formatDate(n.createdAt),
                  trailing: n.pinned
                      ? const StatusChip('Important', tone: ChipTone.warning)
                      : const Icon(Icons.chevron_right, color: AppColors.muted),
                  onTap: () => showDialog<void>(
                    context: context,
                    builder: (_) => _NoticeDialog(notice: n, canManage: canManage),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

Widget _badge(Notice n) => n.pinned
    ? const IconBadge(
        Icons.push_pin,
        color: AppColors.warningDark,
        background: AppColors.warningTint,
      )
    : const IconBadge(Icons.campaign_outlined);

/// Opens one notice's popup (title, text, and delete for the admin).
Future<void> showNoticeDialog(BuildContext context, Notice notice, {required bool canManage}) =>
    showDialog<void>(
      context: context,
      builder: (_) => _NoticeDialog(notice: notice, canManage: canManage),
    );

class _NoticeDialog extends ConsumerWidget {
  const _NoticeDialog({required this.notice, required this.canManage});
  final Notice notice;
  final bool canManage;

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete notice?'),
        content: Text('"${notice.title}" will be removed for everyone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(noticesRepositoryProvider).delete(notice.id);
      ref.invalidate(noticesProvider);
      if (!context.mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop();
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Notice deleted')));
    } catch (error) {
      if (context.mounted) showSnack(context, errorMessage(error), error: true);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final maxBody = MediaQuery.sizeOf(context).height * 0.5;
    return Dialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 22, 14, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _badge(notice),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        notice.title,
                        style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, height: 1.3),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(top: 14, bottom: 18, right: 10),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      formatDate(notice.createdAt),
                      style: const TextStyle(color: AppColors.muted, fontSize: 14),
                    ),
                    if (notice.pinned) const StatusChip('Important', tone: ChipTone.warning),
                  ],
                ),
              ),
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: maxBody),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.only(right: 10),
                  child: Text(notice.body, style: const TextStyle(fontSize: 15, height: 1.6)),
                ),
              ),
              // The X in the header is the only close control; only admins get a delete icon here.
              if (canManage)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: IconButton(
                      tooltip: 'Delete notice',
                      constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                      icon: const Icon(Icons.delete_outline, color: AppColors.error),
                      onPressed: () => _delete(context, ref),
                    ),
                  ),
                )
              else
                const SizedBox(height: 4),
            ],
          ),
        ),
      ),
    );
  }
}

class NoticeFormScreen extends ConsumerStatefulWidget {
  const NoticeFormScreen({super.key});

  @override
  ConsumerState<NoticeFormScreen> createState() => _NoticeFormScreenState();
}

class _NoticeFormScreenState extends ConsumerState<NoticeFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _body = TextEditingController();
  bool _pinned = false;
  bool _busy = false;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await ref.read(noticesRepositoryProvider).post(
            title: _title.text.trim(),
            body: _body.text.trim(),
            pinned: _pinned,
          );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        showSnack(context, errorMessage(error), error: true);
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New notice')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _title,
                  textInputAction: TextInputAction.next,
                  maxLength: 150,
                  decoration: const InputDecoration(labelText: 'Title'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter a title' : null,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _body,
                  minLines: 5,
                  maxLines: 10,
                  maxLength: 4000,
                  decoration: const InputDecoration(
                    labelText: 'Message',
                    alignLabelWithHint: true,
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter a message' : null,
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  activeThumbColor: AppColors.greenDark,
                  title: const Text('Pin to top'),
                  value: _pinned,
                  onChanged: (v) => setState(() => _pinned = v),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _busy ? null : _submit,
                  child: _busy
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(strokeWidth: 3),
                        )
                      : const Text('Post notice'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
