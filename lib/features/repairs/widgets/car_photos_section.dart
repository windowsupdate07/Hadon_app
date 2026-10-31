import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../../core/data/lookups.dart';
import '../../../core/widgets/app_dialogs.dart';
import '../../../core/widgets/common.dart';
import '../repair_models.dart';
import '../repairs_api.dart';
import 'inline_error.dart';

/// Car photos taken at check-in (`ImageCar`). They are stored per
/// quotation, so a repair without a QuotationID has no photos.
class CarPhotosSection extends StatefulWidget {
  const CarPhotosSection({
    super.key,
    required this.api,
    required this.quotationId,
    required this.editable,
  });

  final RepairsApi api;
  final String? quotationId;

  /// Add / delete allowed.
  final bool editable;

  @override
  State<CarPhotosSection> createState() => _CarPhotosSectionState();
}

class _CarPhotosSectionState extends State<CarPhotosSection> {
  late Future<List<CarImage>> _future;

  RepairsApi get _api => widget.api;

  /// Types 1-8 are the standard shots and allowed once each (same rule as
  /// the web uploader); "other" (99) can repeat.
  static const _otherType = 99;

  List<CarImage> _current = const [];

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<CarImage>> _load() async {
    final id = widget.quotationId;
    if (id == null) {
      return const [];
    }
    final list = await _api.images(id);
    _current = list;
    return list;
  }

  void _reload() {
    setState(() {
      _future = _load();
    });
  }

