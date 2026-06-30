import 'package:flutter/material.dart' show Color;

class DiseaseInfo {
  final String id;
  final String scientificName;
  final String categoryKey;
  final Color themeColor;
  final List<String> imageAssets;
  final String source;

  const DiseaseInfo({
    required this.id,
    required this.scientificName,
    required this.categoryKey,
    required this.themeColor,
    required this.imageAssets,
    required this.source,
  });
}
