import 'dart:io';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:flutter/foundation.dart';
import '../models/scan_model.dart';

class PdfService {
  PdfService();

  Future<void> generateAndPrintReport({
    required ScanModel scan,
    required String scientificName,
    required String description,
    required List<String> recommendations,
  }) async {
    try {
      final doc = pw.Document();

      // Read images
      final File originalFile = File(scan.originalImagePath);
      final File overlayFile = File(scan.overlayImagePath);

      pw.ImageProvider? originalImage;
      pw.ImageProvider? overlayImage;

      if (await originalFile.exists()) {
        originalImage = pw.MemoryImage(await originalFile.readAsBytes());
      }
      if (await overlayFile.exists()) {
        overlayImage = pw.MemoryImage(await overlayFile.readAsBytes());
      }

      // Format Date
      final String formattedDate = DateFormat('yyyy-MM-dd HH:mm:ss').format(scan.createdAt);

      doc.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(32),
          build: (pw.Context context) {
            return [
              // Header Banner
              pw.Container(
                decoration: const pw.BoxDecoration(
                  border: pw.Border(bottom: pw.BorderSide(color: PdfColors.green, width: 2)),
                ),
                padding: const pw.EdgeInsets.only(bottom: 8),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          'MOKOGUARD AI',
                          style: pw.TextStyle(
                            fontSize: 24,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.green800,
                          ),
                        ),
                        pw.Text(
                          'Offline Explainable Banana Disease Diagnosis',
                          style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
                        ),
                      ],
                    ),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Text('Report Date: $formattedDate', style: const pw.TextStyle(fontSize: 9)),
                        pw.Text('Diagnostic ID: #${scan.id ?? "TEMP"}', style: const pw.TextStyle(fontSize: 9)),
                      ],
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 20),

