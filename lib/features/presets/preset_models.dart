import '../../core/utils/json.dart';
import '../parts/part_model.dart';

/// `Preset.Status`: 1 = ACTIVE, 2 = INACTIVE.
class PresetStatus {
  PresetStatus._();

  static const active = 1;
  static const inactive = 2;
}

/// `PresetDetails` row: a part and how many units the preset uses.
class PresetDetail {
  const PresetDetail({
    required this.id,
    required this.presetId,
    required this.partId,
    required this.numOfUse,
    this.part,
  });

  factory PresetDetail.fromJson(Map<String, dynamic> j) {
    // Default Sequelize alias for PresetDetails.belongsTo(Parts) is "part".
    final part = asMap(j['part'] ?? j['Part'] ?? j['parts']);
    return PresetDetail(
      id: asInt(j['PresetDetailID']) ?? 0,
      presetId: asInt(j['PresetID']) ?? 0,
      partId: asInt(j['PartID']) ?? 0,
      numOfUse: asInt(j['NumOfUse']) ?? 0,
      part: part == null ? null : Part.fromJson(part),
    );
  }

  final int id;
  final int presetId;
  final int partId;
  final int numOfUse;

  /// Null when the part was (soft) deleted.
  final Part? part;

  String get partName => part?.displayName ?? 'อะไหล่ #$partId (ถูกลบแล้ว)';
}

/// `Preset` with its `presetDetails` (+ part) and
/// `ref_model_category_parts` includes from `GET /preset`.
class Preset {
  const Preset({
    required this.id,
    required this.name,
    required this.status,
    this.details = const [],
    this.refCount = 0,
  });

  factory Preset.fromJson(Map<String, dynamic> j) {
    final details = asMapList(
      j['presetDetails'] ?? j['PresetDetails'],
    ).map(PresetDetail.fromJson).toList();
    final refs = j['ref_model_category_parts'] ?? j['Ref_Model_Category_Parts'];
    return Preset(
      id: asInt(j['PresetID']) ?? 0,
      name: asString(j['Preset']) ?? '',
      status: asInt(j['Status']) ?? PresetStatus.active,
      details: details,
      refCount: refs is List ? refs.length : 0,
    );
  }

  final int id;
  final String name;
  final int status;
  final List<PresetDetail> details;

  /// Number of brand/model/category references that use this preset.
  final int refCount;

  bool get isActive => status == PresetStatus.active;

  /// Sum of `NumOfUse * PricePerUnit` for parts that still exist.
  double get totalPrice => details.fold(
    0,
    (sum, d) => sum + d.numOfUse * (d.part?.pricePerUnit ?? 0),
  );

  bool matches(String q) {
    final s = q.toLowerCase();
    return name.toLowerCase().contains(s) ||
        details.any((d) => d.part?.matches(q) ?? false);
  }
}
