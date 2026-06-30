import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import '../../../core/services/providers.dart';
import '../../../core/services/localization_provider.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/widgets/glass_switch.dart';
import '../../../core/widgets/glass_segmented_control.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  Future<void> _exportData(BuildContext context, WidgetRef ref) async {
    try {
      final scansAsync = ref.read(historyProvider);
      final scans = scansAsync.value ?? [];
      
      if (scans.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No diagnostics recorded yet to export.'),
            backgroundColor: Colors.orangeAccent,
          ),
        );
        return;
      }

      // Convert to Map list
      final dataList = scans.map((s) {
        return {
          'id': s.id,
          'diseaseName': s.diseaseName,
          'confidence': s.confidence,
          'severity': s.severity,
          'inferenceTimeMs': s.inferenceTimeMs,
          'createdAt': s.createdAt.toIso8601String(),
          'originalImagePath': s.originalImagePath,
          'overlayImagePath': s.overlayImagePath,
        };
      }).toList();

      final jsonString = const JsonEncoder.withIndent('  ').convert(dataList);

      // Save file to documents directory
      final Directory docDir = await getApplicationDocumentsDirectory();
      final String filePath = '${docDir.path}/mokoguard_diagnostics_export.json';
      final File file = File(filePath);
      await file.writeAsString(jsonString);

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Successfully exported to:\n$filePath'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Export failed: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  Future<void> _exportFeedbackData(BuildContext context, WidgetRef ref, String format) async {
    try {
      final service = ref.read(feedbackServiceProvider);
      final logs = await service.getAllFeedback();
      if (!context.mounted) return;
      if (logs.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No feedback logs recorded yet to export.'),
            backgroundColor: Colors.orangeAccent,
          ),
        );
        return;
      }

      String filePath;
      if (format.toLowerCase() == 'csv') {
        filePath = await service.exportFeedbackAsCsv();
      } else {
        filePath = await service.exportFeedbackAsJson();
      }

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Successfully exported feedback ($format) to:\n$filePath'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Export failed: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  void _confirmClearData(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.redAccent),
              SizedBox(width: 8),
              Text('Clear Diagnostic Data?', style: TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          content: const Text(
            'This will permanently delete all local banana disease diagnosis records, including stored analysis parameters. The source models themselves will not be affected. This action cannot be undone.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                ref.read(historyProvider.notifier).clearAll();
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('All local diagnostic records successfully deleted.'),
                    backgroundColor: Colors.green,
                  ),
                );
              },
              child: const Text('Clear All', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final themeMode = ref.watch(themeModeProvider);
    final researchMode = ref.watch(researchModeProvider);
    final modelVersion = ref.watch(modelVersionProvider);
    final locale = ref.watch(localeProvider);

    return Column(
      children: [
        // Top Header
        Container(
          width: double.infinity,
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
                getTranslation('settings_title', locale),
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                getTranslation('settings_subtitle', locale),
                style: TextStyle(fontSize: 11.5, color: theme.hintColor),
              ),
            ],
          ),
        ),

        // Settings items list
        Expanded(
          child: ListView(
            padding: const EdgeInsets.only(left: 16.0, right: 16.0, top: 16.0, bottom: 120.0),
            children: [
              // 1. Theme & Language Configuration
              _buildSectionHeader(getTranslation('appearance_header', locale), theme),
              GlassCard(
                borderRadius: 16.0,
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    ListTile(
                      leading: Icon(
                        themeMode == ThemeMode.dark ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
                        color: colorScheme.primary,
                      ),
                      title: Text(getTranslation('theme_settings', locale), style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
                      subtitle: Text(
                        themeMode == ThemeMode.dark ? getTranslation('theme_dark', locale) : getTranslation('theme_light', locale),
                        style: TextStyle(fontSize: 11.5, color: theme.hintColor),
                      ),
                      trailing: GlassSwitch(
                        value: themeMode == ThemeMode.dark,
                        onChanged: (val) {
                          ref.read(themeModeProvider.notifier).toggleTheme();
                        },
                      ),
                    ),
                    const Divider(height: 1, indent: 56),
                    ListTile(
                      leading: Icon(
                        Icons.translate_rounded,
                        color: colorScheme.primary,
                      ),
                      title: Text(getTranslation('language_settings', locale), style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
                      subtitle: Text(
                        languageNames[locale] ?? 'English',
                        style: TextStyle(fontSize: 11.5, color: theme.hintColor),
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded, color: Colors.grey, size: 20),
                      onTap: () => _showLanguagePicker(context, ref, locale),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // 2. Scientific & Model Updates Configuration
              _buildSectionHeader(getTranslation('ai_research_header', locale), theme),
              GlassCard(
                borderRadius: 16.0,
                padding: const EdgeInsets.only(bottom: 12.0),
                child: Column(
                  children: [
                    // Model Version Select
                    ListTile(
                      leading: Icon(Icons.psychology_rounded, color: colorScheme.primary),
                      title: Text(getTranslation('model_version_title', locale), style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
                      subtitle: Text(
                        getTranslation('model_version_desc', locale),
                        style: TextStyle(fontSize: 11.5, color: theme.hintColor),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
                      child: GlassSegmentedControl(
                        options: const ['MobileNetV2 (Float32)', 'MobileNetV2 (Int8 Quant)'],
                        selectedIndex: modelVersion == 'MobileNetV2-Banana-Float32' ? 0 : 1,
                        onValueChanged: (index) {
                          ref.read(modelVersionProvider.notifier).state = index == 0
                              ? 'MobileNetV2-Banana-Float32'
                              : 'MobileNetV2-Quantized-Int8';
                        },
                      ),
                    ),
                    const Divider(height: 24, indent: 56),
                    
                    // Research Mode Toggle
                    ListTile(
                      leading: Icon(Icons.analytics_outlined, color: colorScheme.primary),
                      title: Text(getTranslation('research_mode_title', locale), style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
                      subtitle: Text(
                        getTranslation('research_mode_desc', locale),
                        style: TextStyle(fontSize: 11.5, color: theme.hintColor),
                      ),
                      trailing: GlassSwitch(
                        value: researchMode,
                        onChanged: (val) {
                          ref.read(researchModeProvider.notifier).state = val;
                        },
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // 2.5 Image Quality & Enhancement Configuration
              _buildSectionHeader(getTranslation('image_quality_header', locale), theme),
              GlassCard(
                borderRadius: 16.0,
                padding: const EdgeInsets.only(bottom: 12.0),
                child: Column(
                  children: [
                    // Auto Enhancement Toggle
                    ListTile(
                      leading: Icon(Icons.wb_sunny_rounded, color: colorScheme.primary),
                      title: Text(getTranslation('low_light_enhancement_title', locale), style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
                      subtitle: Text(
                        getTranslation('low_light_enhancement_desc', locale),
                        style: TextStyle(fontSize: 11.5, color: theme.hintColor),
                      ),
                      trailing: GlassSwitch(
                        value: ref.watch(imageEnhancementEnabledProvider),
                        onChanged: (val) {
                          ref.read(imageEnhancementEnabledProvider.notifier).state = val;
                        },
                      ),
                    ),
                    const Divider(height: 24, indent: 56),

                    // Enhancement Strength
                    ListTile(
                      leading: Icon(Icons.tune_rounded, color: colorScheme.primary),
                      title: Text(getTranslation('enhancement_strength_title', locale), style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
                      subtitle: Text(
                        getTranslation('enhancement_strength_desc', locale),
                        style: TextStyle(fontSize: 11.5, color: theme.hintColor),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
                      child: Opacity(
                        opacity: ref.watch(imageEnhancementEnabledProvider) ? 1.0 : 0.45,
                        child: AbsorbPointer(
                          absorbing: !ref.watch(imageEnhancementEnabledProvider),
                          child: GlassSegmentedControl(
                            options: const ['Light', 'Medium', 'Strong'],
                            selectedIndex: const ['Light', 'Medium', 'Strong'].indexOf(ref.watch(imageEnhancementStrengthProvider)),
                            onValueChanged: (index) {
                              ref.read(imageEnhancementStrengthProvider.notifier).state = const ['Light', 'Medium', 'Strong'][index];
                            },
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // 3. Data management & portability
              _buildSectionHeader(getTranslation('local_data_header', locale), theme),
              GlassCard(
                borderRadius: 16.0,
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    // Export records
                    ListTile(
                      leading: Icon(Icons.import_export_rounded, color: colorScheme.primary),
                      title: Text(getTranslation('export_history_title', locale), style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
                      subtitle: Text(
                        getTranslation('export_history_desc', locale),
                        style: TextStyle(fontSize: 11.5, color: theme.hintColor),
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded, color: Colors.grey, size: 20),
                      onTap: () => _exportData(context, ref),
                    ),
                    const Divider(height: 1, indent: 56),

                    // Export feedback (JSON)
                    ListTile(
                      leading: Icon(Icons.rate_review_rounded, color: colorScheme.primary),
                      title: Text(getTranslation('export_feedback_json_title', locale), style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
                      subtitle: Text(
                        getTranslation('export_feedback_json_desc', locale),
                        style: TextStyle(fontSize: 11.5, color: theme.hintColor),
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded, color: Colors.grey, size: 20),
                      onTap: () => _exportFeedbackData(context, ref, 'JSON'),
                    ),
                    const Divider(height: 1, indent: 56),

                    // Export feedback (CSV)
                    ListTile(
                      leading: Icon(Icons.grid_on_rounded, color: colorScheme.primary),
                      title: Text(getTranslation('export_feedback_csv_title', locale), style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
                      subtitle: Text(
                        getTranslation('export_feedback_csv_desc', locale),
                        style: TextStyle(fontSize: 11.5, color: theme.hintColor),
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded, color: Colors.grey, size: 20),
                      onTap: () => _exportFeedbackData(context, ref, 'CSV'),
                    ),
                    const Divider(height: 1, indent: 56),

                    // Clear database
                    ListTile(
                      leading: const Icon(Icons.delete_sweep_rounded, color: Colors.redAccent),
                      title: Text(getTranslation('clear_data_title', locale), style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: Colors.redAccent)),
                      subtitle: Text(
                        getTranslation('clear_data_desc', locale),
                        style: TextStyle(fontSize: 11.5, color: theme.hintColor),
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded, color: Colors.redAccent, size: 20),
                      onTap: () => _confirmClearData(context, ref),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // App Version Branding Footer
              Center(
                child: Column(
                  children: [
                    Text(
                      'MokoGuard AI',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: theme.hintColor.withValues(alpha: 0.8),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'v1.2.0 • Offline Edge AI Architecture',
                      style: TextStyle(
                        fontSize: 10,
                        color: theme.hintColor.withValues(alpha: 0.5),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _showLanguagePicker(BuildContext context, WidgetRef ref, String currentLocale) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (context) {
        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20.0, sigmaY: 20.0),
            child: Container(
              padding: const EdgeInsets.all(24.0),
              decoration: BoxDecoration(
                color: isDark ? Colors.black.withValues(alpha: 0.6) : Colors.white.withValues(alpha: 0.6),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                border: Border(
                  top: BorderSide(
                    color: isDark ? Colors.white.withValues(alpha: 0.12) : Colors.black.withValues(alpha: 0.08),
                    width: 1.5,
                  ),
                ),
              ),
              child: SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 36,
                      height: 5,
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white.withValues(alpha: 0.2) : Colors.black.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      getTranslation('language_settings', currentLocale),
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),
                    Flexible(
                      child: GridView.count(
                        crossAxisCount: 2,
                        shrinkWrap: true,
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 12,
                        childAspectRatio: 1.85,
                        children: languageNames.entries.map((entry) {
                          final code = entry.key;
                          final name = entry.value;
                          final isSelected = code == currentLocale;

                          return GestureDetector(
                            onTap: () {
                              ref.read(localeProvider.notifier).setLocale(code);
                              Navigator.pop(context);
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? theme.primaryColor.withValues(alpha: 0.15)
                                    : (isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.03)),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: isSelected
                                      ? theme.primaryColor
                                      : (isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.06)),
                                  width: isSelected ? 1.8 : 1.0,
                                ),
                                boxShadow: isSelected
                                    ? [
                                        BoxShadow(
                                          color: theme.primaryColor.withValues(alpha: 0.15),
                                          blurRadius: 8,
                                          spreadRadius: 1,
                                        )
                                      ]
                                    : [],
                              ),
                              padding: const EdgeInsets.all(12),
                              child: Stack(
                                children: [
                                  Center(
                                    child: Text(
                                      name,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                        color: isSelected ? theme.primaryColor : (isDark ? Colors.white : Colors.black),
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                  if (isSelected)
                                    Positioned(
                                      top: 0,
                                      right: 0,
                                      child: Icon(
                                        Icons.check_circle_rounded,
                                        color: theme.primaryColor,
                                        size: 16,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSectionHeader(String title, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(left: 4.0, bottom: 8.0, top: 10.0),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 12,
            decoration: BoxDecoration(
              color: theme.primaryColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            title.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w900,
              color: theme.primaryColor,
              letterSpacing: 1.0,
            ),
          ),
        ],
      ),
    );
  }
}
