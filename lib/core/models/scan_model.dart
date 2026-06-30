class ScanModel {
  final int? id;
  final String originalImagePath;
  final String overlayImagePath;
  final String diseaseName;
  final double confidence;
  final String severity;
  final int inferenceTimeMs;
  final DateTime createdAt;
  final String? originalUnenhancedPath;

  ScanModel({
    this.id,
    required this.originalImagePath,
    required this.overlayImagePath,
    required this.diseaseName,
    required this.confidence,
    required this.severity,
    required this.inferenceTimeMs,
    required this.createdAt,
    this.originalUnenhancedPath,
  });

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'original_image_path': originalImagePath,
      'overlay_image_path': overlayImagePath,
      'disease_name': diseaseName,
      'confidence': confidence,
      'severity': severity,
      'inference_time_ms': inferenceTimeMs,
      'created_at': createdAt.toIso8601String(),
      'original_unenhanced_path': originalUnenhancedPath,
    };
  }

  factory ScanModel.fromMap(Map<String, dynamic> map) {
    return ScanModel(
      id: map['id'] as int?,
      originalImagePath: map['original_image_path'] as String,
      overlayImagePath: map['overlay_image_path'] as String,
      diseaseName: map['disease_name'] as String,
      confidence: (map['confidence'] as num).toDouble(),
      severity: map['severity'] as String,
      inferenceTimeMs: map['inference_time_ms'] as int,
      createdAt: DateTime.parse(map['created_at'] as String),
      originalUnenhancedPath: map['original_unenhanced_path'] as String?,
    );
  }
}
