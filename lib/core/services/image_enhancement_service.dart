import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class EnhancementResult {
  final File enhancedFile;
  final bool wasEnhanced;
  final double originalBrightness;
  final double originalContrast;
  final double enhancedBrightness;
  final double enhancedContrast;

  EnhancementResult({
    required this.enhancedFile,
    required this.wasEnhanced,
    required this.originalBrightness,
    required this.originalContrast,
    required this.enhancedBrightness,
    required this.enhancedContrast,
  });
}

class ImageEnhancementService {
  ImageEnhancementService();

  /// Analyzes image brightness (luminance) and contrast (std dev).
  /// Brightness threshold: < 0.35 is considered low-light.
  Future<Map<String, double>> analyzeImageQuality(File imageFile) async {
    try {
      final bytes = await imageFile.readAsBytes();
      
      // Load and downscale to 224x224 for analysis
      final codec = await ui.instantiateImageCodec(bytes, targetWidth: 224, targetHeight: 224);
      final frame = await codec.getNextFrame();
      final uiImage = frame.image;
      
      final byteData = await uiImage.toByteData(format: ui.ImageByteFormat.rawRgba);
      uiImage.dispose();
      
      if (byteData == null) {
        return {'brightness': 0.5, 'contrast': 0.5};
      }
      
      final Uint8List rgbaBytes = byteData.buffer.asUint8List();
      const int numPixels = 224 * 224;
      double totalLuminance = 0.0;
      final intensities = Float32List(numPixels);
      
      for (int i = 0; i < numPixels; i++) {
        final int offset = i * 4;
        final int r = rgbaBytes[offset];
        final int g = rgbaBytes[offset + 1];
        final int b = rgbaBytes[offset + 2];
        
        // Gray intensity for IQA: Y = 0.299*R + 0.587*G + 0.114*B
        final double y = 0.299 * r + 0.587 * g + 0.114 * b;
        totalLuminance += y;
        intensities[i] = y;
      }
      
      final double meanIntensity = totalLuminance / numPixels / 255.0;
      
      double sumVariance = 0.0;
      for (int i = 0; i < numPixels; i++) {
        final double diff = (intensities[i] / 255.0) - meanIntensity;
        sumVariance += diff * diff;
      }
      final double contrast = math.sqrt(sumVariance / numPixels);
      
      return {
        'brightness': meanIntensity,
        'contrast': contrast,
      };
    } catch (_) {
      return {'brightness': 0.5, 'contrast': 0.5};
    }
  }

