import 'package:flutter/material.dart';

import '../../core/widgets/state_views.dart';
import '../../layouts/app_scaffold.dart';

class VendorsPage extends StatelessWidget {
  const VendorsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const AppScaffold(
      title: 'ข้อมูลคู่ค้า',
      body: EmptyView(message: 'กำลังพัฒนา'),
    );
  }
}
