import 'package:flutter/material.dart';

import '../../core/widgets/state_views.dart';
import '../../layouts/app_scaffold.dart';

class CustomersPage extends StatelessWidget {
  const CustomersPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const AppScaffold(
      title: 'ข้อมูลลูกค้า',
      body: EmptyView(message: 'กำลังพัฒนา'),
    );
  }
}