  /// Runs the full image enhancement pipeline if low light / poor contrast is detected.
  Future<EnhancementResult> enhanceImage(
    File originalFile, {
    required bool enabled,
    required String strength,
    bool force = false,
  }) async {
    final Map<String, double> metrics = await analyzeImageQuality(originalFile);
    final double originalBrightness = metrics['brightness'] ?? 0.5;
    final double originalContrast = metrics['contrast'] ?? 0.5;

    // Check triggers: brightness < 0.35 or contrast < 0.10
    final bool trigger = originalBrightness < 0.35 || originalContrast < 0.10;
    
    if (!enabled || (!trigger && !force)) {
      // Return unenhanced result
      return EnhancementResult(
        enhancedFile: originalFile,
        wasEnhanced: false,
        originalBrightness: originalBrightness,
        originalContrast: originalContrast,
        enhancedBrightness: originalBrightness,
        enhancedContrast: originalContrast,
      );
    }

    try {
      final bytes = await originalFile.readAsBytes();
      
      // Step 1: Decode and downscale to max 640x640 (preserving aspect ratio) to keep processing < 80ms
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final origImage = frame.image;
      final int origW = origImage.width;
      final int origH = origImage.height;
      origImage.dispose();
      
      int targetW = origW;
      int targetH = origH;
      if (origW > 640 || origH > 640) {
        if (origW > origH) {
          targetW = 640;
          targetH = (origH * (640.0 / origW)).toInt();
        } else {
          targetH = 640;
          targetW = (origW * (640.0 / origH)).toInt();
        }
      }

      // Re-load at scaled resolution
      final scaleCodec = await ui.instantiateImageCodec(bytes, targetWidth: targetW, targetHeight: targetH);
      final scaleFrame = await scaleCodec.getNextFrame();
      final uiImage = scaleFrame.image;
      
      final int width = uiImage.width;
      final int height = uiImage.height;
      
      final byteData = await uiImage.toByteData(format: ui.ImageByteFormat.rawRgba);
      uiImage.dispose();
      
      if (byteData == null) {
        throw Exception("Failed to retrieve image byte data");
      }
      
      final Uint8List rgbaBytes = byteData.buffer.asUint8List();
      final int numPixels = width * height;

      // 1. White Balance (Gray World Assumption)
      double sumR = 0;
      double sumG = 0;
      double sumB = 0;
      for (int i = 0; i < numPixels; i++) {
        final int offset = i * 4;
        sumR += rgbaBytes[offset];
        sumG += rgbaBytes[offset + 1];
        sumB += rgbaBytes[offset + 2];
      }
      final double avgR = sumR / numPixels;
      final double avgG = sumG / numPixels;
      final double avgB = sumB / numPixels;
      final double avgGray = (avgR + avgG + avgB) / 3.0;
      
      double kR = avgR > 0 ? avgGray / avgR : 1.0;
      double kG = avgG > 0 ? avgGray / avgG : 1.0;
      double kB = avgB > 0 ? avgGray / avgB : 1.0;
      
      // Constrain scaling to prevent severe color shifts
      kR = kR.clamp(0.6, 1.8);
      kG = kG.clamp(0.6, 1.8);
      kB = kB.clamp(0.6, 1.8);

      // 2. Dynamic Gamma Correction
      // Light: gamma = 0.8, Medium: gamma = 0.6, Strong: gamma = 0.45
      final double gamma = strength.toLowerCase() == 'light'
          ? 0.8
          : (strength.toLowerCase() == 'strong' ? 0.45 : 0.6);
      
      // Combine White Balance & Gamma Correction into lookup tables (LUT) for O(1) pixel processing
      final Uint8List rLut = Uint8List(256);
      final Uint8List gLut = Uint8List(256);
      final Uint8List bLut = Uint8List(256);
      for (int i = 0; i < 256; i++) {
        rLut[i] = (math.pow(i / 255.0, gamma) * 255.0 * kR).clamp(0, 255).toInt();
        gLut[i] = (math.pow(i / 255.0, gamma) * 255.0 * kG).clamp(0, 255).toInt();
        bLut[i] = (math.pow(i / 255.0, gamma) * 255.0 * kB).clamp(0, 255).toInt();
      }

      final Uint8List wbGammaBytes = Uint8List(numPixels * 4);
      for (int i = 0; i < numPixels; i++) {
        final int offset = i * 4;
        wbGammaBytes[offset] = rLut[rgbaBytes[offset]];
        wbGammaBytes[offset + 1] = gLut[rgbaBytes[offset + 1]];
        wbGammaBytes[offset + 2] = bLut[rgbaBytes[offset + 2]];
        wbGammaBytes[offset + 3] = rgbaBytes[offset + 3];
      }

      // 3. Denoising (3x3 Gaussian Filter)
      final Uint8List blurredBytes = Uint8List(numPixels * 4);
      for (int i = 0; i < numPixels * 4; i++) {
        blurredBytes[i] = wbGammaBytes[i];
      }
      
      for (int y = 1; y < height - 1; y++) {
        for (int x = 1; x < width - 1; x++) {
          final int idx = (y * width + x) * 4;
          for (int c = 0; c < 3; c++) {
            final int sum = 
              wbGammaBytes[((y - 1) * width + (x - 1)) * 4 + c] +
              2 * wbGammaBytes[((y - 1) * width + x) * 4 + c] +
              wbGammaBytes[((y - 1) * width + (x + 1)) * 4 + c] +
              2 * wbGammaBytes[(y * width + (x - 1)) * 4 + c] +
              4 * wbGammaBytes[idx + c] +
              2 * wbGammaBytes[(y * width + (x + 1)) * 4 + c] +
              wbGammaBytes[((y + 1) * width + (x - 1)) * 4 + c] +
              2 * wbGammaBytes[((y + 1) * width + x) * 4 + c] +
              wbGammaBytes[((y + 1) * width + (x + 1)) * 4 + c];
            
            blurredBytes[idx + c] = sum >> 4; // fast divide by 16
          }
        }
      }

      // Compute Y (luminance) channel for CLAHE
      final Float32List blurredY = Float32List(numPixels);
      for (int i = 0; i < numPixels; i++) {
        final int offset = i * 4;
        blurredY[i] = 0.299 * blurredBytes[offset] + 0.587 * blurredBytes[offset + 1] + 0.114 * blurredBytes[offset + 2];
      }

      // 4. CLAHE (Contrast Limited Adaptive Histogram Equalization)
      const int gridX = 8;
      const int gridY = 8;
      final int tileW = (width / gridX).floor();
      final int tileH = (height / gridY).floor();
      
      final List<List<Int32List>> histograms = List.generate(
        gridY,
        (_) => List.generate(gridX, (_) => Int32List(256)),
      );
      
      for (int gy = 0; gy < gridY; gy++) {
        for (int gx = 0; gx < gridX; gx++) {
          final int startX = gx * tileW;
          final int startY = gy * tileH;
          final int endX = gx == gridX - 1 ? width : startX + tileW;
          final int endY = gy == gridY - 1 ? height : startY + tileH;
          final int tilePixels = (endX - startX) * (endY - startY);
          
          final hist = histograms[gy][gx];
          for (int y = startY; y < endY; y++) {
            for (int x = startX; x < endX; x++) {
              final int val = blurredY[y * width + x].round().clamp(0, 255);
              hist[val]++;
            }
          }
          
          // Clip & redistribute
          final double clipFactor = strength.toLowerCase() == 'light'
              ? 1.8
              : (strength.toLowerCase() == 'strong' ? 3.5 : 2.5);
          final int clipLimit = (clipFactor * tilePixels / 256.0).round().clamp(1, tilePixels);
          
          int excess = 0;
          for (int i = 0; i < 256; i++) {
            if (hist[i] > clipLimit) {
              excess += hist[i] - clipLimit;
              hist[i] = clipLimit;
            }
          }
          
          final int incr = excess ~/ 256;
          final int rem = excess % 256;
          for (int i = 0; i < 256; i++) {
            hist[i] += incr;
          }
          for (int i = 0; i < rem; i++) {
            hist[i]++;
          }
        }
      }
      
      final List<List<Float32List>> cdfs = List.generate(
        gridY,
        (_) => List.generate(gridX, (_) => Float32List(256)),
      );
      
      for (int gy = 0; gy < gridY; gy++) {
        for (int gx = 0; gx < gridX; gx++) {
          final int startX = gx * tileW;
          final int startY = gy * tileH;
          final int endX = gx == gridX - 1 ? width : startX + tileW;
          final int endY = gy == gridY - 1 ? height : startY + tileH;
          final int tilePixels = (endX - startX) * (endY - startY);
          
          final hist = histograms[gy][gx];
          final cdf = cdfs[gy][gx];
          
          int sum = 0;
          for (int i = 0; i < 256; i++) {
            sum += hist[i];
            cdf[i] = (sum / tilePixels) * 255.0;
          }
        }
      }

      // Map pixels using Bilinear Interpolation over CDFs of neighboring tiles
      final Uint8List finalBytes = Uint8List(numPixels * 4);
      for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
          final int idx = (y * width + x) * 4;
          final double oldY = blurredY[y * width + x];
          final int oldYInt = oldY.round().clamp(0, 255);
          
          final double fx = (x - tileW / 2) / tileW;
          final double fy = (y - tileH / 2) / tileH;
          
          final int gx1 = fx.floor().clamp(0, gridX - 1);
          final int gx2 = (gx1 + 1).clamp(0, gridX - 1);
          final int gy1 = fy.floor().clamp(0, gridY - 1);
          final int gy2 = (gy1 + 1).clamp(0, gridY - 1);
          
          final double tx = fx - gx1;
          final double ty = fy - gy1;
          
          final double val11 = cdfs[gy1][gx1][oldYInt];
          final double val12 = cdfs[gy2][gx1][oldYInt];
          final double val21 = cdfs[gy1][gx2][oldYInt];
          final double val22 = cdfs[gy2][gx2][oldYInt];
          
          final double newY = (1.0 - tx) * (1.0 - ty) * val11 +
                              tx * (1.0 - ty) * val21 +
                              (1.0 - tx) * ty * val12 +
                              tx * ty * val22;
          
          final double ratio = oldY > 0.0 ? newY / oldY : 0.0;
          
          finalBytes[idx] = (blurredBytes[idx] * ratio).round().clamp(0, 255);
          finalBytes[idx + 1] = (blurredBytes[idx + 1] * ratio).round().clamp(0, 255);
          finalBytes[idx + 2] = (blurredBytes[idx + 2] * ratio).round().clamp(0, 255);
          finalBytes[idx + 3] = blurredBytes[idx + 3];
        }
      }

