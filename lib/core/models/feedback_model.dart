class FeedbackModel {
  final String id;
  final int scanId;
  final String originalDisease;
  final String originalSeverity;
  final String? userDisease;
  final String? userSeverity;
  final double confidence;
  final String feedbackType; // 'positive' or 'negative'
  final DateTime createdAt;

  FeedbackModel({
    required this.id,
    required this.scanId,
    required this.originalDisease,
    required this.originalSeverity,
    this.userDisease,
    this.userSeverity,
    required this.confidence,
    required this.feedbackType,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'scan_id': scanId,
      'original_disease': originalDisease,
      'original_severity': originalSeverity,
      'user_disease': userDisease,
      'user_severity': userSeverity,
      'confidence': confidence,
      'feedback_type': feedbackType,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory FeedbackModel.fromMap(Map<String, dynamic> map) {
    return FeedbackModel(
      id: map['id'] as String,
      scanId: map['scan_id'] as int,
      originalDisease: map['original_disease'] as String,
      originalSeverity: map['original_severity'] as String,
      userDisease: map['user_disease'] as String?,
      userSeverity: map['user_severity'] as String?,
      confidence: (map['confidence'] as num).toDouble(),
      feedbackType: map['feedback_type'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}
