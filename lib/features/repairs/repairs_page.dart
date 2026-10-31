import 'package:flutter/material.dart';

import '../../core/widgets/state_views.dart';
import '../../layouts/app_scaffold.dart';

class RepairsPage extends StatelessWidget {
  const RepairsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const AppScaffold(
      title: 'ซ่อมรถยนต์',
      body: EmptyView(message: 'กำลังพัฒนา'),
    );
  }
}
