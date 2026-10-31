import 'package:flutter/material.dart';

import '../../core/widgets/state_views.dart';
import '../../layouts/app_scaffold.dart';

class PresetsPage extends StatelessWidget {
  const PresetsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const AppScaffold(
      title: 'พรีเซ็ตข้อมูล',
      body: EmptyView(message: 'กำลังพัฒนา'),
    );
  }
}
