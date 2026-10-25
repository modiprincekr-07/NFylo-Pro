import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';
import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:syncfusion_flutter_pdf/pdf.dart';

class PdfInfo {
  final int pageCount;
  final double width;
  final double height;
  final int fileSizeBytes;
  final String title;
  final String author;

  PdfInfo({
    required this.pageCount,
    required this.width,
    required this.height,
    required this.fileSizeBytes,
    required this.title,
    required this.author,
  });
}

class PdfToolkitService {
  static const String _defaultPdfFolder = '/storage/emulated/0/Download/NFylo_PDFs';
  static const String _defaultEpubFolder = '/storage/emulated/0/Download/NFylo_EPUBs';

  static Directory _getOutputDir(String folderPath) {
    final dir = Directory(folderPath);
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return dir;
  }

  /// Retrieves metadata and page count for a given PDF file.
  static Future<PdfInfo> getPdfInfo(String pdfPath) async {
    final file = File(pdfPath);
    final bytes = await file.readAsBytes();
    final document = PdfDocument(inputBytes: bytes);

    final pageCount = document.pages.count;
    double width = 0;
    double height = 0;
    if (pageCount > 0) {
      width = document.pages[0].size.width;
      height = document.pages[0].size.height;
    }
    final title = document.documentInformation.title;
    final author = document.documentInformation.author;
    final size = bytes.length;

    document.dispose();

    return PdfInfo(
      pageCount: pageCount,
      width: width,
      height: height,
      fileSizeBytes: size,
      title: title.isEmpty ? p.basenameWithoutExtension(pdfPath) : title,
      author: author,
    );
  }

  /// Merges multiple PDF files in the specified order into a single PDF in an isolate.
  static Future<String> mergePdfs({
    required List<String> pdfPaths,
    String? outputName,
  }) async {
    if (pdfPaths.length < 2) {
      throw Exception('Please select at least 2 PDF files to merge.');
    }
    final outDir = _getOutputDir(_defaultPdfFolder).path;
    return compute(_mergePdfsIsolate, {
      'paths': pdfPaths,
      'outDir': outDir,
      'outputName': outputName,
    });
  }

  /// Merges a list of PDF File objects in an isolate via compute().
  static Future<String> mergePdfFiles(
    List<File> files, {
    String? outputName,
  }) async {
    return mergePdfs(
      pdfPaths: files.map((f) => f.path).toList(),
      outputName: outputName,
    );
  }

  /// Splits a PDF file into two documents at the given splitPage (1-indexed) in an isolate.
  static Future<List<String>> splitPdfAtPage(
    File file,
    int splitPage, {
    String? outputDir,
  }) async {
    final targetDir = outputDir ?? _getOutputDir(_defaultPdfFolder).path;
    return compute(_splitPdfIsolate, {
      'path': file.path,
      'splitPage': splitPage,
      'outDir': targetDir,
    });
  }

  /// Extracts all text from a PDF file in an isolate via compute().
  static Future<String> extractText(File file) async {
    return compute(_extractTextIsolate, file.path);
  }

