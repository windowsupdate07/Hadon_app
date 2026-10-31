import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/account_page.dart';
import '../features/auth/auth_provider.dart';
import '../features/auth/login_page.dart';
import '../features/cars/cars_page.dart';
import '../features/customers/customer_detail_page.dart';
import '../features/customers/customers_page.dart';
import '../features/employees/employees_page.dart';
import '../features/home/home_page.dart';
import '../features/invoices/invoice_detail_page.dart';
import '../features/invoices/invoices_page.dart';
import '../features/parts/parts_page.dart';
import '../features/presets/presets_page.dart';
import '../features/quotations/quotation_detail_page.dart';
import '../features/quotations/quotations_page.dart';
import '../features/repairs/repair_detail_page.dart';
import '../features/repairs/repairs_page.dart';
import '../features/vendors/vendors_page.dart';
import '../layouts/app_scaffold.dart';

GoRouter createRouter(AuthProvider auth) {
  return GoRouter(
    initialLocation: '/',
    refreshListenable: auth,
    redirect: (context, state) {
      final loggingIn = state.matchedLocation == '/login';
      final splash = state.matchedLocation == '/splash';
      switch (auth.status) {
        case AuthStatus.unknown:
          return splash ? null : '/splash';
        case AuthStatus.unauthenticated:
          return loggingIn ? null : '/login';
        case AuthStatus.authenticated:
          return (loggingIn || splash) ? '/' : null;
      }
    },
    routes: [
      GoRoute(path: '/splash', builder: (_, _) => const _SplashPage()),
      GoRoute(path: '/login', builder: (_, _) => const LoginPage()),
      GoRoute(path: '/', builder: (_, _) => const HomePage()),
      GoRoute(
        path: '/repairs',
        builder: (_, _) => const RepairsPage(),
        routes: [
          GoRoute(
            path: ':id',
            builder: (_, s) =>
                RepairDetailPage(repairId: _intParam(s, 'id')),
          ),
        ],
      ),
      GoRoute(
        path: '/customers',
        builder: (_, _) => const CustomersPage(),
        routes: [
          GoRoute(
            path: ':id',
            builder: (_, s) =>
                CustomerDetailPage(customerId: _intParam(s, 'id')),
          ),
        ],
      ),
      GoRoute(path: '/cars', builder: (_, _) => const CarsPage()),
      GoRoute(
        path: '/quotations',
        builder: (_, _) => const QuotationsPage(),
        routes: [
          GoRoute(
            path: ':id',
            builder: (_, s) =>
                QuotationDetailPage(quotationId: s.pathParameters['id']!),
          ),
        ],
      ),
      GoRoute(
        path: '/invoices',
        builder: (_, _) => const InvoicesPage(),
        routes: [
          GoRoute(
            path: ':id',
            builder: (_, s) =>
                InvoiceDetailPage(invoiceId: s.pathParameters['id']!),
          ),
        ],
      ),
      GoRoute(path: '/parts', builder: (_, _) => const PartsPage()),
      GoRoute(path: '/vendors', builder: (_, _) => const VendorsPage()),
      GoRoute(path: '/employees', builder: (_, _) => const EmployeesPage()),
      GoRoute(path: '/presets', builder: (_, _) => const PresetsPage()),
      GoRoute(
        path: '/account',
        builder: (_, _) =>
            const AppScaffold(title: 'บัญชีผู้ใช้', body: AccountPage()),
      ),
    ],
  );
}

int _intParam(GoRouterState s, String name) =>
    int.tryParse(s.pathParameters[name] ?? '') ?? 0;

class _SplashPage extends StatelessWidget {
  const _SplashPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset('assets/images/ntp-logo.png', height: 100),
            const SizedBox(height: 24),
            const CircularProgressIndicator(),
          ],
        ),
      ),
    );
  }
}