  Future<void> _add() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera),
              title: const Text('ถ่ายรูป'),
              onTap: () => Navigator.of(context).pop(ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('เลือกจากคลังรูปภาพ'),
              onTap: () => Navigator.of(context).pop(ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null || !mounted) {
      return;
    }

    XFile? file;
    try {
      file = await ImagePicker().pickImage(
        source: source,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );
    } catch (e) {
      if (mounted) {
        await AppDialogs.error(context, 'ไม่สามารถเปิดกล้อง/คลังรูปภาพได้: $e');
      }
      return;
    }
    if (file == null || !mounted) {
      return;
    }

    final typeId = await _pickType();
    if (typeId == null || !mounted) {
      return;
    }

    final picked = file;
    final done = await runWithProgress(context, () async {
      await _api.uploadImage(
        quotationId: widget.quotationId!,
        imageCarTypeId: typeId,
        filePath: picked.path,
        fileName: picked.name,
      );
      return true;
    }, successMessage: 'อัปโหลดรูปภาพเรียบร้อยแล้ว');
    if (done == true && mounted) {
      _reload();
    }
  }

  Future<int?> _pickType() async {
    final lookups = context.read<Lookups>();
    final types = await runWithProgress(context, lookups.imageCarTypes);
    if (types == null || !mounted) {
      return null;
    }
    // Keep the seeded order (front, back, ... other) rather than alphabetical.
    final sorted = [...types]..sort((a, b) => a.id.compareTo(b.id));
    final used = {
      for (final i in _current)
        if (i.typeId != null && i.typeId != _otherType) i.typeId!,
    };
    return showDialog<int>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('เลือกประเภทรูปภาพ'),
        children: [
          for (final t in sorted)
            SimpleDialogOption(
              onPressed: used.contains(t.id)
                  ? null
                  : () => Navigator.of(context).pop(t.id),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(
                  used.contains(t.id) ? '${t.label} (มีรูปแล้ว)' : t.label,
                  style: used.contains(t.id)
                      ? const TextStyle(color: Colors.grey)
                      : null,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _delete(CarImage image) async {
    final ok = await AppDialogs.confirmDelete(context, 'รูปภาพนี้');
    if (!ok || !mounted) {
      return;
    }
    final done = await runWithProgress(context, () async {
      await _api.deleteImage(image.id);
      return true;
    }, successMessage: 'ลบรูปภาพเรียบร้อยแล้ว');
    if (done == true && mounted) {
      _reload();
    }
  }

  void _view(List<CarImage> images, int index) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            _PhotoViewerPage(api: _api, images: images, initialIndex: index),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.quotationId == null) {
      return const SectionCard(
        title: 'รูปภาพรถยนต์',
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Text(
            'งานซ่อมนี้ไม่ได้สร้างจากใบเสนอราคา จึงไม่มีรูปภาพรถยนต์',
            style: TextStyle(color: Colors.grey),
          ),
        ),
      );
    }
    return SectionCard(
      title: 'รูปภาพรถยนต์',
      trailing: widget.editable
          ? TextButton.icon(
              onPressed: _add,
              icon: const Icon(Icons.add_a_photo_outlined),
              label: const Text('เพิ่มรูป'),
            )
          : null,
      child: FutureBuilder<List<CarImage>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          if (snap.hasError) {
            return InlineError(error: snap.error!, onRetry: _reload);
          }
          final images = snap.data!;
          if (images.isEmpty) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'ยังไม่มีรูปภาพ',
                style: TextStyle(color: Colors.grey),
              ),
            );
          }
          return GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: images.length,
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 140,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 0.85,
            ),
            itemBuilder: (context, i) => _thumb(images, i),
          );
        },
      ),
    );
  }

  Widget _thumb(List<CarImage> images, int i) {
    final image = images[i];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: GestureDetector(
                  onTap: () => _view(images, i),
                  child: Hero(
                    tag: 'car-image-${image.id}',
                    child: _NetworkCarImage(
                      api: _api,
                      image: image,
                      fit: BoxFit.cover,
                      cacheWidth: 320,
                    ),
                  ),
                ),
              ),
              if (widget.editable)
                Positioned(
                  top: 2,
                  right: 2,
                  child: Material(
                    color: Colors.black45,
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () => _delete(image),
                      child: const Padding(
                        padding: EdgeInsets.all(4),
                        child: Icon(Icons.close, size: 16, color: Colors.white),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          image.typeName ?? '-',
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

/// Authenticated image from `GET /images/car/:quotationId/:filename`.
class _NetworkCarImage extends StatelessWidget {
  const _NetworkCarImage({
    required this.api,
    required this.image,
    this.fit,
    this.cacheWidth,
  });

  final RepairsApi api;
  final CarImage image;
  final BoxFit? fit;
  final int? cacheWidth;

  @override
  Widget build(BuildContext context) {
    return Image.network(
      api.imageUrl(image),
      headers: api.authHeaders,
      fit: fit,
      cacheWidth: cacheWidth,
      loadingBuilder: (context, child, progress) {
        if (progress == null) {
          return child;
        }
        return const ColoredBox(
          color: Color(0x11000000),
          child: Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        );
      },
      errorBuilder: (context, error, stack) => const ColoredBox(
        color: Color(0x11000000),
        child: Center(
          child: Icon(Icons.broken_image_outlined, color: Colors.grey),
        ),
      ),
    );
  }
}

class _PhotoViewerPage extends StatefulWidget {
  const _PhotoViewerPage({
    required this.api,
    required this.images,
    required this.initialIndex,
  });

  final RepairsApi api;
  final List<CarImage> images;
  final int initialIndex;

  @override
  State<_PhotoViewerPage> createState() => _PhotoViewerPageState();
}

class _PhotoViewerPageState extends State<_PhotoViewerPage> {
  late final PageController _controller = PageController(
    initialPage: widget.initialIndex,
  );
  late int _index = widget.initialIndex;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final current = widget.images[_index];
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          '${current.typeName ?? 'รูปภาพ'} (${_index + 1}/${widget.images.length})',
        ),
      ),
      body: PageView.builder(
        controller: _controller,
        itemCount: widget.images.length,
        onPageChanged: (i) => setState(() => _index = i),
        itemBuilder: (context, i) {
          final image = widget.images[i];
          return InteractiveViewer(
            minScale: 1,
            maxScale: 5,
            child: Center(
              child: Hero(
                tag: 'car-image-${image.id}',
                child: _NetworkCarImage(
                  api: widget.api,
                  image: image,
                  fit: BoxFit.contain,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