  /// Splits or extracts specific pages from a PDF.
  static Future<String> splitPdf({
    required String inputPath,
    required List<int> pageIndices, // 0-indexed
    String? outputName,
  }) async {
    if (pageIndices.isEmpty) {
      throw Exception('No pages selected to extract.');
    }

    final file = File(inputPath);
    final bytes = await file.readAsBytes();
    final sourceDoc = PdfDocument(inputBytes: bytes);

    final newDoc = PdfDocument();
    newDoc.pageSettings.margins.all = 0;

    for (final index in pageIndices) {
      if (index >= 0 && index < sourceDoc.pages.count) {
        final page = sourceDoc.pages[index];
        final template = page.createTemplate();
        newDoc.pageSettings.size = page.size;
        final newPage = newDoc.pages.add();
        newPage.graphics.drawPdfTemplate(template, Offset.zero);
      }
    }

    sourceDoc.dispose();

    final outDir = _getOutputDir(_defaultPdfFolder);
    final base = p.basenameWithoutExtension(inputPath);
    final safeName = (outputName == null || outputName.trim().isEmpty)
        ? '${base}_split_${DateTime.now().millisecondsSinceEpoch}.pdf'
        : '${outputName.replaceAll(RegExp(r'[\\/:*?"<>| ]'), '_')}.pdf';

    final outPath = p.join(outDir.path, safeName);
    final savedBytes = await newDoc.save();
    newDoc.dispose();

    await File(outPath).writeAsBytes(savedBytes);
    return outPath;
  }

  /// Rotates specified pages (or all pages) in a PDF document by 90, 180, or 270 degrees.
  static Future<String> rotatePdfPages({
    required String inputPath,
    required List<int> pageIndices, // 0-indexed
    required int degrees, // 90, 180, 270
    String? outputName,
  }) async {
    final file = File(inputPath);
    final bytes = await file.readAsBytes();
    final sourceDoc = PdfDocument(inputBytes: bytes);

    PdfPageRotateAngle angle;
    switch (degrees) {
      case 90:
        angle = PdfPageRotateAngle.rotateAngle90;
        break;
      case 180:
        angle = PdfPageRotateAngle.rotateAngle180;
        break;
      case 270:
        angle = PdfPageRotateAngle.rotateAngle270;
        break;
      default:
        angle = PdfPageRotateAngle.rotateAngle0;
    }

    final newDoc = PdfDocument();
    newDoc.pageSettings.margins.all = 0;

    for (int i = 0; i < sourceDoc.pages.count; i++) {
      final page = sourceDoc.pages[i];
      final template = page.createTemplate();
      final shouldRotate = pageIndices.contains(i);

      if (shouldRotate && (degrees == 90 || degrees == 270)) {
        newDoc.pageSettings.size = Size(page.size.height, page.size.width);
      } else {
        newDoc.pageSettings.size = page.size;
      }

      if (shouldRotate) {
        newDoc.pageSettings.rotate = angle;
      } else {
        newDoc.pageSettings.rotate = PdfPageRotateAngle.rotateAngle0;
      }

      final newPage = newDoc.pages.add();
      newPage.graphics.drawPdfTemplate(template, Offset.zero);
    }

    sourceDoc.dispose();

    final outDir = _getOutputDir(_defaultPdfFolder);
    final base = p.basenameWithoutExtension(inputPath);
    final safeName = (outputName == null || outputName.trim().isEmpty)
        ? '${base}_rotated_${degrees}deg_${DateTime.now().millisecondsSinceEpoch}.pdf'
        : '${outputName.replaceAll(RegExp(r'[\\/:*?"<>| ]'), '_')}.pdf';

    final outPath = p.join(outDir.path, safeName);
    final savedBytes = await newDoc.save();
    newDoc.dispose();

    await File(outPath).writeAsBytes(savedBytes);
    return outPath;
  }

  /// Adds a custom diagonal text watermark to all or selected pages in a PDF.
  static Future<String> addTextWatermark({
    required String inputPath,
    required String watermarkText,
    double opacity = 0.25,
    double fontSize = 42,
    double rotationDegrees = -40,
    List<int>? targetPageIndices, // null = all pages
    String? outputName,
  }) async {
    final file = File(inputPath);
    final bytes = await file.readAsBytes();
    final document = PdfDocument(inputBytes: bytes);

    final font = PdfStandardFont(
      PdfFontFamily.helvetica,
      fontSize,
      style: PdfFontStyle.bold,
    );
    final textSize = font.measureString(watermarkText);

    for (int i = 0; i < document.pages.count; i++) {
      if (targetPageIndices != null && !targetPageIndices.contains(i)) {
        continue;
      }

      final page = document.pages[i];
      final graphics = page.graphics;
      final state = graphics.save();

      graphics.setTransparency(opacity.clamp(0.05, 1.0));
      // Center of the page
      final centerX = page.size.width / 2;
      final centerY = page.size.height / 2;

      graphics.translateTransform(centerX, centerY);
      graphics.rotateTransform(rotationDegrees);

      graphics.drawString(
        watermarkText,
        font,
        pen: PdfPens.darkGray,
        brush: PdfBrushes.darkGray,
        bounds: Rect.fromLTWH(
          -textSize.width / 2,
          -textSize.height / 2,
          textSize.width,
          textSize.height,
        ),
      );

      graphics.restore(state);
    }

    final outDir = _getOutputDir(_defaultPdfFolder);
    final base = p.basenameWithoutExtension(inputPath);
    final safeName = (outputName == null || outputName.trim().isEmpty)
        ? '${base}_watermarked_${DateTime.now().millisecondsSinceEpoch}.pdf'
        : '${outputName.replaceAll(RegExp(r'[\\/:*?"<>| ]'), '_')}.pdf';

    final outPath = p.join(outDir.path, safeName);
    final savedBytes = await document.save();
    document.dispose();

    await File(outPath).writeAsBytes(savedBytes);
    return outPath;
  }

  /// Converts a PDF document into a reflowable .epub eBook.
  /// Extracts text page by page, groups it into HTML sections, and packages into EPUB 3 format.
  static Future<String> convertPdfToEpub({
    required String inputPath,
    String? bookTitle,
    String? author,
    String? outputName,
  }) async {
    final file = File(inputPath);
    final bytes = await file.readAsBytes();
    final document = PdfDocument(inputBytes: bytes);

    final base = p.basenameWithoutExtension(inputPath);
    final title = (bookTitle != null && bookTitle.trim().isNotEmpty)
        ? bookTitle.trim()
        : (document.documentInformation.title.isNotEmpty
            ? document.documentInformation.title
            : base);
    final bookAuthor = (author != null && author.trim().isNotEmpty)
        ? author.trim()
        : (document.documentInformation.author.isNotEmpty
            ? document.documentInformation.author
            : 'Unknown Author');

    final extractor = PdfTextExtractor(document);
    final pageTexts = <String>[];

    for (int i = 0; i < document.pages.count; i++) {
      try {
        final pageText = extractor.extractText(startPageIndex: i, endPageIndex: i);
        if (pageText.trim().isNotEmpty) {
          pageTexts.add(pageText.trim());
        }
      } catch (_) {}
    }

    document.dispose();

    if (pageTexts.isEmpty) {
      throw Exception(
        'Could not extract text from this PDF. It may contain scanned image pages without OCR.',
      );
    }

    // Build EPUB package in memory
    final archive = Archive();
    final timestamp = DateTime.now().toUtc().toIso8601String().split('.').first + 'Z';
    final uuid = 'urn:uuid:${DateTime.now().millisecondsSinceEpoch}';

    // 1. mimetype (Must be first, stored uncompressed)
    final mimeBytes = Uint8List.fromList('application/epub+zip'.codeUnits);
    archive.addFile(ArchiveFile('mimetype', mimeBytes.length, mimeBytes)..compress = false);

    // 2. META-INF/container.xml
    const containerXml = '''<?xml version="1.0" encoding="UTF-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
    <rootfiles>
        <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
    </rootfiles>
</container>''';
    final containerBytes = Uint8List.fromList(containerXml.codeUnits);
    archive.addFile(ArchiveFile('META-INF/container.xml', containerBytes.length, containerBytes));

    // 3. Chapters
    final manifestItems = StringBuffer();
    final spineItems = StringBuffer();
    final tocNavPoints = StringBuffer();

    for (int i = 0; i < pageTexts.length; i++) {
      final pageNum = i + 1;
      final rawContent = pageTexts[i];
      final paragraphs = rawContent
          .split(RegExp(r'\n\s*\n|\r\n\s*\r\n'))
          .where((p) => p.trim().isNotEmpty)
          .map((p) => '<p>${_escapeHtml(p.trim())}</p>')
          .join('\n');

      final chapterHtml = '''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml">
<head>
    <title>Page $pageNum</title>
    <style>
        body { font-family: sans-serif; line-height: 1.6; margin: 5%; color: #1a1a1a; }
        h2 { border-bottom: 1px solid #ccc; padding-bottom: 4px; color: #333; }
        p { margin-bottom: 1em; text-indent: 1em; }
    </style>
</head>
<body>
    <h2>Page $pageNum</h2>
    $paragraphs
</body>
</html>''';

      final chPath = 'OEBPS/chapter_$pageNum.xhtml';
      final chBytes = Uint8List.fromList(chapterHtml.codeUnits);
      archive.addFile(ArchiveFile(chPath, chBytes.length, chBytes));

      manifestItems.writeln(
        '        <item id="chapter$pageNum" href="chapter_$pageNum.xhtml" media-type="application/xhtml+xml"/>',
      );
      spineItems.writeln('        <itemref idref="chapter$pageNum"/>');
      tocNavPoints.writeln('''        <navPoint id="navPoint-$pageNum" playOrder="$pageNum">
            <navLabel><text>Page $pageNum</text></navLabel>
            <content src="chapter_$pageNum.xhtml"/>
        </navPoint>''');
    }

    // 4. OEBPS/toc.ncx
    final tocNcx = '''<?xml version="1.0" encoding="UTF-8"?>
<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">
    <head>
        <meta name="dtb:uid" content="$uuid"/>
        <meta name="dtb:depth" content="1"/>
        <meta name="dtb:totalPageCount" content="0"/>
        <meta name="dtb:maxPageNumber" content="0"/>
    </head>
    <docTitle><text>${_escapeHtml(title)}</text></docTitle>
    <docAuthor><text>${_escapeHtml(bookAuthor)}</text></docAuthor>
    <navMap>
$tocNavPoints
    </navMap>
</ncx>''';
    final tocBytes = Uint8List.fromList(tocNcx.codeUnits);
    archive.addFile(ArchiveFile('OEBPS/toc.ncx', tocBytes.length, tocBytes));

    // 5. OEBPS/nav.xhtml (EPUB 3 Navigation)
    final navItems = List.generate(
      pageTexts.length,
      (i) => '            <li><a href="chapter_${i + 1}.xhtml">Page ${i + 1}</a></li>',
    ).join('\n');

    final navXhtml = '''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
<head><title>Table of Contents</title></head>
<body>
    <nav epub:type="toc" id="toc">
        <h1>Table of Contents</h1>
        <ol>
$navItems
        </ol>
    </nav>
</body>
</html>''';
    final navBytes = Uint8List.fromList(navXhtml.codeUnits);
    archive.addFile(ArchiveFile('OEBPS/nav.xhtml', navBytes.length, navBytes));

    // 6. OEBPS/content.opf
    final contentOpf = '''<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" unique-identifier="BookID" version="3.0">
    <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
        <dc:title>${_escapeHtml(title)}</dc:title>
        <dc:creator>${_escapeHtml(bookAuthor)}</dc:creator>
        <dc:language>en</dc:language>
        <dc:identifier id="BookID">$uuid</dc:identifier>
        <meta property="dcterms:modified">$timestamp</meta>
    </metadata>
    <manifest>
$manifestItems
        <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
        <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
    </manifest>
    <spine toc="ncx">
$spineItems
    </spine>
</package>''';
    final opfBytes = Uint8List.fromList(contentOpf.codeUnits);
    archive.addFile(ArchiveFile('OEBPS/content.opf', opfBytes.length, opfBytes));

    // Compress into EPUB zip file
    final encoder = ZipEncoder();
    final epubBytes = encoder.encode(archive);
    if (epubBytes == null) {
      throw Exception('Failed to generate EPUB archive.');
    }

    final outDir = _getOutputDir(_defaultEpubFolder);
    final safeName = (outputName == null || outputName.trim().isEmpty)
        ? '${base}_converted.epub'
        : '${outputName.replaceAll(RegExp(r'[\\/:*?"<>| ]'), '_')}.epub';

    final outPath = p.join(outDir.path, safeName);
    await File(outPath).writeAsBytes(epubBytes);
    return outPath;
  }

  static String _escapeHtml(String text) {
    return text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&#39;');
  }
}

// -------------------------------------------------------------
// Top-Level / Static Isolate Functions for Zero UI-Freezing
// -------------------------------------------------------------

Future<String> _mergePdfsIsolate(Map<String, dynamic> params) async {
  final List<String> paths = List<String>.from(params['paths']);
  final String outDir = params['outDir'];
  final String? outputName = params['outputName'];

  final newDocument = PdfDocument();
  newDocument.pageSettings.margins.all = 0;

  for (final pdfPath in paths) {
    final file = File(pdfPath);
    final bytes = await file.readAsBytes();
    final loadedDoc = PdfDocument(inputBytes: bytes);

    for (int i = 0; i < loadedDoc.pages.count; i++) {
      final originalPage = loadedDoc.pages[i];
      final template = originalPage.createTemplate();
      newDocument.pageSettings.size = originalPage.size;
      final newPage = newDocument.pages.add();
      newPage.graphics.drawPdfTemplate(template, Offset.zero);
    }

    loadedDoc.dispose();
  }

  final safeName = (outputName == null || outputName.trim().isEmpty)
      ? 'merged_${DateTime.now().millisecondsSinceEpoch}.pdf'
      : '${outputName.replaceAll(RegExp(r'[\\/:*?"<>| ]'), '_')}.pdf';

  final outPath = p.join(outDir, safeName);
  final savedBytes = await newDocument.save();
  newDocument.dispose();

  await File(outPath).writeAsBytes(savedBytes);
  return outPath;
}

Future<List<String>> _splitPdfIsolate(Map<String, dynamic> params) async {
  final String inputPath = params['path'];
  final int splitPage = params['splitPage']; // 1-indexed split point
  final String outDir = params['outDir'];

  final file = File(inputPath);
  final bytes = await file.readAsBytes();
  final sourceDoc = PdfDocument(inputBytes: bytes);
  final totalPages = sourceDoc.pages.count;

  if (splitPage < 1 || splitPage >= totalPages) {
    sourceDoc.dispose();
    throw Exception('Split page must be between 1 and ${totalPages - 1}');
  }

  final base = p.basenameWithoutExtension(inputPath);
  final timestamp = DateTime.now().millisecondsSinceEpoch;

  // Part 1: pages 0 to splitPage - 1
  final doc1 = PdfDocument();
  doc1.pageSettings.margins.all = 0;
  for (int i = 0; i < splitPage; i++) {
    final page = sourceDoc.pages[i];
    final template = page.createTemplate();
    doc1.pageSettings.size = page.size;
    final newPage = doc1.pages.add();
    newPage.graphics.drawPdfTemplate(template, Offset.zero);
  }
  final path1 = p.join(outDir, '${base}_part1_${timestamp}.pdf');
  final bytes1 = await doc1.save();
  doc1.dispose();
  await File(path1).writeAsBytes(bytes1);

  // Part 2: pages splitPage to totalPages - 1
  final doc2 = PdfDocument();
  doc2.pageSettings.margins.all = 0;
  for (int i = splitPage; i < totalPages; i++) {
    final page = sourceDoc.pages[i];
    final template = page.createTemplate();
    doc2.pageSettings.size = page.size;
    final newPage = doc2.pages.add();
    newPage.graphics.drawPdfTemplate(template, Offset.zero);
  }
  final path2 = p.join(outDir, '${base}_part2_${timestamp}.pdf');
  final bytes2 = await doc2.save();
  doc2.dispose();
  await File(path2).writeAsBytes(bytes2);

  sourceDoc.dispose();
  return [path1, path2];
}

Future<String> _extractTextIsolate(String inputPath) async {
  final file = File(inputPath);
  final bytes = await file.readAsBytes();
  final document = PdfDocument(inputBytes: bytes);
  final extractor = PdfTextExtractor(document);
  final text = extractor.extractText();
  document.dispose();
  return text;
}
