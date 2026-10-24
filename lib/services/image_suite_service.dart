import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

class GpsCoordinates {
  final double latitude;
  final double longitude;
  final double? altitude;

  GpsCoordinates({
    required this.latitude,
    required this.longitude,
    this.altitude,
  });

  String get mapsUrl =>
      'https://www.google.com/maps/search/?api=1&query=$latitude,$longitude';

  String get coordinatesString =>
      '${latitude.toStringAsFixed(6)}, ${longitude.toStringAsFixed(6)}';
}

class ExifTagItem {
  final String category; // 'Camera', 'Capture', 'Date & Time', 'GPS Location', 'Technical'
  final String key;
  final String value;
  final bool isSensitive;

  ExifTagItem({
    required this.category,
    required this.key,
    required this.value,
    this.isSensitive = false,
  });
}

class ParsedExifData {
  final List<ExifTagItem> tags;
  final GpsCoordinates? gps;
  final String? cameraMake;
  final String? cameraModel;
  final String? dateTimeOriginal;
  final String? software;
  final bool hasSensitiveGps;

  ParsedExifData({
    required this.tags,
    this.gps,
    this.cameraMake,
    this.cameraModel,
    this.dateTimeOriginal,
    this.software,
    this.hasSensitiveGps = false,
  });

  factory ParsedExifData.empty() => ParsedExifData(tags: []);
}

enum OutputImageFormat { jpg, png, webp, ico }

enum UpscaleFactor { x2, x4 }

enum UpscaleInterpolation { bicubic, bilinear, nearest }

class ImageSuiteService {
  /// Converts and compresses an image to JPG, PNG, WEBP, or ICO.
  static Future<Uint8List> convertAndCompress({
    required Uint8List inputBytes,
    required OutputImageFormat targetFormat,
    int quality = 85, // 1 - 100
    int? targetWidth,
    int? targetHeight,
    bool maintainAspectRatio = true,
  }) async {
    return compute(_convertAndCompressTask, {
      'bytes': inputBytes,
      'format': targetFormat.name,
      'quality': quality.clamp(1, 100),
      'targetWidth': targetWidth,
      'targetHeight': targetHeight,
      'maintainAspectRatio': maintainAspectRatio,
    });
  }

  static Uint8List _convertAndCompressTask(Map<String, dynamic> params) {
    final Uint8List bytes = params['bytes'];
    final String formatStr = params['format'];
    final int quality = params['quality'];
    final int? targetWidth = params['targetWidth'];
    final int? targetHeight = params['targetHeight'];
    final bool maintainAspectRatio = params['maintainAspectRatio'] ?? true;

    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw Exception('Unable to decode image file format.');
    }

    img.Image processed = decoded;

    // Apply resize if requested
    if (targetWidth != null || targetHeight != null) {
      if (maintainAspectRatio) {
        processed = img.copyResize(
          processed,
          width: targetWidth,
          height: targetHeight,
          maintainAspect: true,
          interpolation: img.Interpolation.cubic,
        );
      } else {
        processed = img.copyResize(
          processed,
          width: targetWidth ?? processed.width,
          height: targetHeight ?? processed.height,
          maintainAspect: false,
          interpolation: img.Interpolation.cubic,
        );
      }
    }

