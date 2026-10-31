import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../core/network/api_client.dart';
import '../../core/widgets/app_dialogs.dart';
import '../auth/employee.dart';
import 'employees_api.dart';

/// Bumped after a profile image changes. Uploads keep the same file name
/// (`<Username>.jpg`), so the URL gets a `t=` query to bypass the image
/// cache (the server ignores the query string).
final profileImageVersion = ValueNotifier<int>(
  DateTime.now().millisecondsSinceEpoch,
);

/// The web falls back to this avatar when `ProfileImage` is empty.
const _fallbackProfileImage = 'user-1.jpg';

/// `GET /images/profile/:filename` (JWT protected).
String profileImageUrl(ApiClient api, String? filename) {
  final name = Uri.encodeComponent(
    (filename == null || filename.isEmpty) ? _fallbackProfileImage : filename,
  );
  return api.url('/images/profile/$name?t=${profileImageVersion.value}');
}

/// Round avatar from `ProfileImage`, falling back to initials while loading
/// or when the image cannot be fetched (e.g. expired token, missing file —
/// the server then answers 202 JSON, which fails to decode).
class EmployeeAvatar extends StatelessWidget {
  const EmployeeAvatar({
    super.key,
    required this.employee,
    this.radius = 20,
    this.dimmed = false,
  });

  final Employee employee;
  final double radius;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: profileImageVersion,
      builder: (context, _, _) => _ProfileImageCircle(
        filename: employee.profileImage,
        initials: employee.initials,
        radius: radius,
        dimmed: dimmed,
      ),
    );
  }
}

class _ProfileImageCircle extends StatelessWidget {
  const _ProfileImageCircle({
    required this.filename,
    required this.radius,
    this.initials,
    this.dimmed = false,
  });

  final String? filename;
  final String? initials;
  final double radius;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final api = context.read<ApiClient>();
    final size = radius * 2;
    final fallback = CircleAvatar(
      radius: radius,
      backgroundColor: dimmed ? Colors.grey.shade400 : null,
      child: Text(initials ?? '?'),
    );
    final cacheSize = (size * MediaQuery.devicePixelRatioOf(context)).round();
    final image = ClipOval(
      child: Image.network(
        profileImageUrl(api, filename),
        headers: api.authHeaders,
        width: size,
        height: size,
        fit: BoxFit.cover,
        cacheWidth: cacheSize,
        frameBuilder: (context, child, frame, sync) =>
            (frame == null && !sync) ? fallback : child,
        errorBuilder: (_, _, _) => fallback,
      ),
    );
    if (!dimmed) {
      return image;
    }
    return Opacity(opacity: 0.6, child: image);
  }
}

/// Lets the user pick a default avatar, a gallery photo or a camera photo
/// for [target], uploads it when needed and saves `ProfileImage`.
/// Returns true when the profile image was changed.
Future<bool> changeEmployeePhoto(BuildContext context, Employee target) async {
  final choice = await showModalBottomSheet<_PhotoChoice>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => _PhotoSheet(current: target.profileImage),
  );
  if (choice == null || !context.mounted) {
    return false;
  }

  final api = EmployeesApi(context.read<ApiClient>());
  String? localPath;
  final source = choice.source;
  if (source != null) {
    try {
      final file = await ImagePicker().pickImage(
        source: source,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 80,
        preferredCameraDevice: CameraDevice.front,
      );
      localPath = file?.path;
    } catch (e) {
      if (context.mounted) {
        await AppDialogs.error(context, 'ไม่สามารถเปิดกล้อง/คลังรูปภาพได้: $e');
      }
      return false;
    }
    if (localPath == null || !context.mounted) {
      return false;
    }
  }

  final path = localPath;
  final done = await runWithProgress(context, () async {
    final filename = path != null
        ? await api.uploadProfileImage(target.username, path)
        : choice.preset!;
    // Re-uploads keep the same file name; the column is already correct.
    if (filename != target.profileImage) {
      await api.setProfileImage(target.id, filename);
    }
    return true;
  }, successMessage: 'อัปเดตรูปโปรไฟล์เรียบร้อยแล้ว');
  if (done != true) {
    return false;
  }
  profileImageVersion.value = DateTime.now().millisecondsSinceEpoch;
  return true;
}

class _PhotoChoice {
  const _PhotoChoice.source(ImageSource this.source) : preset = null;
  const _PhotoChoice.preset(String this.preset) : source = null;

  final ImageSource? source;
  final String? preset;
}

class _PhotoSheet extends StatelessWidget {
  const _PhotoSheet({this.current});

  final String? current;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('เปลี่ยนรูปโปรไฟล์', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.photo_camera),
              title: const Text('ถ่ายรูป'),
              onTap: () => Navigator.of(
                context,
              ).pop(const _PhotoChoice.source(ImageSource.camera)),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.photo_library),
              title: const Text('เลือกจากคลังรูปภาพ'),
              onTap: () => Navigator.of(
                context,
              ).pop(const _PhotoChoice.source(ImageSource.gallery)),
            ),
            const Divider(),
            Text('หรือเลือกรูปเริ่มต้น', style: theme.textTheme.labelLarge),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              alignment: WrapAlignment.center,
              children: [
                for (final name in defaultProfileImages)
                  InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () =>
                        Navigator.of(context).pop(_PhotoChoice.preset(name)),
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          width: 2,
                          color: name == current
                              ? theme.colorScheme.primary
                              : Colors.transparent,
                        ),
                      ),
                      child: _ProfileImageCircle(filename: name, radius: 28),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