              // Summary Section
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Expanded(
                    flex: 3,
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          'Diagnosis Summary',
                          style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColors.green900),
                        ),
                        pw.SizedBox(height: 8),
                        _buildRow('Condition:', scan.diseaseName.replaceAll('_', ' '), isBoldValue: true),
                        _buildRow('Scientific Name:', scientificName),
                        _buildRow('Confidence Score:', '${scan.confidence.toStringAsFixed(2)}%'),
                        _buildRow('Severity Level:', scan.severity, isColoredSeverity: true),
                        _buildRow('Inference Latency:', '${scan.inferenceTimeMs} ms'),
                      ],
                    ),
                  ),
                  pw.SizedBox(width: 20),
                  pw.Expanded(
                    flex: 2,
                    child: pw.Container(
                      padding: const pw.EdgeInsets.all(10),
                      decoration: const pw.BoxDecoration(
                        color: PdfColors.grey100,
                        borderRadius: pw.BorderRadius.all(pw.Radius.circular(8)),
                      ),
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            'AI Interpretation',
                            style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
                          ),
                          pw.SizedBox(height: 4),
                          pw.Text(
                            description,
                            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey800),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 24),

              // Visual Analysis Section (Images)
              pw.Text(
                'Visual Explainability Analysis (Grad-CAM)',
                style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColors.green900),
              ),
              pw.SizedBox(height: 10),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
                children: [
                  if (originalImage != null)
                    pw.Column(
                      children: [
                        pw.Container(
                          width: 200,
                          height: 200,
                          decoration: pw.BoxDecoration(
                            border: pw.Border.all(color: PdfColors.grey300),
                          ),
                          child: pw.Image(originalImage, fit: pw.BoxFit.cover),
                        ),
                        pw.SizedBox(height: 4),
                        pw.Text('Original Leaf Photo', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
                      ],
                    ),
                  if (overlayImage != null)
                    pw.Column(
                      children: [
                        pw.Container(
                          width: 200,
                          height: 200,
                          decoration: pw.BoxDecoration(
                            border: pw.Border.all(color: PdfColors.grey300),
                          ),
                          child: pw.Image(overlayImage, fit: pw.BoxFit.cover),
                        ),
                        pw.SizedBox(height: 4),
                        pw.Text('Explainable AI Highlight (Red = Disease Focus)',
                            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
                      ],
                    ),
                ],
              ),
              pw.SizedBox(height: 24),

              // Recommendations Section
              pw.Text(
                'Recommended Treatment & Preventative Measures',
                style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColors.green900),
              ),
              pw.SizedBox(height: 8),
              if (recommendations.isEmpty)
                pw.Text('No specific actions required. Maintain standard agricultural hygiene.',
                    style: const pw.TextStyle(fontSize: 10))
              else
                ...recommendations.map((rec) => pw.Padding(
                      padding: const pw.EdgeInsets.symmetric(vertical: 2.0),
                      child: pw.Row(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text('• ', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                          pw.Expanded(
                            child: pw.Text(rec, style: const pw.TextStyle(fontSize: 10)),
                          ),
                        ],
                      ),
                    )),
              pw.SizedBox(height: 30),

              // Footer Disclaimer
              pw.Container(
                alignment: pw.Alignment.center,
                padding: const pw.EdgeInsets.only(top: 8),
                decoration: const pw.BoxDecoration(
                  border: pw.Border(top: pw.BorderSide(color: PdfColors.grey300, width: 0.5)),
                ),
                child: pw.Text(
                  'Disclaimer: This analysis is computer-generated by an offline deep learning model and is intended for research and guiding diagnostics. Always verify with field inspectors.',
                  style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600),
                  textAlign: pw.TextAlign.center,
                ),
              ),
            ];
          },
        ),
      );

      // Trigger print or save as PDF flow using the printing package
      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => doc.save(),
        name: 'MokoGuard_Report_${scan.id ?? "TEMP"}.pdf',
      );
    } catch (e) {
      debugPrint("Error generating PDF Report: $e");
      rethrow;
    }
  }

  Future<void> generateAndPrintTreeReport({
    required File parentImage,
    required List<ScanModel> scans,
    required String aggDisease,
    required String aggScientificName,
    required double aggConfidence,
    required String aggSeverity,
    required String aggDescription,
    required List<String> aggRecommendations,
  }) async {
    try {
      final doc = pw.Document();

      pw.ImageProvider? parentImageProvider;
      if (await parentImage.exists()) {
        parentImageProvider = pw.MemoryImage(await parentImage.readAsBytes());
      }

      // Read each leaf crop overlay image
      final List<pw.ImageProvider?> leafOverlayProviders = [];
      for (var scan in scans) {
        final File file = File(scan.overlayImagePath);
        if (await file.exists()) {
          leafOverlayProviders.add(pw.MemoryImage(await file.readAsBytes()));
        } else {
          leafOverlayProviders.add(null);
        }
      }

      final String formattedDate = DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());

      doc.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(32),
          build: (pw.Context context) {
            return [
              // Header Banner
              pw.Container(
                decoration: const pw.BoxDecoration(
                  border: pw.Border(bottom: pw.BorderSide(color: PdfColors.green, width: 2)),
                ),
                padding: const pw.EdgeInsets.only(bottom: 8),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          'MOKOGUARD AI - TREE REPORT',
                          style: pw.TextStyle(
                            fontSize: 22,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.green800,
                          ),
                        ),
                        pw.Text(
                          'Offline Aggregated Multi-Leaf Diagnosis',
                          style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
                        ),
                      ],
                    ),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Text('Report Date: $formattedDate', style: const pw.TextStyle(fontSize: 9)),
                        pw.Text('Leaves Processed: ${scans.length}', style: const pw.TextStyle(fontSize: 9)),
                      ],
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 16),

              // Aggregated Tree Diagnosis Summary
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Expanded(
                    flex: 3,
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          'Aggregated Diagnosis',
                          style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: PdfColors.green900),
                        ),
                        pw.SizedBox(height: 6),
                        _buildRow('Condition:', aggDisease.replaceAll('_', ' '), isBoldValue: true),
                        _buildRow('Scientific Name:', aggScientificName),
                        _buildRow('Mean Confidence:', '${aggConfidence.toStringAsFixed(2)}%'),
                        _buildRow('Overall Severity:', aggSeverity, isColoredSeverity: true),
                      ],
                    ),
                  ),
                  pw.SizedBox(width: 16),
                  if (parentImageProvider != null)
                    pw.Container(
                      width: 110,
                      height: 110,
                      decoration: pw.BoxDecoration(
                        border: pw.Border.all(color: PdfColors.grey300),
                      ),
                      child: pw.Image(parentImageProvider, fit: pw.BoxFit.cover),
                    ),
                ],
              ),
              pw.SizedBox(height: 16),
              
              pw.Text(
                'AI Analysis Interpretation:',
                style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 2),
              pw.Text(
                aggDescription,
                style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey800),
              ),
              pw.SizedBox(height: 20),

              // Individual Leaf Crop Analysis
              pw.Text(
                'Individual Leaf Segment Diagnostics',
                style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: PdfColors.green900),
              ),
              pw.SizedBox(height: 8),

              pw.Table(
                border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
                columnWidths: {
                  0: const pw.FixedColumnWidth(80),
                  1: const pw.FlexColumnWidth(),
                  2: const pw.FixedColumnWidth(80),
                  3: const pw.FixedColumnWidth(80),
                },
                children: [
                  // Table Header
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: PdfColors.grey100),
                    children: [
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(6),
                        child: pw.Text('Visual Focus', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(6),
                        child: pw.Text('Leaf Segment', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(6),
                        child: pw.Text('Confidence', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(6),
                        child: pw.Text('Severity', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
                      ),
                    ],
                  ),
                  // Table Rows
                  ...List.generate(scans.length, (idx) {
                    final scan = scans[idx];
                    final imageProv = leafOverlayProviders[idx];
                    return pw.TableRow(
                      children: [
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(4),
                          child: imageProv != null
                              ? pw.Container(
                                  width: 60,
                                  height: 60,
                                  child: pw.Image(imageProv, fit: pw.BoxFit.cover),
                                )
                              : pw.Text('No Image', style: const pw.TextStyle(fontSize: 8)),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(6),
                          child: pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            children: [
                              pw.Text('Leaf Crop ${idx + 1}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
                              pw.SizedBox(height: 2),
                              pw.Text(scan.diseaseName.replaceAll('_', ' '), style: const pw.TextStyle(fontSize: 8)),
                            ],
                          ),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(6),
                          child: pw.Text('${scan.confidence.toStringAsFixed(1)}%', style: const pw.TextStyle(fontSize: 9)),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(6),
                          child: pw.Text(
                            scan.severity,
                            style: pw.TextStyle(
                              fontWeight: pw.FontWeight.bold,
                              fontSize: 9,
                              color: scan.severity.toLowerCase() == 'high'
                                  ? PdfColors.red800
                                  : (scan.severity.toLowerCase() == 'medium' ? PdfColors.orange800 : PdfColors.green800),
                            ),
                          ),
                        ),
                      ],
                    );
                  }),
                ],
              ),
              pw.SizedBox(height: 20),

              // Aggregated Recommendations
              pw.Text(
                'Tree-Level Prescriptions & Measures',
                style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: PdfColors.green900),
              ),
              pw.SizedBox(height: 6),
              if (aggRecommendations.isEmpty)
                pw.Text('No specific actions required. Maintain standard agricultural hygiene.',
                    style: const pw.TextStyle(fontSize: 9))
              else
                ...aggRecommendations.map((rec) => pw.Padding(
                      padding: const pw.EdgeInsets.symmetric(vertical: 2.0),
                      child: pw.Row(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text('• ', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
                          pw.Expanded(
                            child: pw.Text(rec, style: const pw.TextStyle(fontSize: 9)),
                          ),
                        ],
                      ),
                    )),
              pw.SizedBox(height: 20),

              // Footer Disclaimer
              pw.Container(
                alignment: pw.Alignment.center,
                padding: const pw.EdgeInsets.only(top: 8),
                decoration: const pw.BoxDecoration(
                  border: pw.Border(top: pw.BorderSide(color: PdfColors.grey300, width: 0.5)),
                ),
                child: pw.Text(
                  'Disclaimer: Aggregated diagnostics are computer-generated by local offline machine learning. Always consult professional phytosanitary inspectors.',
                  style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600),
                  textAlign: pw.TextAlign.center,
                ),
              ),
            ];
          },
        ),
      );

      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => doc.save(),
        name: 'MokoGuard_TreeAggregated_Report_${DateTime.now().millisecondsSinceEpoch}.pdf',
      );
    } catch (e) {
      debugPrint("Error generating Aggregated PDF Report: $e");
      rethrow;
    }
  }

  pw.Widget _buildRow(String label, String value, {bool isBoldValue = false, bool isColoredSeverity = false}) {
    PdfColor valColor = PdfColors.black;
    if (isColoredSeverity) {
      if (value.toLowerCase() == 'high') {
        valColor = PdfColors.red800;
      } else if (value.toLowerCase() == 'medium') {
        valColor = PdfColors.orange800;
      } else if (value.toLowerCase() == 'low' || value.toLowerCase() == 'healthy') {
        valColor = PdfColors.green800;
      }
    }

    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 3.0),
      child: pw.Row(
        children: [
          pw.SizedBox(
            width: 100,
            child: pw.Text(
              label,
              style: pw.TextStyle(fontSize: 10, color: PdfColors.grey800, fontWeight: pw.FontWeight.bold),
            ),
          ),
          pw.Text(
            value,
            style: pw.TextStyle(
              fontSize: 10,
              fontWeight: (isBoldValue || isColoredSeverity) ? pw.FontWeight.bold : pw.FontWeight.normal,
              color: valColor,
            ),
          ),
        ],
      ),
    );
  }
}
