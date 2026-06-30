import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/disease.dart';
import 'disease_detail_screen.dart';
import '../../../core/services/localization_provider.dart';
import '../../../core/services/providers.dart';
import '../../../core/widgets/glass_card.dart';

class EducationGuideScreen extends ConsumerStatefulWidget {
  const EducationGuideScreen({super.key});

  @override
  ConsumerState<EducationGuideScreen> createState() => _EducationGuideScreenState();
}

class _EducationGuideScreenState extends ConsumerState<EducationGuideScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = "";
  bool _showOnlyFavorites = false;

  static const List<DiseaseInfo> _diseases = [
    DiseaseInfo(
      id: "Healthy",
      scientificName: "Musa acuminata / balbisiana",
      categoryKey: "cat_Normal_Status",
      themeColor: Color(0xFF4CAF50),
      imageAssets: [
        'assets/images/healthy_low.jpg',
        'assets/images/healthy_medium.jpg',
        'assets/images/healthy_high.jpg',
      ],
      source: "DOA Sri Lanka, FAO",
    ),
    DiseaseInfo(
      id: "Moko",
      scientificName: "Ralstonia solanacearum",
      categoryKey: "cat_Bacterial_Wilt",
      themeColor: Color(0xFFC62828),
      imageAssets: [
        'assets/images/moko_low.jpg',
        'assets/images/moko_medium.jpg',
        'assets/images/moko_high.jpg',
      ],
      source: "DOA Sri Lanka, FAO",
    ),
    DiseaseInfo(
      id: "Panama_Disease",
      scientificName: "Fusarium oxysporum f. sp. cubense (TR4)",
      categoryKey: "cat_Fungal_Wilt",
      themeColor: Color(0xFFC62828),
      imageAssets: [
        'assets/images/panama_low.jpg',
        'assets/images/panama_medium.jpg',
        'assets/images/panama_high.jpg',
      ],
      source: "DOA Sri Lanka, FAO",
    ),
    DiseaseInfo(
      id: "Black_Sigatoka",
      scientificName: "Pseudocercospora fijiensis",
      categoryKey: "cat_Fungal_Leaf_Spot",
      themeColor: Color(0xFFC62828),
      imageAssets: [
        'assets/images/black_sigatoka_low.jpg',
        'assets/images/black_sigatoka_medium.jpg',
        'assets/images/black_sigatoka_high.jpg',
      ],
      source: "DOA Sri Lanka, FAO",
    ),
    DiseaseInfo(
      id: "Yellow_Sigatoka",
      scientificName: "Pseudocercospora musae",
      categoryKey: "cat_Fungal_Leaf_Spot",
      themeColor: Color(0xFFFBC02D),
      imageAssets: [
        'assets/images/yellow_sigatoka_low.jpg',
        'assets/images/yellow_sigatoka_medium.jpg',
        'assets/images/yellow_sigatoka_high.jpg',
      ],
      source: "DOA Sri Lanka, FAO",
    ),
    DiseaseInfo(
      id: "Cordana",
      scientificName: "Cordana musae",
      categoryKey: "cat_Fungal_Leaf_Spot",
      themeColor: Color(0xFFFF9800),
      imageAssets: [
        'assets/images/cordana_low.jpg',
        'assets/images/cordana_medium.jpg',
        'assets/images/cordana_high.jpg',
      ],
      source: "DOA Sri Lanka, FAO",
    ),
    DiseaseInfo(
      id: "Pestalotiopsis",
      scientificName: "Pestalotiopsis spp.",
      categoryKey: "cat_Fungal_Infection",
      themeColor: Color(0xFF8D6E63),
      imageAssets: [
        'assets/images/pestalotiopsis_low.jpg',
        'assets/images/pestalotiopsis_medium.jpg',
        'assets/images/pestalotiopsis_high.jpg',
      ],
      source: "DOA Sri Lanka, FAO",
    ),
  ];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final locale = ref.watch(localeProvider);
    final favorites = ref.watch(favoriteDiseasesProvider);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final filteredDiseases = _diseases.where((disease) {
      // 1. Favorite filtering
      if (_showOnlyFavorites && !favorites.contains(disease.id)) {
        return false;
      }

      // 2. Search query filtering
      final name = getTranslation('disease_${disease.id}', locale).toLowerCase();
      final category = getTranslation(disease.categoryKey, locale).toLowerCase();
      final symptoms = getTranslation('disease_${disease.id}_symptoms', locale).toLowerCase();
      final scientificName = disease.scientificName.toLowerCase();
      final query = _searchQuery.toLowerCase();

      return name.contains(query) ||
          category.contains(query) ||
          scientificName.contains(query) ||
          symptoms.contains(query);
    }).toList();

    return Column(
      children: [
        // Search & Header Banner
        Container(
          padding: const EdgeInsets.all(16.0),
          decoration: BoxDecoration(
            color: isDark ? Colors.black.withValues(alpha: 0.18) : Colors.white.withValues(alpha: 0.38),
            borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
            border: Border(
              bottom: BorderSide(
                color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.white.withValues(alpha: 0.24),
                width: 1.2,
              ),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                getTranslation('education_title', locale),
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                getTranslation('education_subtitle', locale),
                style: TextStyle(fontSize: 11.5, color: theme.hintColor),
              ),
              const SizedBox(height: 16),
              // Search Input Field & Favorite Toggle
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      onChanged: (val) {
                        setState(() {
                          _searchQuery = val;
                        });
                      },
                      decoration: InputDecoration(
                        hintText: getTranslation('education_search_hint', locale),
                        hintStyle: const TextStyle(fontSize: 14),
                        prefixIcon: Icon(Icons.search, color: colorScheme.primary),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 20),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() {
                                    _searchQuery = "";
                                  });
                                },
                              )
                            : null,
                        filled: true,
                        fillColor: isDark ? const Color(0xFF262626) : const Color(0xFFF1F3F4),
                        contentPadding: const EdgeInsets.symmetric(vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilterChip(
                    avatar: Icon(
                      _showOnlyFavorites ? Icons.bookmark : Icons.bookmark_border,
                      size: 16,
                      color: _showOnlyFavorites ? Colors.amber : theme.hintColor,
                    ),
                    label: Text(
                      _showOnlyFavorites ? 'Saved' : 'All',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                    selected: _showOnlyFavorites,
                    onSelected: (bool selected) {
                      setState(() {
                        _showOnlyFavorites = selected;
                      });
                    },
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    showCheckmark: false,
                  ),
                ],
              ),
            ],
          ),
        ),

        // Diseases List
        Expanded(
          child: filteredDiseases.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.search_off_rounded, color: theme.hintColor, size: 48),
                      const SizedBox(height: 12),
                      Text(
                        getTranslation('no_matches_found', locale).replaceAll('{query}', _searchQuery),
                        style: TextStyle(color: theme.hintColor),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.only(left: 16, right: 16, top: 16, bottom: 120),
                  itemCount: filteredDiseases.length,
                  itemBuilder: (context, index) {
                    final disease = filteredDiseases[index];
                    final isFavorite = favorites.contains(disease.id);
                    final name = getTranslation('disease_${disease.id}', locale);
                    final category = getTranslation(disease.categoryKey, locale);
                    final symptoms = getTranslation('disease_${disease.id}_symptoms', locale);

                    return GlassCard(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: EdgeInsets.zero,
                      borderRadius: 16,
                      borderColor: disease.themeColor.withValues(alpha: 0.25),
                      onTap: () {
                        Navigator.of(context).push(MaterialPageRoute(
                          builder: (context) => DiseaseDetailScreen(disease: disease),
                        ));
                      },
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                            // Cover Image
                            Stack(
                              children: [
                                SizedBox(
                                  height: 140,
                                  width: double.infinity,
                                  child: Image.asset(
                                    disease.imageAssets[0],
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) {
                                      return Container(
                                        color: disease.themeColor.withValues(alpha: isDark ? 0.12 : 0.08),
                                        child: Center(
                                          child: Icon(
                                            Icons.local_florist_rounded,
                                            color: disease.themeColor,
                                            size: 48,
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                                // Bookmark Overlay Button
                                Positioned(
                                  top: 8,
                                  right: 8,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: Colors.black.withValues(alpha: 0.4),
                                      shape: BoxShape.circle,
                                    ),
                                    child: IconButton(
                                      icon: Icon(
                                        isFavorite ? Icons.bookmark : Icons.bookmark_border,
                                        color: isFavorite ? Colors.amber : Colors.white,
                                        size: 20,
                                      ),
                                      onPressed: () {
                                        ref.read(favoriteDiseasesProvider.notifier).toggleFavorite(disease.id);
                                      },
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            // Details Area
                            Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          name,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 17,
                                            letterSpacing: -0.3,
                                          ),
                                        ),
                                      ),
                                      // Severity indicator dot
                                      Container(
                                        width: 10,
                                        height: 10,
                                        decoration: BoxDecoration(
                                          color: disease.themeColor,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    category,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontStyle: FontStyle.italic,
                                      color: isDark ? Colors.grey[400] : Colors.grey[600],
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  // Symptoms Preview
                                  Text(
                                    symptoms,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      color: theme.hintColor,
                                      height: 1.35,
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        disease.scientificName,
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          fontStyle: FontStyle.italic,
                                          color: disease.themeColor,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      ElevatedButton.icon(
                                        style: ElevatedButton.styleFrom(
                                          elevation: 0,
                                          backgroundColor: disease.themeColor.withValues(alpha: 0.12),
                                          foregroundColor: disease.themeColor,
                                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                        ),
                                        icon: const Icon(Icons.arrow_forward, size: 14),
                                        label: Text(
                                          getTranslation('learn_more', locale),
                                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                        ),
                                        onPressed: () {
                                          Navigator.of(context).push(MaterialPageRoute(
                                            builder: (context) => DiseaseDetailScreen(disease: disease),
                                          ));
                                        },
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
