import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/push_service.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../models/models.dart';
import '../auth/auth_repository.dart';
import '../bills/bills_screen.dart';
import '../emergency/emergency_watcher.dart';
import '../emergency/sos_sheet.dart';
import '../guests/guard_screen.dart';
import '../guests/resident_guests_screen.dart';
import 'resident_home_screen.dart';
import '../notices/notices_screen.dart';
import '../profile/profile_screen.dart';
import '../profile/user_avatar.dart';
import '../secretary/charges_screen.dart';
import '../secretary/dashboard_screen.dart';
import '../secretary/flats_screen.dart';
import '../services/services_screen.dart';

class _Tab {
  const _Tab(this.label, this.icon, this.selectedIcon, this.page);
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final Widget page;
}

/// Tabs for each role. The backend enforces the same rules independently;
/// this only decides what to *show*.
List<_Tab> _tabsFor(AppRole role, Me me) {
  switch (role) {
    case AppRole.secretary:
      return const [
        _Tab(
          'Home',
          Icons.home_outlined,
          Icons.home_rounded,
          DashboardScreen(),
        ),
        _Tab(
          'Charges',
          Icons.receipt_long_outlined,
          Icons.receipt_long,
          SecretaryChargesScreen(),
        ),
        _Tab('Flats', Icons.apartment_outlined, Icons.apartment, FlatsScreen()),
        _Tab(
          'Services',
          Icons.grid_view_outlined,
          Icons.grid_view_rounded,
          ServicesScreen(isAdmin: true),
        ),
        _Tab(
          'Notices',
          Icons.campaign_outlined,
          Icons.campaign,
          NoticesScreen(canManage: true),
        ),
      ];
    case AppRole.resident:
      return [
        const _Tab(
          'Home',
          Icons.home_outlined,
          Icons.home_rounded,
          ResidentHomeScreen(),
        ),
        const _Tab(
          'Bills',
          Icons.receipt_long_outlined,
          Icons.receipt_long,
          BillsScreen(),
        ),
        if (me.canApproveGuests)
          const _Tab(
            'Guests',
            Icons.people_outline,
            Icons.people,
            ResidentGuestsScreen(),
          ),
        const _Tab(
          'Services',
          Icons.grid_view_outlined,
          Icons.grid_view_rounded,
          ServicesScreen(isAdmin: false),
        ),
        const _Tab(
          'Notices',
          Icons.campaign_outlined,
          Icons.campaign,
          NoticesScreen(),
        ),
      ];
    case AppRole.guard:
      return const [
        _Tab(
          'Gate',
          Icons.door_front_door_outlined,
          Icons.door_front_door,
          GuardScreen(),
        ),
        _Tab(
          'Notices',
          Icons.campaign_outlined,
          Icons.campaign,
          NoticesScreen(),
        ),
      ];
  }
}

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _index = 0;
  AppRole? _lastRole;

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(meProvider).value;
    final role = ref.watch(activeRoleProvider);
    ref.watch(pushRegistrationProvider); // registers this phone for emergency push
    if (me == null || role == null) {
      return const Scaffold(body: AppLoader());
    }

    // Switching role starts on that role's first tab.
    if (_lastRole != role) {
      _lastRole = role;
      _index = 0;
    }

    final tabs = _tabsFor(role, me);
    final safeIndex = _index.clamp(0, tabs.length - 1);
    final current = tabs[safeIndex];
    final noticesIndex = tabs.indexWhere((t) => t.label == 'Notices');
    // The display name the person chose (Profile > Edit profile). A name that
    // defaulted from an email ("dhavul123") reads better without trailing digits.
    final cleaned = me.fullName.trim().replaceAll(RegExp(r'\d+$'), '');
    final firstName = cleaned.isEmpty
        ? 'there'
        : cleaned[0].toUpperCase() + cleaned.substring(1);

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        bottom: false,
        child: EmergencyWatcher(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: PageHeader(
                  eyebrow: safeIndex == 0 ? 'Hello,' : null,
                  title: safeIndex == 0 ? firstName : current.label,
                  actions: [
                    RoundIconButton(
                      icon: Icons.notifications_none_rounded,
                      tooltip: 'Notices',
                      onPressed: () {
                        if (noticesIndex >= 0) {
                          setState(() => _index = noticesIndex);
                        }
                      },
                    ),
                    _AvatarButton(me: me),
                  ],
                ),
              ),
              // IndexedStack keeps each tab's state (scroll position, polling) alive.
              Expanded(
                child: Stack(
                  children: [
                    IndexedStack(
                      index: safeIndex,
                      children: [for (final t in tabs) t.page],
                    ),
                    // Only on the first (Home / Gate) tab, not on every screen.
                    if (safeIndex == 0)
                      const Positioned(right: 16, bottom: 16, child: SosButton()),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          boxShadow: [
            BoxShadow(
              color: Color(0x1A000000),
              blurRadius: 16,
              offset: Offset(0, -4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          child: NavigationBar(
            backgroundColor: Colors.white,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            selectedIndex: safeIndex,
            onDestinationSelected: (i) => setState(() => _index = i),
            destinations: [
              for (final t in tabs)
                NavigationDestination(
                  icon: Icon(t.icon),
                  selectedIcon: Icon(
                    t.selectedIcon,
                    color: AppColors.greenDark,
                  ),
                  label: t.label,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Round avatar in the header; opens Profile & settings.
class _AvatarButton extends StatelessWidget {
  const _AvatarButton({required this.me});
  final Me me;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Profile and settings',
      child: Material(
        color: AppColors.greenTint,
        elevation: 3,
        shadowColor: const Color(0x1A000000),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () => Navigator.of(context).push<void>(
            MaterialPageRoute(builder: (_) => const ProfileScreen()),
          ),
          child: SizedBox(
            width: 48,
            height: 48,
            child: Center(
              child: UserAvatar(
                name: me.fullName,
                avatarVersion: me.avatarVersion,
                radius: 24,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
