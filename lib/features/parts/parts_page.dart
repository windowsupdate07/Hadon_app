import 'package:flutter/material.dart';

import '../../core/widgets/state_views.dart';
import '../../layouts/app_scaffold.dart';

class PartsPage extends StatelessWidget {
  const PartsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const AppScaffold(
      title: 'สินค้าคงคลัง',
      body: EmptyView(message: 'กำลังพัฒนา'),
    );
  }
}
