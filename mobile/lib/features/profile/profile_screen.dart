import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../models/models.dart';
import '../auth/auth_repository.dart';
import '../bookings/bookings_screen.dart';
import '../complaints/complaints_screen.dart';
import '../contacts/contacts_screen.dart';
import '../notices/notices_repository.dart';
import '../notices/notices_screen.dart';
import '../secretary/charges_screen.dart';
import '../secretary/flats_screen.dart';
import '../secretary/maintenance_screen.dart';
import '../secretary/secretary_repository.dart';
import 'avatar_repository.dart';
import 'profile_groups.dart';
import 'profile_repository.dart';
import 'user_avatar.dart';

const appVersion = '1.0.0';

/// Profile & settings. Everyone: edit name, change password, switch role,
/// sign out. Admin also: society name and monthly maintenance.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  Future<void> _editProfile(BuildContext context, WidgetRef ref, Me me) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (_) => _EditProfileSheet(me: me),
    );
    if (saved == true && context.mounted) showSnack(context, 'Profile updated');
  }

  Future<void> _editSociety(BuildContext context, WidgetRef ref, String current) async {
    final controller = TextEditingController(text: current);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Society name'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          maxLength: 150,
          decoration: const InputDecoration(labelText: 'Name'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    // Not disposed: the dialog is still animating closed and nothing listens to it.
    if (name == null || name.isEmpty || name == current || !context.mounted) return;
    try {
      await ref.read(profileRepositoryProvider).setSocietyName(name);
      ref.invalidate(societyNameProvider);
      if (context.mounted) showSnack(context, 'Society name updated');
    } catch (error) {
      if (context.mounted) showSnack(context, errorMessage(error), error: true);
    }
  }

  Future<void> _changePassword(BuildContext context, WidgetRef ref) async {
    final done = await showDialog<bool>(
      context: context,
      builder: (_) => const _ChangePasswordDialog(),
    );
    if (done == true && context.mounted) showSnack(context, 'Password changed');
  }

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text('You will need to sign in again to use SocietyOS.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    if (context.mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    try {
      await ref.read(authRepositoryProvider).signOut(); // router sends us to login
    } catch (e) {
      if (context.mounted) showSnack(context, errorMessage(e), error: true);
    }
  }

  Widget _tile(IconData icon, String title, String subtitle, VoidCallback onTap) =>
      ActionTile(icon: icon, title: title, subtitle: subtitle, onTap: onTap);

  Widget _page(String title, Widget body) =>
      Scaffold(appBar: AppBar(title: Text(title)), body: body);

  Future<T?> _open<T>(BuildContext context, Widget page) =>
      Navigator.of(context).push<T>(MaterialPageRoute(builder: (_) => page));

  Future<void> _newCharge(BuildContext context, WidgetRef ref) async {
    final result = await _open<Map<String, dynamic>>(context, const ChargeFormScreen());
    if (result == null || !context.mounted) return;
    ref.invalidate(secretaryChargesProvider);
    ref.invalidate(collectionsProvider);
    showSnack(context, 'Added to ${result['created']} flats');
  }

  Future<void> _register(BuildContext context) async {
    final saved = await _open<bool>(context, const InviteFormScreen());
    if (saved == true && context.mounted) {
      showSnack(context, 'Registered. They can now create their account with that email.');
    }
  }

  Future<void> _postNotice(BuildContext context, WidgetRef ref) async {
    final saved = await _open<bool>(context, const NoticeFormScreen());
    if (saved != true || !context.mounted) return;
    ref.invalidate(noticesProvider);
    showSnack(context, 'Notice posted');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(meProvider).value;
    if (me == null) return const Scaffold(body: AppLoader());
    final roles = availableRoles(me);
    final active = ref.watch(activeRoleProvider);
    final repo = ref.read(profileRepositoryProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _IdentityHeader(me: me),
          const SectionHeader('Account'),
          TileCard(
            leading: const IconBadge(Icons.person_outline),
            title: 'Edit profile',
            subtitle: 'Name and phone number',
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _editProfile(context, ref, me),
          ),
          if (repo.canChangePassword) ...[
            const SizedBox(height: 10),
            TileCard(
              leading: const IconBadge(Icons.lock_outline),
              title: 'Change password',
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _changePassword(context, ref),
            ),
          ],
          if (roles.length > 1) ...[
            const SectionHeader('Switch role'),
            for (final r in roles) ...[
              TileCard(
                leading: IconBadge(
                  switch (r) {
                    AppRole.secretary => Icons.admin_panel_settings_outlined,
                    AppRole.resident => Icons.home_outlined,
                    AppRole.guard => Icons.security_outlined,
                  },
                ),
                title: 'Act as ${r.label}',
                trailing: r == active
                    ? const Icon(Icons.check_circle, color: AppColors.greenDark)
                    : const Icon(Icons.radio_button_unchecked, color: AppColors.muted),
                onTap: () {
                  ref.read(selectedRoleProvider.notifier).select(r);
                  Navigator.of(context).pop(); // back to the home screen of that role
                },
              ),
              const SizedBox(height: 10),
            ],
          ],
          if (me.isSecretary) ...[
            const SectionHeader('Society'),
            _SocietyNameTile(onEdit: (name) => _editSociety(context, ref, name)),
            const SectionHeader('Billing'),
            _tile(Icons.calendar_month_outlined, 'Monthly maintenance', 'Rates, late fees and due day',
                () => _open(context, const MaintenanceScreen())),
            const SizedBox(height: 10),
            _tile(Icons.receipt_long_outlined, 'New society-wide charge',
                'Festival or repair, billed to every flat', () => _newCharge(context, ref)),
            const SectionHeader('People'),
            _tile(Icons.apartment_outlined, 'Flats & residents', 'Flats, owners and tenants',
                () => _open(context, _page('Flats & residents', const FlatsScreen()))),
            const SizedBox(height: 10),
            _tile(Icons.person_add_alt_outlined, 'Register a person', 'Owner, tenant, guard or admin',
                () => _register(context)),
            const SectionHeader('Communication'),
            _tile(Icons.campaign_outlined, 'Post a notice', 'Tell everyone in the society',
                () => _postNotice(context, ref)),
            const SizedBox(height: 10),
            _tile(Icons.article_outlined, 'Manage notices', 'View and delete notices',
                () => _open(context, _page('Notices', const NoticesScreen(canManage: true)))),
            const SectionHeader('Services'),
            _tile(Icons.report_problem_outlined, 'Complaints', 'Review and resolve complaints',
                () => _open(context, const ComplaintsScreen(isAdmin: true))),
            const SizedBox(height: 10),
            _tile(Icons.event_available_outlined, 'Community hall', 'See and cancel bookings',
                () => _open(context, const BookingsScreen(isAdmin: true))),
            const SizedBox(height: 10),
            _tile(Icons.phone_in_talk_outlined, 'Emergency contacts', 'Police, security, plumber...',
                () => _open(context, const ContactsScreen(isAdmin: true))),
          ],
          if (active == AppRole.resident) ResidentGroups(canApproveGuests: me.canApproveGuests),
          const SectionHeader('About'),
          const TileCard(
            leading: IconBadge(Icons.info_outline),
            title: 'SocietyOS',
            subtitle: 'Version $appVersion',
          ),
          const SizedBox(height: 28),
          OutlinedButton.icon(
            onPressed: () => _signOut(context, ref),
            icon: const Icon(Icons.logout),
            label: const Text('Sign out'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.error,
              side: const BorderSide(color: AppColors.error, width: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _SocietyNameTile extends ConsumerWidget {
  const _SocietyNameTile({required this.onEdit});
  final void Function(String current) onEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = ref.watch(societyNameProvider);
    return TileCard(
      leading: const IconBadge(Icons.domain_outlined),
      title: 'Society name',
      subtitle: name.when(
        data: (n) => n,
        loading: () => 'Loading...',
        error: (_, _) => 'Could not load',
      ),
      trailing: const Icon(Icons.edit_outlined),
      onTap: name.hasValue ? () => onEdit(name.value!) : null,
    );
  }
}

enum _PhotoAction { camera, gallery, remove }

class _IdentityHeader extends ConsumerStatefulWidget {
  const _IdentityHeader({required this.me});
  final Me me;

  @override
  ConsumerState<_IdentityHeader> createState() => _IdentityHeaderState();
}

class _IdentityHeaderState extends ConsumerState<_IdentityHeader> {
  static const _maxBytes = 380 * 1024;
  final _picker = ImagePicker();
  bool _busy = false;

  Future<void> _choose() async {
    if (_busy) return;
    final action = await showModalBottomSheet<_PhotoAction>(
      context: context,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (_) => _PhotoSheet(hasPhoto: widget.me.avatarVersion != null),
    );
    if (action == null || !mounted) return;
    setState(() => _busy = true);
    try {
      if (action == _PhotoAction.remove) {
        await ref.read(avatarRepositoryProvider).remove();
        if (!mounted) return;
        ref.invalidate(meProvider);
        showSnack(context, 'Profile photo removed');
      } else {
        await _pickAndUpload(action);
      }
    } on PlatformException {
      if (mounted) {
        showSnack(
          context,
          action == _PhotoAction.camera
              ? "We could not open the camera. Check the app's camera permission."
              : 'We could not open your photos. Please try again.',
          error: true,
        );
      }
    } catch (e) {
      if (mounted) showSnack(context, errorMessage(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickAndUpload(_PhotoAction action) async {
    final source = action == _PhotoAction.camera ? ImageSource.camera : ImageSource.gallery;
    XFile? file;
    Uint8List? bytes;
    for (final quality in const [85, 60]) {
      file = await _picker.pickImage(
        source: source,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: quality,
        preferredCameraDevice: CameraDevice.front,
      );
      if (file == null) return; // cancelled: not an error
      bytes = await file.readAsBytes();
      if (bytes.length <= _maxBytes) break;
    }
    if (!mounted || file == null || bytes == null) return;
    final name = file.name.toLowerCase();
    final type = name.endsWith('.png')
        ? 'image/png'
        : name.endsWith('.webp')
            ? 'image/webp'
            : 'image/jpeg';
    await ref.read(avatarRepositoryProvider).upload(bytes, type);
    if (!mounted) return;
    ref.invalidate(meProvider);
    showSnack(context, 'Profile photo updated');
  }

  @override
  Widget build(BuildContext context) {
    final me = widget.me;
    final roles = [
      if (me.isSecretary) 'Admin',
      if (me.isOwner) 'Owner',
      if (me.isTenant) 'Tenant',
      if (me.isGuard) 'Guard',
    ];
    const shadow = [BoxShadow(color: Color(0x33000000), blurRadius: 12, offset: Offset(0, 4))];
    return Column(
      children: [
        const SizedBox(height: 8),
        SizedBox(
          width: 120,
          height: 120,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: Tooltip(
                  message: 'Change profile photo',
                  child: GestureDetector(
                    onTap: _busy ? null : _choose,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white,
                        boxShadow: shadow,
                      ),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          UserAvatar(name: me.fullName, avatarVersion: me.avatarVersion, radius: 56),
                          if (_busy)
                            Container(
                              width: 112,
                              height: 112,
                              decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0x88FFFFFF)),
                              child: const Center(
                                child: SizedBox(
                                  width: 28,
                                  height: 28,
                                  child: CircularProgressIndicator(strokeWidth: 3),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                right: -4,
                bottom: -4,
                child: Tooltip(
                  message: 'Change profile photo',
                  child: SizedBox(
                    width: 48,
                    height: 48,
                    child: Center(
                      child: Material(
                        color: AppColors.green,
                        shape: const CircleBorder(side: BorderSide(color: Colors.white, width: 3)),
                        elevation: 3,
                        shadowColor: const Color(0x55000000),
                        child: InkResponse(
                          onTap: _busy ? null : _choose,
                          customBorder: const CircleBorder(),
                          child: const SizedBox(
                            width: 40,
                            height: 40,
                            child: Icon(Icons.add_a_photo_rounded, size: 20, color: AppColors.onGreen),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Text(
          me.fullName,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 2),
        Text(me.email, style: const TextStyle(color: AppColors.muted, fontSize: 15)),
        if (me.phone != null && me.phone!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(me.phone!, style: const TextStyle(color: AppColors.muted, fontSize: 15)),
          ),
        if (residentSummary(me) case final summary?)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              summary,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.muted, fontSize: 15, fontWeight: FontWeight.w600),
            ),
          ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          alignment: WrapAlignment.center,
          children: [for (final r in roles) StatusChip(r, tone: ChipTone.success)],
        ),
      ],
    );
  }
}

class _PhotoSheet extends StatelessWidget {
  const _PhotoSheet({required this.hasPhoto});
  final bool hasPhoto;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: const Text('Take a photo'),
            onTap: () => Navigator.pop(context, _PhotoAction.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Choose from gallery'),
            onTap: () => Navigator.pop(context, _PhotoAction.gallery),
          ),
          if (hasPhoto)
            ListTile(
              leading: const Icon(Icons.delete_outline, color: AppColors.error),
              title: const Text('Remove photo', style: TextStyle(color: AppColors.error)),
              onTap: () => Navigator.pop(context, _PhotoAction.remove),
            ),
        ],
      ),
    );
  }
}

class _EditProfileSheet extends ConsumerStatefulWidget {
  const _EditProfileSheet({required this.me});
  final Me me;

  @override
  ConsumerState<_EditProfileSheet> createState() => _EditProfileSheetState();
}

class _EditProfileSheetState extends ConsumerState<_EditProfileSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name = TextEditingController(text: widget.me.fullName);
  late final TextEditingController _phone = TextEditingController(text: widget.me.phone ?? '');
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await ref.read(profileRepositoryProvider).updateProfile(
            fullName: _name.text.trim(),
            phone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
          );
      ref.invalidate(meProvider); // greeting + profile pick up the new name
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
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 4, 20, 20 + bottom),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Edit profile', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
            const SizedBox(height: 4),
            const Text(
              'Your name is shown on your dashboard.',
              style: TextStyle(color: AppColors.muted),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _name,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              maxLength: 100,
              decoration: const InputDecoration(labelText: 'Display name'),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter your name' : null,
            ),
            const SizedBox(height: 4),
            TextFormField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.done,
              maxLength: 20,
              onFieldSubmitted: (_) => _save(),
              decoration: const InputDecoration(labelText: 'Phone (optional)'),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _busy ? null : _save,
              child: _busy
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(strokeWidth: 3),
                    )
                  : const Text('Save'),
            ),
          ],
        )),
      ),
    );
  }
}

class _ChangePasswordDialog extends ConsumerStatefulWidget {
  const _ChangePasswordDialog();

  @override
  ConsumerState<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends ConsumerState<_ChangePasswordDialog> {
  final _formKey = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  bool _show = false;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await ref.read(profileRepositoryProvider).changePassword(_password.text);
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
    return AlertDialog(
      title: const Text('Change password'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _password,
              obscureText: !_show,
              autofillHints: const [AutofillHints.newPassword],
              decoration: InputDecoration(
                labelText: 'New password',
                suffixIcon: IconButton(
                  tooltip: _show ? 'Hide password' : 'Show password',
                  icon: Icon(_show ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setState(() => _show = !_show),
                ),
              ),
              validator: (v) => (v == null || v.length < 8) ? 'Use at least 8 characters' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _confirm,
              obscureText: !_show,
              autofillHints: const [AutofillHints.newPassword],
              decoration: const InputDecoration(labelText: 'Confirm password'),
              validator: (v) => v != _password.text ? 'Passwords do not match' : null,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        TextButton(onPressed: _busy ? null : _save, child: const Text('Save')),
      ],
    );
  }
}