      // Convert final pixels back to a File
      final Completer<ui.Image> completer = Completer<ui.Image>();
      ui.decodeImageFromPixels(
        finalBytes,
        width,
        height,
        ui.PixelFormat.rgba8888,
        completer.complete,
      );
      final ui.Image finalImage = await completer.future;
      
      final ByteData? pngByteData = await finalImage.toByteData(format: ui.ImageByteFormat.png);
      finalImage.dispose();
      
      if (pngByteData == null) {
        throw Exception("Failed to encode enhanced image to PNG");
      }
      
      final Uint8List pngBytes = pngByteData.buffer.asUint8List();
      final Directory tempDir = await getTemporaryDirectory();
      final String enhancedPath = '${tempDir.path}/enhanced_${DateTime.now().millisecondsSinceEpoch}.png';
      final File enhancedFile = File(enhancedPath);
      await enhancedFile.writeAsBytes(pngBytes);

      // Re-evaluate quality scores
      final Map<String, double> newMetrics = await analyzeImageQuality(enhancedFile);
      final double enhancedBrightness = newMetrics['brightness'] ?? 0.5;
      final double enhancedContrast = newMetrics['contrast'] ?? 0.5;

      return EnhancementResult(
        enhancedFile: enhancedFile,
        wasEnhanced: true,
        originalBrightness: originalBrightness,
        originalContrast: originalContrast,
        enhancedBrightness: enhancedBrightness,
        enhancedContrast: enhancedContrast,
      );
    } catch (e) {
      debugPrint("Error in ImageEnhancementService: $e");
      return EnhancementResult(
        enhancedFile: originalFile,
        wasEnhanced: false,
        originalBrightness: originalBrightness,
        originalContrast: originalContrast,
        enhancedBrightness: originalBrightness,
        enhancedContrast: originalContrast,
      );
    }
  }
}
