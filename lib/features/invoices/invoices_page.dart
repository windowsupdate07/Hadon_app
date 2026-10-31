import 'package:flutter/material.dart';

import '../../core/widgets/state_views.dart';
import '../../layouts/app_scaffold.dart';

class InvoicesPage extends StatelessWidget {
  const InvoicesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const AppScaffold(
      title: 'ใบแจ้งหนี้',
      body: EmptyView(message: 'กำลังพัฒนา'),
    );
  }
}
