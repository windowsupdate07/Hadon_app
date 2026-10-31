import 'package:flutter/material.dart';

import '../../core/widgets/state_views.dart';
import '../../layouts/app_scaffold.dart';

class QuotationsPage extends StatelessWidget {
  const QuotationsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const AppScaffold(
      title: 'ใบเสนอราคา',
      body: EmptyView(message: 'กำลังพัฒนา'),
    );
  }
}
