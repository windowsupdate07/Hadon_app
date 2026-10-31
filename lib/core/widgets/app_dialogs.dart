import 'package:flutter/material.dart';

/// Standard Thai dialogs, matching the web app's SweetAlert wording.
class AppDialogs {
  AppDialogs._();

  static Future<void> success(BuildContext context, [String? message]) {
    return _alert(
      context,
      icon: Icons.check_circle,
      color: Colors.green,
      title: 'สำเร็จ!',
      message: message ?? 'บันทึกข้อมูลเรียบร้อยแล้ว',
    );
  }

  static Future<void> error(BuildContext context, Object error) {
    return _alert(
      context,
      icon: Icons.error,
      color: Colors.red,
      title: 'เกิดข้อผิดพลาด!',
      message: error.toString(),
    );
  }

  static Future<void> warn(BuildContext context, String message) {
    return _alert(
      context,
      icon: Icons.warning_amber_rounded,
      color: Colors.orange,
      title: 'แจ้งเตือน!',
      message: message,
    );
  }

  /// Returns true when the user taps "ยืนยัน".
  static Future<bool> confirm(
    BuildContext context, {
    String title = 'ยืนยันการทำรายการ?',
    String message = 'ท่านต้องการทำรายการนี้ ใช่หรือไม่?',
    bool destructive = false,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: Icon(
          destructive ? Icons.delete_forever : Icons.help_outline,
          color: destructive ? Colors.red : Colors.blue,
          size: 40,
        ),
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: destructive ? Colors.red : Colors.blue,
            ),
            child: const Text('ยืนยัน'),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  static Future<bool> confirmDelete(BuildContext context, [String? what]) {
    return confirm(
      context,
      message: 'ท่านต้องการลบ${what ?? 'ข้อมูล'} ใช่หรือไม่?',
      destructive: true,
    );
  }

  static void toast(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  static Future<void> _alert(
    BuildContext context, {
    required IconData icon,
    required Color color,
    required String title,
    required String message,
  }) {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        icon: Icon(icon, color: color, size: 40),
        title: Text(title),
        content: Text(message),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('ตกลง'),
          ),
        ],
      ),
    );
  }
}

/// Runs [action] behind a blocking progress dialog and reports errors.
/// Returns the action's result, or null if it threw.
Future<T?> runWithProgress<T>(
  BuildContext context,
  Future<T> Function() action, {
  String? successMessage,
}) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    useRootNavigator: true,
    builder: (_) => const PopScope(
      canPop: false,
      child: Center(child: CircularProgressIndicator()),
    ),
  );
  try {
    final result = await action();
    navigator.pop();
    if (successMessage != null && context.mounted) {
      AppDialogs.toast(context, successMessage);
    }
    return result;
  } catch (e) {
    navigator.pop();
    if (context.mounted) {
      await AppDialogs.error(context, e);
    }
    return null;
  }
}
