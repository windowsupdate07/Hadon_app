import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../../core/data/lookups.dart';
import '../../../core/widgets/app_dialogs.dart';
import '../../../core/widgets/common.dart';
import '../quotation_models.dart';
import '../quotations_api.dart';

/// Car photos of a quotation (`GET /imageCar/quotationID/:id`), with upload
/// (`POST /imageCar`) and delete (`DELETE /imageCar/:id`) while the
/// quotation is still editable — like the web's CarImages + ImageUploader.
class QuotationPhotosSection extends StatefulWidget {
  const QuotationPhotosSection({
    super.key,
    required this.api,
    required this.quotationId,
    required this.editable,
    this.onChanged,
  });

  final QuotationsApi api;
  final String quotationId;
  final bool editable;

  /// Called with the current list after every (re)load.
  final ValueChanged<List<QuotationImage>>? onChanged;

  @override
  State<QuotationPhotosSection> createState() => QuotationPhotosSectionState();
}

class QuotationPhotosSectionState extends State<QuotationPhotosSection> {
  late Future<List<QuotationImage>> _future;

  QuotationsApi get _api => widget.api;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<QuotationImage>> _load() async {
    final list = await _api.images(widget.quotationId);
    list.sort((a, b) => (a.typeId ?? 999).compareTo(b.typeId ?? 999));
    widget.onChanged?.call(list);
    return list;
  }

  void reload() => setState(() {
    _future = _load();
  });

  Future<void> _add(List<QuotationImage> existing) async {
    final typeId = await _pickType(existing);
    if (typeId == null || !mounted) {
      return;
    }
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
    final picked = file;
    final done = await runWithProgress(context, () async {
      await _api.uploadImage(
        quotationId: widget.quotationId,
        imageCarTypeId: typeId,
        filePath: picked.path,
        fileName: picked.name,
      );
      return true;
    }, successMessage: 'อัปโหลดรูปภาพเรียบร้อยแล้ว');
    if (done == true && mounted) {
      reload();
    }
  }

  /// Angles 1..8 can be uploaded once each (the web hides used ones);
  /// 99 (อื่นๆ) any number of times.
  Future<int?> _pickType(List<QuotationImage> existing) async {
    final lookups = context.read<Lookups>();
    final types = await runWithProgress(context, lookups.imageCarTypes);
    if (types == null || !mounted) {
      return null;
    }
    final used = existing.map((i) => i.typeId).toSet();
    final available = [...types]
      ..removeWhere((t) => t.id != otherImageTypeId && used.contains(t.id))
      ..sort((a, b) => a.id.compareTo(b.id));
    return showDialog<int>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('เลือกประเภทรูปภาพ'),
        children: [
          for (final t in available)
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(t.id),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(t.label),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _delete(QuotationImage image) async {
    final ok = await AppDialogs.confirmDelete(context, 'รูปภาพนี้');
    if (!ok || !mounted) {
      return;
    }
    final done = await runWithProgress(context, () async {
      await _api.deleteImage(image.id);
      return true;
    }, successMessage: 'ลบรูปภาพเรียบร้อยแล้ว');
    if (done == true && mounted) {
      reload();
    }
  }

  void _view(List<QuotationImage> images, int index) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            _PhotoViewerPage(api: _api, images: images, initialIndex: index),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<QuotationImage>>(
      future: _future,
      builder: (context, snap) {
        final images = snap.data ?? const <QuotationImage>[];
        final loading = snap.connectionState != ConnectionState.done;
        final missing = requiredImageTypeIds
            .where((id) => !images.any((i) => i.typeId == id))
            .length;
        return SectionCard(
          title: 'รูปภาพรถยนต์ (${images.length})',
          trailing: widget.editable && !loading && !snap.hasError
              ? TextButton.icon(
                  onPressed: () => _add(images),
                  icon: const Icon(Icons.add_a_photo_outlined),
                  label: const Text('อัปโหลด'),
                )
              : null,
          child: _content(snap, images, missing),
        );
      },
    );
  }

  Widget _content(
    AsyncSnapshot<List<QuotationImage>> snap,
    List<QuotationImage> images,
    int missing,
  ) {
    if (snap.connectionState != ConnectionState.done) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (snap.hasError) {
      return Row(
        children: [
          Expanded(
            child: Text(
              '${snap.error}',
              style: const TextStyle(color: Colors.red),
            ),
          ),
          TextButton(onPressed: reload, child: const Text('ลองใหม่')),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (missing > 0 && widget.editable)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'ยังขาดรูปมาตรฐานอีก $missing มุม (จาก 8 มุม)',
              style: const TextStyle(fontSize: 12, color: Colors.orange),
            ),
          ),
        if (images.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('ยังไม่มีรูปภาพ', style: TextStyle(color: Colors.grey)),
          )
        else
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: images.length,
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 130,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 0.85,
            ),
            itemBuilder: (context, i) => _thumb(images, i),
          ),
      ],
    );
  }

  Widget _thumb(List<QuotationImage> images, int i) {
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
                    tag: 'quotation-image-${image.id}',
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

  final QuotationsApi api;
  final QuotationImage image;
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

  final QuotationsApi api;
  final List<QuotationImage> images;
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
                tag: 'quotation-image-${image.id}',
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