    switch (formatStr) {
      case 'png':
        // PNG compression level (0 = none, 9 = max compression)
        final level = ((100 - quality) / 10).round().clamp(0, 9);
        return Uint8List.fromList(img.encodePng(processed, level: level));
      case 'webp':
        return Uint8List.fromList(img.encodeWebP(
          processed,
          quality: quality,
          lossless: false,
        ));
      case 'ico':
        // ICO usually requires small dimensions (e.g. max 256x256)
        img.Image icoImg = processed;
        if (icoImg.width > 256 || icoImg.height > 256) {
          icoImg = img.copyResize(icoImg, width: 256, height: 256);
        }
        return Uint8List.fromList(img.encodeIco(icoImg));
      case 'jpg':
      default:
        return Uint8List.fromList(img.encodeJpg(processed, quality: quality));
    }
  }

  /// Upscales an image by 2x or 4x using high quality pure Dart interpolation.
  static Future<Uint8List> upscaleImage({
    required Uint8List inputBytes,
    required UpscaleFactor factor,
    UpscaleInterpolation interpolation = UpscaleInterpolation.bicubic,
  }) async {
    return compute(_upscaleTask, {
      'bytes': inputBytes,
      'scale': factor == UpscaleFactor.x4 ? 4 : 2,
      'interpolation': interpolation.name,
    });
  }

  static Uint8List _upscaleTask(Map<String, dynamic> params) {
    final Uint8List bytes = params['bytes'];
    final int scale = params['scale'];
    final String interpStr = params['interpolation'];

    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw Exception('Failed to decode image for upscaling.');
    }

    img.Interpolation interpolation;
    switch (interpStr) {
      case 'nearest':
        interpolation = img.Interpolation.nearest;
        break;
      case 'bilinear':
        interpolation = img.Interpolation.linear;
        break;
      case 'bicubic':
      default:
        interpolation = img.Interpolation.cubic;
        break;
    }

    final upscaled = img.copyResize(
      decoded,
      width: decoded.width * scale,
      height: decoded.height * scale,
      interpolation: interpolation,
    );

    // Default to high quality JPEG or preserve PNG if original had alpha
    if (decoded.hasAlpha) {
      return Uint8List.fromList(img.encodePng(upscaled, level: 6));
    } else {
      return Uint8List.fromList(img.encodeJpg(upscaled, quality: 95));
    }
  }

  /// Strips all EXIF, GPS, IPTC, and XMP metadata from an image.
  /// For JPEG, uses lossless APP segment stripping (0% quality loss, original pixels intact).
  /// For PNG/WEBP, re-encodes without EXIF metadata tags.
  static Future<Uint8List> stripExifMetadata({
    required Uint8List inputBytes,
    required String fileExtension,
  }) async {
    final ext = fileExtension.toLowerCase().replaceAll('.', '');

    if (ext == 'jpg' || ext == 'jpeg') {
      try {
        final lossless = _stripJpegMarkersLossless(inputBytes);
        if (lossless != null) return lossless;
      } catch (_) {}
    }

    // Fallback via image decode/re-encode
    return compute(_reencodeCleanTask, inputBytes);
  }

  static Uint8List _reencodeCleanTask(Uint8List bytes) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw Exception('Could not decode image for metadata stripping.');
    }

    // Clear EXIF object
    decoded.exif.clear();

    if (decoded.hasAlpha) {
      return Uint8List.fromList(img.encodePng(decoded));
    } else {
      return Uint8List.fromList(img.encodeJpg(decoded, quality: 96));
    }
  }

  /// Lossless JPEG metadata stripper: removes APP1 (EXIF/XMP), APP2 (FlashPix),
  /// APP13 (Photoshop IPTC), and COM segments without touching entropy-coded pixel scans.
  static Uint8List? _stripJpegMarkersLossless(Uint8List bytes) {
    if (bytes.length < 4) return null;
    if (bytes[0] != 0xFF || bytes[1] != 0xD8) return null; // Not JPEG SOI

    final cleanChunks = <Uint8List>[];
    cleanChunks.add(Uint8List.fromList([0xFF, 0xD8])); // SOI

    int offset = 2;
    while (offset < bytes.length) {
      if (bytes[offset] != 0xFF) {
        offset++;
        continue;
      }

      final marker = bytes[offset + 1];
      // 0xFF 0x00 is stuffing byte, 0xFF 0xFF is fill
      if (marker == 0x00 || marker == 0xFF) {
        offset += 2;
        continue;
      }

      // SOS (Start of Scan 0xDA) means entropy data begins; append rest and finish
      if (marker == 0xDA) {
        cleanChunks.add(bytes.sublist(offset));
        break;
      }

      // RST (Restart) or SOI have no payload length
      if (marker == 0xD8 || (marker >= 0xD0 && marker <= 0xD7)) {
        cleanChunks.add(bytes.sublist(offset, offset + 2));
        offset += 2;
        continue;
      }

      if (offset + 4 > bytes.length) break;
      final len = (bytes[offset + 2] << 8) | bytes[offset + 3];
      final segmentEnd = offset + 2 + len;
      if (segmentEnd > bytes.length) break;

      // Metadata markers to strip:
      // 0xE1 = APP1 (EXIF / XMP)
      // 0xE2 = APP2 (ICC Profile / Flashpix)
      // 0xED = APP13 (Photoshop IPTC)
      // 0xFE = Comment
      final isMetadataMarker = (marker == 0xE1 ||
          marker == 0xE2 ||
          marker == 0xED ||
          marker == 0xFE);

      if (!isMetadataMarker) {
        cleanChunks.add(bytes.sublist(offset, segmentEnd));
      }

      offset = segmentEnd;
    }

    final totalLen = cleanChunks.fold(0, (sum, c) => sum + c.length);
    final result = Uint8List(totalLen);
    int pos = 0;
    for (final c in cleanChunks) {
      result.setRange(pos, pos + c.length, c);
      pos += c.length;
    }
    return result;
  }

  /// Parses comprehensive EXIF metadata (Camera, settings, GPS location).
  static Future<ParsedExifData> parseExifMetadata(Uint8List bytes) async {
    return compute(_parseExifTask, bytes);
  }

  static ParsedExifData _parseExifTask(Uint8List bytes) {
    final tags = <ExifTagItem>[];
    GpsCoordinates? gps;
    String? make;
    String? model;
    String? dateTime;
    String? software;

    // First try pure Dart TIFF/EXIF parser for robust GPS and camera fields
    try {
      final tiffExif = _extractTiffExifFromJpeg(bytes);
      if (tiffExif != null) {
        tags.addAll(tiffExif.tags);
        gps = tiffExif.gps;
        make = tiffExif.cameraMake;
        model = tiffExif.cameraModel;
        dateTime = tiffExif.dateTimeOriginal;
        software = tiffExif.software;
      }
    } catch (_) {}

    // Fallback/enrichment with package:image ExifData
    try {
      final decoded = img.decodeImage(bytes);
      if (decoded != null && !decoded.exif.isEmpty) {
        final exif = decoded.exif;

        // Image IFD
        for (final entry in exif.imageIfd.data.entries) {
          final tagName = _getTagName(entry.key);
          final val = entry.value.toString();
          if (!tags.any((t) => t.key == tagName)) {
            tags.add(ExifTagItem(
              category: 'Device & Camera',
              key: tagName,
              value: val,
            ));
          }
        }

        // Exif IFD
        for (final entry in exif.exifIfd.data.entries) {
          final tagName = _getTagName(entry.key);
          final val = entry.value.toString();
          if (!tags.any((t) => t.key == tagName)) {
            tags.add(ExifTagItem(
              category: 'Capture Settings',
              key: tagName,
              value: val,
            ));
          }
        }

        // GPS IFD
        for (final entry in exif.gpsIfd.data.entries) {
          final tagName = _getGpsTagName(entry.key);
          final val = entry.value.toString();
          if (!tags.any((t) => t.key == tagName)) {
            tags.add(ExifTagItem(
              category: 'GPS Location',
              key: tagName,
              value: val,
              isSensitive: true,
            ));
          }
        }
      }
    } catch (_) {}

    return ParsedExifData(
      tags: tags,
      gps: gps,
      cameraMake: make,
      cameraModel: model,
      dateTimeOriginal: dateTime,
      software: software,
      hasSensitiveGps: gps != null,
    );
  }

  /// Parses TIFF Header inside JPEG APP1 marker directly.
  static ParsedExifData? _extractTiffExifFromJpeg(Uint8List bytes) {
    if (bytes.length < 4 || bytes[0] != 0xFF || bytes[1] != 0xD8) return null;

    int offset = 2;
    Uint8List? app1Payload;

    while (offset + 4 < bytes.length) {
      if (bytes[offset] != 0xFF) {
        offset++;
        continue;
      }
      final marker = bytes[offset + 1];
      if (marker == 0xDA) break; // SOS
      final len = (bytes[offset + 2] << 8) | bytes[offset + 3];
      if (marker == 0xE1 && offset + 4 + len <= bytes.length) {
        app1Payload = bytes.sublist(offset + 4, offset + 2 + len);
        break;
      }
      offset += 2 + len;
    }

    if (app1Payload == null || app1Payload.length < 14) return null;

    // Check "Exif\0\0" header
    if (app1Payload[0] != 0x45 ||
        app1Payload[1] != 0x78 ||
        app1Payload[2] != 0x69 ||
        app1Payload[3] != 0x66 ||
        app1Payload[4] != 0x00 ||
        app1Payload[5] != 0x00) {
      return null;
    }

    final tiffData = app1Payload.sublist(6);
    final bd = ByteData.sublistView(tiffData);

    // Byte order: 0x4949 = Little Endian, 0x4D4D = Big Endian
    final isLE = tiffData[0] == 0x49 && tiffData[1] == 0x49;
    final endian = isLE ? Endian.little : Endian.big;

    final magic = bd.getUint16(2, endian);
    if (magic != 42) return null;

    final firstIfdOffset = bd.getUint32(4, endian);
    if (firstIfdOffset >= tiffData.length) return null;

    final tags = <ExifTagItem>[];
    String? make;
    String? model;
    String? dateTime;
    String? software;
    int? exifIfdOffset;
    int? gpsIfdOffset;

    // Parse IFD0
    _parseIfd(
      bd: bd,
      tiffData: tiffData,
      offset: firstIfdOffset,
      endian: endian,
      category: 'Camera & Device',
      onTag: (tagId, val) {
        if (tagId == 0x010F) make = val;
        if (tagId == 0x0110) model = val;
        if (tagId == 0x0131) software = val;
        if (tagId == 0x0132) dateTime = val;
        if (tagId == 0x8769) exifIfdOffset = int.tryParse(val);
        if (tagId == 0x8825) gpsIfdOffset = int.tryParse(val);
        tags.add(ExifTagItem(
          category: 'Camera & Device',
          key: _getTagName(tagId),
          value: val,
        ));
      },
    );

    // Parse Exif sub-IFD
    if (exifIfdOffset != null && exifIfdOffset! < tiffData.length) {
      _parseIfd(
        bd: bd,
        tiffData: tiffData,
        offset: exifIfdOffset!,
        endian: endian,
        category: 'Capture Settings',
        onTag: (tagId, val) {
          if (tagId == 0x9003 && dateTime == null) dateTime = val;
          tags.add(ExifTagItem(
            category: 'Capture Settings',
            key: _getTagName(tagId),
            value: val,
          ));
        },
      );
    }

    // Parse GPS sub-IFD
    GpsCoordinates? gps;
    if (gpsIfdOffset != null && gpsIfdOffset! < tiffData.length) {
      String? latRef;
      List<double>? latDms;
      String? lngRef;
      List<double>? lngDms;
      double? altitude;

      _parseIfd(
        bd: bd,
        tiffData: tiffData,
        offset: gpsIfdOffset!,
        endian: endian,
        category: 'GPS Location',
        onTag: (tagId, val) {
          if (tagId == 0x0001) latRef = val.trim();
          if (tagId == 0x0003) lngRef = val.trim();
          if (tagId == 0x0002) latDms = _parseRationalList(val);
          if (tagId == 0x0004) lngDms = _parseRationalList(val);
          if (tagId == 0x0006) {
            final altParts = val.split('/');
            if (altParts.length == 2) {
              final n = double.tryParse(altParts[0]);
              final d = double.tryParse(altParts[1]);
              if (n != null && d != null && d != 0) altitude = n / d;
            }
          }

          tags.add(ExifTagItem(
            category: 'GPS Location',
            key: _getGpsTagName(tagId),
            value: val,
            isSensitive: true,
          ));
        },
      );

      if (latRef != null &&
          lngRef != null &&
          latDms != null &&
          lngDms != null &&
          latDms!.length == 3 &&
          lngDms!.length == 3) {
        final lat = _dmsToDecimal(latDms![0], latDms![1], latDms![2], latRef!);
        final lng = _dmsToDecimal(lngDms![0], lngDms![1], lngDms![2], lngRef!);
        gps = GpsCoordinates(latitude: lat, longitude: lng, altitude: altitude);
      }
    }

    return ParsedExifData(
      tags: tags,
      gps: gps,
      cameraMake: make,
      cameraModel: model,
      dateTimeOriginal: dateTime,
      software: software,
      hasSensitiveGps: gps != null,
    );
  }

  static void _parseIfd({
    required ByteData bd,
    required Uint8List tiffData,
    required int offset,
    required Endian endian,
    required String category,
    required void Function(int tagId, String value) onTag,
  }) {
    if (offset + 2 > tiffData.length) return;
    final count = bd.getUint16(offset, endian);
    int pos = offset + 2;

    for (int i = 0; i < count; i++) {
      if (pos + 12 > tiffData.length) break;
      final tagId = bd.getUint16(pos, endian);
      final type = bd.getUint16(pos + 2, endian);
      final count = bd.getUint32(pos + 4, endian);
      final valOrOffset = bd.getUint32(pos + 8, endian);

      String val = '';
      if (type == 2) {
        // ASCII String
        int strStart = count <= 4 ? pos + 8 : valOrOffset;
        if (strStart + count <= tiffData.length) {
          final strBytes = tiffData.sublist(strStart, strStart + count);
          val = String.fromCharCodes(strBytes.where((c) => c != 0)).trim();
        }
      } else if (type == 3) {
        // SHORT (16-bit)
        val = bd.getUint16(pos + 8, endian).toString();
      } else if (type == 4) {
        // LONG (32-bit)
        val = valOrOffset.toString();
      } else if (type == 5) {
        // RATIONAL (Two 32-bit uints: numerator / denominator)
        if (valOrOffset + 8 <= tiffData.length) {
          final num = bd.getUint32(valOrOffset, endian);
          final den = bd.getUint32(valOrOffset + 4, endian);
          val = den == 1 ? '$num' : '$num/$den';
        }
      }

      if (val.isNotEmpty) {
        onTag(tagId, val);
      }
      pos += 12;
    }
  }

  static double _dmsToDecimal(double d, double m, double s, String ref) {
    double dec = d + (m / 60.0) + (s / 3600.0);
    if (ref.toUpperCase() == 'S' || ref.toUpperCase() == 'W') {
      dec = -dec;
    }
    return dec;
  }

  static List<double>? _parseRationalList(String val) {
    try {
      final items = val.split(RegExp(r'[\s,]+'));
      final result = <double>[];
      for (final item in items) {
        if (item.contains('/')) {
          final parts = item.split('/');
          final n = double.tryParse(parts[0]);
          final d = double.tryParse(parts[1]);
          if (n != null && d != null && d != 0) result.add(n / d);
        } else {
          final d = double.tryParse(item);
          if (d != null) result.add(d);
        }
      }
      return result.isNotEmpty ? result : null;
    } catch (_) {
      return null;
    }
  }

  static String _getTagName(int id) {
    switch (id) {
      case 0x010F:
        return 'Camera Manufacturer';
      case 0x0110:
        return 'Camera Model';
      case 0x0112:
        return 'Orientation';
      case 0x011A:
        return 'X Resolution';
      case 0x011B:
        return 'Y Resolution';
      case 0x0128:
        return 'Resolution Unit';
      case 0x0131:
        return 'Software / Firmware';
      case 0x0132:
        return 'Modify Date';
      case 0x829A:
        return 'Exposure Time';
      case 0x829D:
        return 'F-Number (Aperture)';
      case 0x8822:
        return 'Exposure Program';
      case 0x8827:
        return 'ISO Speed';
      case 0x9003:
        return 'Date & Time Original';
      case 0x9004:
        return 'Date & Time Digitized';
      case 0x920A:
        return 'Focal Length';
      case 0xA002:
        return 'Pixel Width';
      case 0xA003:
        return 'Pixel Height';
      case 0xA405:
        return 'Focal Length (35mm eq)';
      default:
        return 'Tag 0x${id.toRadixString(16).toUpperCase()}';
    }
  }

  static String _getGpsTagName(int id) {
    switch (id) {
      case 0x0001:
        return 'GPS Latitude Ref';
      case 0x0002:
        return 'GPS Latitude';
      case 0x0003:
        return 'GPS Longitude Ref';
      case 0x0004:
        return 'GPS Longitude';
      case 0x0005:
        return 'GPS Altitude Ref';
      case 0x0006:
        return 'GPS Altitude';
      case 0x0007:
        return 'GPS TimeStamp';
      case 0x001D:
        return 'GPS DateStamp';
      default:
        return 'GPS Tag 0x${id.toRadixString(16).toUpperCase()}';
    }
  }

  /// Saves processed image bytes to device Download directory.
  static Future<String> saveImage({
    required Uint8List bytes,
    required String subFolder,
    required String baseName,
    required String extension,
  }) async {
    final downloadDir =
        Directory(p.join('/storage/emulated/0/Download', subFolder));
    if (!downloadDir.existsSync()) {
      downloadDir.createSync(recursive: true);
    }

    final safeBase = baseName.replaceAll(RegExp(r'[\\/:*?"<>| ]'), '_');
    final cleanExt = extension.replaceAll('.', '');
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final outPath = p.join(downloadDir.path, '${safeBase}_$timestamp.$cleanExt');

    final file = File(outPath);
    await file.writeAsBytes(bytes);
    return outPath;
  }
}
