import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/disease.dart';
import '../../../core/services/localization_provider.dart';
import '../../../core/services/providers.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/widgets/glass_background.dart';

class DiseaseDetailScreen extends ConsumerStatefulWidget {
  final DiseaseInfo disease;

  const DiseaseDetailScreen({super.key, required this.disease});

  @override
  ConsumerState<DiseaseDetailScreen> createState() => _DiseaseDetailScreenState();
}

class _DiseaseDetailScreenState extends ConsumerState<DiseaseDetailScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final locale = ref.watch(localeProvider);
    final favorites = ref.watch(favoriteDiseasesProvider);
    final isFavorite = favorites.contains(widget.disease.id);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final name = getTranslation('disease_${widget.disease.id}', locale);
    final category = getTranslation(widget.disease.categoryKey, locale);
    final symptoms = getTranslation('disease_${widget.disease.id}_symptoms', locale);
    final severity = getTranslation('disease_${widget.disease.id}_severity', locale);
    final cultural = getTranslation('disease_${widget.disease.id}_mgmt_cultural', locale);
    final organic = getTranslation('disease_${widget.disease.id}_mgmt_organic', locale);
    final chemical = getTranslation('disease_${widget.disease.id}_mgmt_chemical', locale);
    final prevention = getTranslation('disease_${widget.disease.id}_mgmt_prevention', locale);

    // List of severity labels for custom fallback text on image placeholders
    final imageLabels = [
      getTranslation('low', locale),
      getTranslation('medium', locale),
      getTranslation('high', locale),
    ];

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: Container(
          margin: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.4),
            shape: BoxShape.circle,
          ),
          child: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        actions: [
          Container(
            margin: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.4),
              shape: BoxShape.circle,
            ),
            child: IconButton(
              icon: Icon(
                isFavorite ? Icons.bookmark : Icons.bookmark_border,
                color: isFavorite ? Colors.amber : Colors.white,
              ),
              onPressed: () {
                ref.read(favoriteDiseasesProvider.notifier).toggleFavorite(widget.disease.id);
              },
            ),
          ),
        ],
      ),
      body: GlassBackground(
        child: SingleChildScrollView(
          child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image Slideshow Carousel
            Stack(
              children: [
                SizedBox(
                  height: 280,
                  width: double.infinity,
                  child: PageView.builder(
                    controller: _pageController,
                    onPageChanged: (int page) {
                      setState(() {
                        _currentPage = page;
                      });
                    },
                    itemCount: widget.disease.imageAssets.length,
                    itemBuilder: (context, index) {
                      final assetPath = widget.disease.imageAssets[index];
                      final fallbackLabel = widget.disease.id == 'Healthy'
                          ? '${getTranslation('healthy', locale)} #${index + 1}'
                          : '${getTranslation('disease_${widget.disease.id}', locale)} (${imageLabels[index]})';
                      return Image.asset(
                        assetPath,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            color: widget.disease.themeColor.withValues(alpha: isDark ? 0.12 : 0.08),
                            child: Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.image_not_supported_outlined,
                                    color: widget.disease.themeColor,
                                    size: 48,
                                  ),
                                  const SizedBox(height: 8),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 20),
                                    child: Text(
                                      fallbackLabel,
                                      style: TextStyle(
                                        color: widget.disease.themeColor,
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
                // Page Indicator Dot Overlay
                if (widget.disease.imageAssets.length > 1)
                  Positioned(
                    bottom: 16,
                    left: 0,
                    right: 0,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(
                        widget.disease.imageAssets.length,
                        (index) => AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          height: 8,
                          width: _currentPage == index ? 24 : 8,
                          decoration: BoxDecoration(
                            color: _currentPage == index
                                ? widget.disease.themeColor
                                : Colors.white.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),

            // Content Area
            Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Disease Header (Name & Science Name)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                letterSpacing: -0.5,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              widget.disease.scientificName,
                              style: TextStyle(
                                fontSize: 14,
                                fontStyle: FontStyle.italic,
                                color: widget.disease.themeColor,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Favorite Badge Indicator
                      if (isFavorite)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.amber.withValues(alpha: isDark ? 0.15 : 0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.bookmark, color: Colors.amber, size: 14),
                              const SizedBox(width: 4),
                              Text(
                                getTranslation('learn_more', locale), // Or "Saved"
                                style: const TextStyle(fontSize: 11, color: Colors.amber, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Category & Severity Indicator Row
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      // Category Chip
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          category,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      // Severity Badges (Colored indicators)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: widget.disease.themeColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: widget.disease.themeColor.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: widget.disease.themeColor,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '${getTranslation('severity_levels_label', locale)}: $severity',
                              style: TextStyle(
                                fontSize: 11.5,
                                color: isDark ? Colors.grey[200] : Colors.grey[800],
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 32),

                  // Symptoms Section
                  Text(
                    getTranslation('symptoms_label', locale),
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  GlassCard(
                    borderRadius: 16,
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                          Icon(Icons.visibility_outlined, color: widget.disease.themeColor, size: 24),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              symptoms,
                              style: const TextStyle(fontSize: 13.5, height: 1.45),
                            ),
                          ),
                        ],
                      ),
                  ),
                  const SizedBox(height: 24),

                  // Management & Control Header
                  Text(
                    getTranslation('management_header', locale),
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),

                  // Cultural Practices Card
                  _buildManagementCard(
                    getTranslation('management_cultural', locale),
                    cultural,
                    Icons.agriculture_rounded,
                    widget.disease.themeColor,
                    isDark,
                    theme,
                  ),
                  const SizedBox(height: 12),

                  // Organic Methods Card
                  _buildManagementCard(
                    getTranslation('management_organic', locale),
                    organic,
                    Icons.eco_rounded,
                    Colors.green,
                    isDark,
                    theme,
                  ),
                  const SizedBox(height: 12),

                  // Chemical Methods Card
                  _buildManagementCard(
                    getTranslation('management_chemical', locale),
                    chemical,
                    Icons.science_rounded,
                    Colors.blueAccent,
                    isDark,
                    theme,
                  ),
                  const SizedBox(height: 12),

                  // Prevention Card
                  _buildManagementCard(
                    getTranslation('management_prevention', locale),
                    prevention,
                    Icons.shield_outlined,
                    Colors.orangeAccent,
                    isDark,
                    theme,
                  ),

                  const Divider(height: 48),

                  // Source Footer
                  Center(
                    child: Text(
                      getTranslation('source_label', locale).replaceAll('{source}', widget.disease.source),
                      style: TextStyle(
                        fontSize: 11,
                        fontStyle: FontStyle.italic,
                        color: theme.hintColor,
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
    );
  }

  Widget _buildManagementCard(
    String title,
    String content,
    IconData icon,
    Color iconColor,
    bool isDark,
    ThemeData theme,
  ) {
    return GlassCard(
      borderRadius: 16,
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
            Row(
              children: [
                Icon(icon, color: iconColor, size: 22),
                const SizedBox(width: 10),
                Text(
                  title,
                  style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.only(left: 4.0),
              child: Text(
                content,
                style: const TextStyle(fontSize: 13, height: 1.45),
              ),
            ),
          ],
        ),
    );
  }
}
