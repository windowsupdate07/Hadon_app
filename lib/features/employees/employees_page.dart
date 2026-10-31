import 'package:flutter/material.dart';

import '../../core/widgets/state_views.dart';
import '../../layouts/app_scaffold.dart';

class EmployeesPage extends StatelessWidget {
  const EmployeesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const AppScaffold(
      title: 'ข้อมูลพนักงาน',
      body: EmptyView(message: 'กำลังพัฒนา'),
    );
  }
}
