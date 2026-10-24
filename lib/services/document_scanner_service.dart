import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:syncfusion_flutter_pdf/pdf.dart';

enum ScannerFilter {
  original,
  blackAndWhite,
  grayscale,
  enhancedColor,
}

class ScannedPage {
  final String id;
  final Uint8List originalBytes;
  Uint8List processedBytes;
  ScannerFilter filter;
  int rotationDegrees;
  int width;
  int height;

  ScannedPage({
    required this.id,
    required this.originalBytes,
    required this.processedBytes,
    this.filter = ScannerFilter.blackAndWhite,
    this.rotationDegrees = 0,
    required this.width,
    required this.height,
  });

  ScannedPage copyWith({
    Uint8List? processedBytes,
    ScannerFilter? filter,
    int? rotationDegrees,
    int? width,
    int? height,
  }) {
    return ScannedPage(
      id: id,
      originalBytes: originalBytes,
      processedBytes: processedBytes ?? this.processedBytes,
      filter: filter ?? this.filter,
      rotationDegrees: rotationDegrees ?? this.rotationDegrees,
      width: width ?? this.width,
      height: height ?? this.height,
    );
  }
}

class DocumentScannerService {
  static const String _defaultScansFolder =
      '/storage/emulated/0/Download/NFylo_Scanned';

  static Directory _getOutputDir() {
    final dir = Directory(_defaultScansFolder);
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return dir;
  }

  /// Processes a single scanned page image (filter + rotation) in an isolate.
  static Future<Uint8List> processPage({
    required Uint8List bytes,
    required ScannerFilter filter,
    int rotationDegrees = 0,
  }) async {
    return compute(_processTask, {
      'bytes': bytes,
      'filter': filter.name,
      'rotation': rotationDegrees,
    });
  }

  static Uint8List _processTask(Map<String, dynamic> params) {
    final Uint8List bytes = params['bytes'];
    final String filterName = params['filter'];
    final int rotation = params['rotation'] ?? 0;

    var image = img.decodeImage(bytes);
    if (image == null) {
      throw Exception('Failed to decode document image.');
    }

    // Apply rotation if required
    if (rotation != 0) {
      image = img.copyRotate(image, angle: rotation);
    }

    switch (filterName) {
      case 'blackAndWhite':
        // High-contrast document scanner filter (Binarization)
        // 1. Grayscale
        img.grayscale(image);
        // 2. Adaptive/threshold contrast for crisp text on paper
        for (final pixel in image) {
          final lum = (0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b);
          if (lum > 140) {
            pixel.r = 255;
            pixel.g = 255;
            pixel.b = 255;
          } else {
            // Emphasize text lines
            pixel.r = 0;
            pixel.g = 0;
            pixel.b = 0;
          }
        }
        break;

      case 'grayscale':
        img.grayscale(image);
        break;

      case 'enhancedColor':
        // Boost contrast and brightness for color documents, receipts & stamps
        img.adjustColor(image, contrast: 1.35, brightness: 1.08);
        break;

      case 'original':
      default:
        // Keep original colors
        break;
    }

    return Uint8List.fromList(img.encodeJpg(image, quality: 90));
  }

  /// Converts a list of processed page images into a single standardized PDF file.
  static Future<String> generatePdf({
    required List<Uint8List> pages,
    String? outputName,
    String? documentTitle,
  }) async {
    if (pages.isEmpty) {
      throw Exception('No pages to generate PDF from.');
    }

    final document = PdfDocument();
    document.pageSettings.margins.all = 0;

    final title = (documentTitle != null && documentTitle.trim().isNotEmpty)
        ? documentTitle.trim()
        : 'Scanned Document';
    document.documentInformation.title = title;
    document.documentInformation.author = 'NFylo Document Scanner';
    document.documentInformation.creationDate = DateTime.now();

    for (final pageBytes in pages) {
      final bitmap = PdfBitmap(pageBytes);
      // Auto-fit page dimension to match image aspect ratio
      final double imgW = bitmap.width.toDouble();
      final double imgH = bitmap.height.toDouble();

      // Standardize size while preserving aspect ratio
      document.pageSettings.size = Size(imgW, imgH);
      final pdfPage = document.pages.add();

      pdfPage.graphics.drawImage(
        bitmap,
        Rect.fromLTWH(0, 0, imgW, imgH),
      );
    }

    final savedBytes = await document.save();
    document.dispose();

    final outDir = _getOutputDir();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final safeName = (outputName == null || outputName.trim().isEmpty)
        ? 'scan_$timestamp.pdf'
        : '${outputName.replaceAll(RegExp(r'[\\/:*?"<>| ]'), '_')}.pdf';

    final outPath = p.join(outDir.path, safeName);
    await File(outPath).writeAsBytes(savedBytes);
    return outPath;
  }
}
