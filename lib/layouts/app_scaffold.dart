import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../features/auth/auth_provider.dart';

class MenuItem {
  const MenuItem(this.title, this.icon, this.path);

  final String title;
  final IconData icon;
  final String path;
}

class MenuSection {
  const MenuSection(this.header, this.items);

  final String header;
  final List<MenuItem> items;
}

/// Mirrors the web sidebar, limited to modules the ntp-api backend serves.
const menu = [
  MenuSection('', [
    MenuItem('หน้าหลัก', Icons.home_outlined, '/'),
    MenuItem('รับรถเข้า', Icons.garage_rounded, '/intake'),
  ]),
  MenuSection('SYSTEM', [MenuItem('ซ่อมรถยนต์', Icons.car_repair, '/repairs')]),
  MenuSection('INVOICES', [
    MenuItem('ใบเสนอราคา', Icons.request_quote_outlined, '/quotations'),
    MenuItem('ใบแจ้งหนี้', Icons.receipt_long_outlined, '/invoices'),
  ]),
  MenuSection('CUSTOMERS AND VENDORS', [
    MenuItem('ข้อมูลลูกค้า', Icons.people_outline, '/customers'),
    MenuItem('ข้อมูลคู่ค้า', Icons.storefront_outlined, '/vendors'),
    MenuItem('ข้อมูลรถยนต์', Icons.directions_car_outlined, '/cars'),
  ]),
  MenuSection('STOCKS', [
    MenuItem('สินค้าคงคลัง', Icons.inventory_2_outlined, '/parts'),
    MenuItem('พรีเซ็ตข้อมูล', Icons.playlist_add_check, '/presets'),
  ]),
  MenuSection('EMPLOYEES', [
    MenuItem('ข้อมูลพนักงาน', Icons.badge_outlined, '/employees'),
  ]),
  MenuSection('', [
    MenuItem('บัญชีผู้ใช้', Icons.manage_accounts_outlined, '/account'),
  ]),
];

/// Scaffold for top-level (menu) pages: app bar + navigation drawer.
/// Detail pages use a plain [Scaffold] so they get a back button.
class AppScaffold extends StatelessWidget {
  const AppScaffold({
    super.key,
    required this.title,
    required this.body,
    this.actions,
    this.floatingActionButton,
    this.bottom,
  });

  final String title;
  final Widget body;
  final List<Widget>? actions;
  final Widget? floatingActionButton;
  final PreferredSizeWidget? bottom;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title), actions: actions, bottom: bottom),
      drawer: const AppDrawer(),
      body: body,
      floatingActionButton: floatingActionButton,
    );
  }
}

class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final employee = context.watch<AuthProvider>().employee;
    final location = GoRouterState.of(context).uri.path;
    final theme = Theme.of(context);

    return NavigationDrawer(
      selectedIndex: null,
      children: [
        UserAccountsDrawerHeader(
          decoration: BoxDecoration(color: theme.colorScheme.primary),
          currentAccountPicture: CircleAvatar(
            backgroundColor: theme.colorScheme.onPrimary,
            child: Text(employee?.initials ?? '?'),
          ),
          accountName: Text(employee?.fullName ?? ''),
          accountEmail: Text(employee?.positionTitle ?? ''),
        ),
        for (final section in menu) ...[
          if (section.header.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 12, 16, 4),
              child: Text(
                section.header,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: Colors.grey,
                  letterSpacing: 1,
                ),
              ),
            ),
          for (final item in section.items)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: ListTile(
                leading: Icon(
                  item.icon,
                  color: item.path == '/intake'
                      ? theme.colorScheme.primary
                      : null,
                ),
                title: Text(
                  item.title,
                  style: item.path == '/intake'
                      ? TextStyle(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.bold,
                        )
                      : null,
                ),
                selected: item.path == '/'
                    ? location == '/'
                    : location.startsWith(item.path),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(28),
                ),
                onTap: () {
                  Navigator.of(context).pop();
                  // Intake is a task flow (with back), not a menu page.
                  if (item.path == '/intake') {
                    context.push(item.path);
                  } else {
                    context.go(item.path);
                  }
                },
              ),
            ),
        ],
        const SizedBox(height: 16),
      ],
    );
  }
}
