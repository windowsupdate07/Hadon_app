import 'package:flutter/material.dart';

import '../../core/widgets/state_views.dart';
import '../../layouts/app_scaffold.dart';

class CarsPage extends StatelessWidget {
  const CarsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const AppScaffold(
      title: 'ข้อมูลรถยนต์',
      body: EmptyView(message: 'กำลังพัฒนา'),
    );
  }
}
