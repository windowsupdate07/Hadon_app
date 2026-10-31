import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:provider/provider.dart';

import '../network/api_client.dart';
import 'app_dialogs.dart';

/// Downloads a server-generated PDF (with auth header) and opens it in the
/// device's PDF viewer. [path] is relative to the API base, e.g.
/// `/pdf/create-invoice/INV-20260301-001`.
Future<void> openServerPdf(
  BuildContext context,
  String path,
  String fileName,
) async {
  final api = context.read<ApiClient>();
  final file = await runWithProgress(
    context,
    () => api.download(
      path,
      fileName.endsWith('.pdf') ? fileName : '$fileName.pdf',
    ),
  );
  if (file == null) {
    return;
  }
  final result = await OpenFilex.open(file.path, type: 'application/pdf');
  if (result.type != ResultType.done && context.mounted) {
    await AppDialogs.warn(
      context,
      'ไม่สามารถเปิดไฟล์ PDF ได้: ${result.message}',
    );
  }
}
