import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../../core/models/scan_model.dart';
import '../../../core/models/feedback_model.dart';
import '../../../core/services/providers.dart';
import '../../../core/services/localization_provider.dart';

class FeedbackWidget extends ConsumerStatefulWidget {
  final ScanModel scan;

  const FeedbackWidget({
    super.key,
    required this.scan,
  });

  @override
  ConsumerState<FeedbackWidget> createState() => _FeedbackWidgetState();
}

class _FeedbackWidgetState extends ConsumerState<FeedbackWidget> {
  bool? _isPositive; // null = unselected, true = thumbs up, false = thumbs down
  bool _submitted = false;
  
  String? _correctedDisease;
  String? _correctedSeverity;

  final List<String> _diseases = [
    'Black_Sigatoka',
    'Cordana',
    'Healthy',
    'Panama_Disease',
    'Pestalotiopsis',
    'Yellow_Sigatoka',
    'Moko',
  ];

  final List<String> _severities = ['Low', 'Medium', 'High'];

  @override
  void initState() {
    super.initState();
    // Default corrected values to current scan predictions
    _correctedDisease = widget.scan.diseaseName;
    _correctedSeverity = widget.scan.severity;
  }

  Future<void> _submitPositiveFeedback() async {
    setState(() {
      _isPositive = true;
      _submitted = true;
    });

    final feedback = FeedbackModel(
      id: const Uuid().v4(),
      scanId: widget.scan.id ?? 0,
      originalDisease: widget.scan.diseaseName,
      originalSeverity: widget.scan.severity,
      userDisease: null,
      userSeverity: null,
      confidence: widget.scan.confidence,
      feedbackType: 'positive',
      createdAt: DateTime.now(),
    );

    try {
      await ref.read(feedbackHistoryProvider.notifier).addFeedback(feedback);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save feedback: $e')),
        );
      }
    }
  }

  Future<void> _submitNegativeFeedback() async {
    setState(() {
      _submitted = true;
    });

    final feedback = FeedbackModel(
      id: const Uuid().v4(),
      scanId: widget.scan.id ?? 0,
      originalDisease: widget.scan.diseaseName,
      originalSeverity: widget.scan.severity,
      userDisease: _correctedDisease,
      userSeverity: _correctedSeverity,
      confidence: widget.scan.confidence,
      feedbackType: 'negative',
      createdAt: DateTime.now(),
    );

    try {
      await ref.read(feedbackHistoryProvider.notifier).addFeedback(feedback);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save correction: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final locale = ref.watch(localeProvider);
    final isDark = theme.brightness == Brightness.dark;

    if (_submitted) {
      return Card(
        color: isDark ? const Color(0xFF1E2822) : const Color(0xFFE8F5E9),
        elevation: 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              const Icon(Icons.check_circle_rounded, color: Colors.green, size: 28),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      getTranslation('feedback_thanks', locale),
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      getTranslation('feedback_privacy', locale),
                      style: TextStyle(fontSize: 10.5, color: theme.hintColor),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Question Row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    getTranslation('feedback_prompt', locale),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5),
                  ),
                ),
                Row(
                  children: [
                    // Thumbs Up
                    IconButton(
                      icon: Icon(
                        _isPositive == true ? Icons.thumb_up_rounded : Icons.thumb_up_outlined,
                        color: _isPositive == true ? Colors.green : theme.hintColor,
                      ),
                      onPressed: _submitPositiveFeedback,
                      tooltip: 'Correct',
                    ),
                    // Thumbs Down
                    IconButton(
                      icon: Icon(
                        _isPositive == false ? Icons.thumb_down_rounded : Icons.thumb_down_outlined,
                        color: _isPositive == false ? Colors.redAccent : theme.hintColor,
                      ),
                      onPressed: () {
                        setState(() {
                          _isPositive = false;
                        });
                      },
                      tooltip: 'Incorrect',
                    ),
                  ],
                ),
              ],
            ),

            // Negative Feedback / Correction Form
            if (_isPositive == false) ...[
              const Divider(height: 20),
              Text(
                getTranslation('feedback_improve', locale),
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: theme.hintColor),
              ),
              const SizedBox(height: 12),
              
              // Corrected Disease Class Dropdown
              DropdownButtonFormField<String>(
                initialValue: _correctedDisease,
                decoration: InputDecoration(
                  labelText: getTranslation('feedback_correct', locale),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                items: _diseases.map((d) {
                  return DropdownMenuItem(
                    value: d,
                    child: Text(getTranslation('disease_$d', locale), style: const TextStyle(fontSize: 13.5)),
                  );
                }).toList(),
                onChanged: (val) {
                  setState(() {
                    _correctedDisease = val;
                  });
                },
              ),
              const SizedBox(height: 12),

              // Corrected Severity Dropdown
              DropdownButtonFormField<String>(
                initialValue: _correctedSeverity,
                decoration: InputDecoration(
                  labelText: getTranslation('feedback_severity', locale),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                items: _severities.map((s) {
                  return DropdownMenuItem(
                    value: s,
                    child: Text(getTranslation('severity_$s', locale), style: const TextStyle(fontSize: 13.5)),
                  );
                }).toList(),
                onChanged: (val) {
                  setState(() {
                    _correctedSeverity = val;
                  });
                },
              ),
              const SizedBox(height: 16),

              // Submit Button
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.colorScheme.primary,
                  foregroundColor: theme.colorScheme.onPrimary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                onPressed: _submitNegativeFeedback,
                child: Text(
                  getTranslation('feedback_submit', locale),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
            
            const SizedBox(height: 8),
            // Privacy Note
            Text(
              getTranslation('feedback_privacy', locale),
              style: TextStyle(fontSize: 9.5, color: theme.hintColor, fontStyle: FontStyle.italic),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
