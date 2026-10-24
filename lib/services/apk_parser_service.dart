import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// Model representing a single DEX file inside the APK.
class ApkDexInfo {
  final String name;
  final int size;
  final int compressedSize;

  ApkDexInfo({
    required this.name,
    required this.size,
    required this.compressedSize,
  });
}

/// Model representing a signing certificate found in META-INF.
class ApkCertInfo {
  final String fileName;
  final int size;
  final String md5Digest;
  final String sha1Digest;
  final String sha256Digest;

  ApkCertInfo({
    required this.fileName,
    required this.size,
    required this.md5Digest,
    required this.sha1Digest,
    required this.sha256Digest,
  });
}

/// Model representing an extracted Android permission with classification.
class ApkPermissionInfo {
  final String name;
  final bool isDangerous;
  final String description;

  ApkPermissionInfo({
    required this.name,
    required this.isDangerous,
    required this.description,
  });
}

/// Complete inspection data extracted from an APK.
class ApkInspectionResult {
  final String filePath;
  final String fileName;
  final int fileSize;
  final String appName;
  final String packageName;
  final String versionName;
  final int versionCode;
  final int minSdk;
  final int targetSdk;
  final List<ApkPermissionInfo> permissions;
  final List<String> activities;
  final List<String> services;
  final List<String> receivers;
  final List<String> providers;
  final List<ApkDexInfo> dexFiles;
  final Map<String, List<String>> nativeLibraries;
  final int totalAssetsCount;
  final int totalAssetsSize;
  final int resourcesArscSize;
  final int totalResFilesCount;
  final List<ApkCertInfo> certificates;
  final bool isSplitApk;
  final List<String> splitFilePaths;
  final String rawManifestSummary;

  ApkInspectionResult({
    required this.filePath,
    required this.fileName,
    required this.fileSize,
    required this.appName,
    required this.packageName,
    required this.versionName,
    required this.versionCode,
    required this.minSdk,
    required this.targetSdk,
    required this.permissions,
    required this.activities,
    required this.services,
    required this.receivers,
    required this.providers,
    required this.dexFiles,
    required this.nativeLibraries,
    required this.totalAssetsCount,
    required this.totalAssetsSize,
    required this.resourcesArscSize,
    required this.totalResFilesCount,
    required this.certificates,
    required this.isSplitApk,
    required this.splitFilePaths,
    required this.rawManifestSummary,
  });

  int get totalDexSize => dexFiles.fold(0, (sum, d) => sum + d.size);
  int get totalNativeLibsCount =>
      nativeLibraries.values.fold(0, (sum, libs) => sum + libs.length);
  List<String> get supportedAbis => nativeLibraries.keys.toList();
}

/// Internal helper model representing a ZIP entry from the Central Directory.
class _ZipEntry {
  final String name;
  final int method; // 0 = stored, 8 = deflate
  final int compressedSize;
  final int uncompressedSize;
  final int localHeaderOffset;

  _ZipEntry({
    required this.name,
    required this.method,
    required this.compressedSize,
    required this.uncompressedSize,
    required this.localHeaderOffset,
  });
}

class ApkParserService {
  /// Known dangerous Android permissions according to AOSP documentation.
  static final Set<String> _dangerousPermissions = {
    'android.permission.READ_CALENDAR',
    'android.permission.WRITE_CALENDAR',
    'android.permission.CAMERA',
    'android.permission.READ_CONTACTS',
    'android.permission.WRITE_CONTACTS',
    'android.permission.GET_ACCOUNTS',
    'android.permission.ACCESS_FINE_LOCATION',
    'android.permission.ACCESS_COARSE_LOCATION',
    'android.permission.ACCESS_BACKGROUND_LOCATION',
    'android.permission.RECORD_AUDIO',
    'android.permission.READ_PHONE_STATE',
    'android.permission.READ_PHONE_NUMBERS',
    'android.permission.CALL_PHONE',
    'android.permission.ANSWER_PHONE_CALLS',
    'android.permission.READ_CALL_LOG',
    'android.permission.WRITE_CALL_LOG',
    'android.permission.ADD_VOICEMAIL',
    'android.permission.USE_SIP',
    'android.permission.BODY_SENSORS',
    'android.permission.BODY_SENSORS_BACKGROUND',
    'android.permission.SEND_SMS',
    'android.permission.RECEIVE_SMS',
    'android.permission.READ_SMS',
    'android.permission.RECEIVE_WAP_PUSH',
    'android.permission.RECEIVE_MMS',
    'android.permission.READ_EXTERNAL_STORAGE',
    'android.permission.WRITE_EXTERNAL_STORAGE',
    'android.permission.MANAGE_EXTERNAL_STORAGE',
    'android.permission.POST_NOTIFICATIONS',
    'android.permission.NEARBY_WIFI_DEVICES',
    'android.permission.BLUETOOTH_SCAN',
    'android.permission.BLUETOOTH_CONNECT',
    'android.permission.BLUETOOTH_ADVERTISE',
  };

  /// Parses an APK file directly using low-memory Central Directory parsing.
  static Future<ApkInspectionResult> inspectApk(
    String apkPath, {
    String? fallbackAppName,
    List<String>? splitPaths,
  }) async {
    final file = File(apkPath);
    if (!file.existsSync()) {
      throw Exception('APK file does not exist at: $apkPath');
    }

    final fileSize = file.lengthSync();
    final fileName = p.basename(apkPath);

    RandomAccessFile? raf;
    try {
      raf = file.openSync(mode: FileMode.read);
      final entries = _readZipCentralDirectory(raf, fileSize);

      // Structure analysis
      final dexList = <ApkDexInfo>[];
      final nativeLibs = <String, List<String>>{};
      int assetsCount = 0;
      int assetsSize = 0;
      int resCount = 0;
      int arscSize = 0;
      final certList = <ApkCertInfo>[];

      _ZipEntry? manifestEntry;
      final certEntries = <_ZipEntry>[];

      for (final entry in entries) {
        if (entry.name == 'AndroidManifest.xml') {
          manifestEntry = entry;
        } else if (entry.name.endsWith('.dex')) {
          dexList.add(ApkDexInfo(
            name: entry.name,
            size: entry.uncompressedSize,
            compressedSize: entry.compressedSize,
          ));
        } else if (entry.name.startsWith('lib/')) {
          final parts = entry.name.split('/');
          if (parts.length >= 3) {
            final abi = parts[1];
            final libName = parts.sublist(2).join('/');
            nativeLibs.putIfAbsent(abi, () => []).add(libName);
          }
        } else if (entry.name.startsWith('assets/')) {
          assetsCount++;
          assetsSize += entry.uncompressedSize;
        } else if (entry.name.startsWith('res/')) {
          resCount++;
        } else if (entry.name == 'resources.arsc') {
          arscSize = entry.uncompressedSize;
        } else if (entry.name.startsWith('META-INF/') &&
            (entry.name.endsWith('.RSA') ||
                entry.name.endsWith('.DSA') ||
                entry.name.endsWith('.EC') ||
                entry.name.endsWith('.SF'))) {
          certEntries.add(entry);
        }
      }

      // Sort dex files by name (classes.dex, classes2.dex, etc.)
      dexList.sort((a, b) => a.name.compareTo(b.name));

      // Extract certificates
      for (final certEntry in certEntries) {
        try {
          final certBytes = _extractEntryData(raf, certEntry);
          final md5Hash = md5.convert(certBytes).toString().toUpperCase();
          final sha1Hash = sha1.convert(certBytes).toString().toUpperCase();
          final sha256Hash = sha256.convert(certBytes).toString().toUpperCase();
          certList.add(ApkCertInfo(
            fileName: p.basename(certEntry.name),
            size: certEntry.uncompressedSize,
            md5Digest: md5Hash,
            sha1Digest: sha1Hash,
            sha256Digest: sha256Hash,
          ));
        } catch (e) {
          debugPrint('Error extracting cert ${certEntry.name}: $e');
        }
      }

      // Decompress and parse AndroidManifest.xml
      _ManifestData manifestData;
      if (manifestEntry != null) {
        final manifestBytes = _extractEntryData(raf, manifestEntry);
        manifestData = _parseBinaryManifest(manifestBytes);
      } else {
        manifestData = _ManifestData.empty();
      }

      // Classify permissions
      final permissionInfos = manifestData.permissions.map((perm) {
        final isDangerous = _dangerousPermissions.contains(perm);
        return ApkPermissionInfo(
          name: perm,
          isDangerous: isDangerous,
          description: _getPermissionDescription(perm),
        );
      }).toList();

      final splits = splitPaths ?? [];
      final isSplit = splits.isNotEmpty || fileName.contains('split');

      return ApkInspectionResult(
        filePath: apkPath,
        fileName: fileName,
        fileSize: fileSize,
        appName: fallbackAppName ?? manifestData.appName.ifEmpty(fileName),
        packageName: manifestData.packageName.ifEmpty('Unknown Package'),
        versionName: manifestData.versionName.ifEmpty('1.0'),
        versionCode: manifestData.versionCode,
        minSdk: manifestData.minSdk,
        targetSdk: manifestData.targetSdk,
        permissions: permissionInfos,
        activities: manifestData.activities,
        services: manifestData.services,
        receivers: manifestData.receivers,
        providers: manifestData.providers,
        dexFiles: dexList,
        nativeLibraries: nativeLibs,
        totalAssetsCount: assetsCount,
        totalAssetsSize: assetsSize,
        resourcesArscSize: arscSize,
        totalResFilesCount: resCount,
        certificates: certList,
        isSplitApk: isSplit,
        splitFilePaths: splits,
        rawManifestSummary: manifestData.rawSummary,
      );
    } finally {
      raf?.closeSync();
    }
  }

  /// Extracts single base APK to a target directory.
  static Future<String> extractBaseApk({
    required String sourceApkPath,
    required String targetDirPath,
    required String appName,
    required String version,
  }) async {
    final targetDir = Directory(targetDirPath);
    if (!targetDir.existsSync()) {
      targetDir.createSync(recursive: true);
    }

    final safeAppName = appName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final safeVersion = version.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final outPath = p.join(targetDir.path, '${safeAppName}_v$safeVersion.apk');

    final sourceFile = File(sourceApkPath);
    await sourceFile.copy(outPath);
    return outPath;
  }

  /// Extracts base APK and all split APKs into a bundled .apks or directory.
  static Future<String> extractSplitApks({
    required String baseApkPath,
    required List<String> splitPaths,
    required String targetDirPath,
    required String appName,
    required String version,
  }) async {
    final targetDir = Directory(targetDirPath);
    if (!targetDir.existsSync()) {
      targetDir.createSync(recursive: true);
    }

    final safeAppName = appName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final safeVersion = version.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final outBundlePath =
        p.join(targetDir.path, '${safeAppName}_v$safeVersion.apks');

    final encoder = ZipFileEncoder();
    encoder.create(outBundlePath);

    // Add base.apk
    final baseFile = File(baseApkPath);
    if (baseFile.existsSync()) {
      encoder.addFile(baseFile, 'base.apk');
    }

    // Add splits
    for (final split in splitPaths) {
      final sFile = File(split);
      if (sFile.existsSync()) {
        encoder.addFile(sFile, p.basename(split));
      }
    }
    encoder.close();

    return outBundlePath;
  }

  // -------------------------------------------------------------
  // ZIP Central Directory Engine (Reads headers in ~5ms without OOM)
  // -------------------------------------------------------------

  static List<_ZipEntry> _readZipCentralDirectory(
      RandomAccessFile raf, int fileSize) {
    // Search for End of Central Directory Record (0x06054b50) in last 64KB
    final searchLength = fileSize < 65557 ? fileSize : 65557;
    raf.setPositionSync(fileSize - searchLength);
    final searchBuf = raf.readSync(searchLength);

    int eocdOffset = -1;
    for (int i = searchLength - 22; i >= 0; i--) {
      if (searchBuf[i] == 0x50 &&
          searchBuf[i + 1] == 0x4b &&
          searchBuf[i + 2] == 0x05 &&
          searchBuf[i + 3] == 0x06) {
        eocdOffset = fileSize - searchLength + i;
        break;
      }
    }

    if (eocdOffset == -1) {
      throw Exception('Invalid APK file: End of Central Directory not found.');
    }

    raf.setPositionSync(eocdOffset);
    final eocdBuf = raf.readSync(22);
    final byteData = ByteData.sublistView(eocdBuf);

    final totalEntries = byteData.getUint16(10, Endian.little);
    final cdSize = byteData.getUint32(12, Endian.little);
    final cdOffset = byteData.getUint32(16, Endian.little);

    raf.setPositionSync(cdOffset);
    final cdBuf = raf.readSync(cdSize);
    final cdData = ByteData.sublistView(cdBuf);

    final entries = <_ZipEntry>[];
    int pos = 0;
    while (pos < cdSize) {
      if (pos + 46 > cdSize) break;
      final sig = cdData.getUint32(pos, Endian.little);
      if (sig != 0x02014b50) break;

      final method = cdData.getUint16(pos + 10, Endian.little);
      final compSize = cdData.getUint32(pos + 20, Endian.little);
      final uncompSize = cdData.getUint32(pos + 24, Endian.little);
      final nameLen = cdData.getUint16(pos + 28, Endian.little);
      final extraLen = cdData.getUint16(pos + 30, Endian.little);
      final commentLen = cdData.getUint16(pos + 32, Endian.little);
      final localOffset = cdData.getUint32(pos + 42, Endian.little);

      final nameBytes = cdBuf.sublist(pos + 46, pos + 46 + nameLen);
      final name = utf8.decode(nameBytes, allowMalformed: true);

      entries.add(_ZipEntry(
        name: name,
        method: method,
        compressedSize: compSize,
        uncompressedSize: uncompSize,
        localHeaderOffset: localOffset,
      ));

      pos += 46 + nameLen + extraLen + commentLen;
    }

    return entries;
  }

  /// Extracts and decompresses only the specific ZIP entry from the APK.
  static Uint8List _extractEntryData(RandomAccessFile raf, _ZipEntry entry) {
    raf.setPositionSync(entry.localHeaderOffset);
    final headerBuf = raf.readSync(30);
    final hData = ByteData.sublistView(headerBuf);

    final nameLen = hData.getUint16(26, Endian.little);
    final extraLen = hData.getUint16(28, Endian.little);
    final dataOffset = entry.localHeaderOffset + 30 + nameLen + extraLen;

    raf.setPositionSync(dataOffset);
    final compBytes = raf.readSync(entry.compressedSize);

    if (entry.method == 0) {
      // Stored (no compression)
      return compBytes;
    } else if (entry.method == 8) {
      // Raw Deflate (RFC 1951)
      try {
        final decoded = const ZLibDecoder(raw: true).convert(compBytes);
        return Uint8List.fromList(decoded);
      } catch (_) {
        // Fallback to archive's Inflate
        final inflated = Inflate(compBytes).getBytes();
        return Uint8List.fromList(inflated);
      }
    } else {
      throw Exception('Unsupported compression method: ${entry.method}');
    }
  }

  // -------------------------------------------------------------
  // Binary AndroidManifest.xml (AXML) Parser
  // -------------------------------------------------------------

  static _ManifestData _parseBinaryManifest(Uint8List bytes) {
    if (bytes.length < 8) return _ManifestData.empty();
    final data = ByteData.sublistView(bytes);

    // Root chunk header
    final rootType = data.getUint16(0, Endian.little);
    if (rootType != 0x0003) {
      // Not RES_XML_TYPE, try fallback plain text parsing if present
      return _ManifestData.empty();
    }

    // String Pool Chunk starts at offset 8
    if (bytes.length < 36) return _ManifestData.empty();
    final poolType = data.getUint16(8, Endian.little);
    if (poolType != 0x0001) return _ManifestData.empty();

    final poolChunkSize = data.getUint32(12, Endian.little);
    final stringCount = data.getUint32(16, Endian.little);
    final styleCount = data.getUint32(20, Endian.little);
    final flags = data.getUint32(24, Endian.little);
    final stringsStart = data.getUint32(28, Endian.little);
    final isUtf8 = (flags & (1 << 8)) != 0;

    final strings = <String>[];
    final offsetsStart = 8 + 28 + (styleCount > 0 ? 4 : 0);

    for (int i = 0; i < stringCount; i++) {
      final strOffset = data.getUint32(offsetsStart + i * 4, Endian.little);
      final actualStart = 8 + stringsStart + strOffset;

      if (actualStart >= bytes.length) {
        strings.add('');
        continue;
      }

      if (!isUtf8) {
        // UTF-16LE
        int len = data.getUint16(actualStart, Endian.little);
        int charOffset = actualStart + 2;
        if ((len & 0x8000) != 0) {
          len = ((len & 0x7fff) << 16) |
              data.getUint16(charOffset, Endian.little);
          charOffset += 2;
        }
        final end = charOffset + len * 2;
        if (end <= bytes.length) {
          final strBytes = bytes.sublist(charOffset, end);
          strings.add(String.fromCharCodes(Uint16List.view(
            strBytes.buffer,
            strBytes.offsetInBytes,
            len,
          )));
        } else {
          strings.add('');
        }
      } else {
        // UTF-8
        int charLen = bytes[actualStart];
        int byteOffset = actualStart + 1;
        if ((charLen & 0x80) != 0) byteOffset++;
        int byteLen = bytes[byteOffset];
        byteOffset++;
        if ((byteLen & 0x80) != 0) byteOffset++;

        final end = byteOffset + byteLen;
        if (end <= bytes.length) {
          strings.add(utf8.decode(bytes.sublist(byteOffset, end),
              allowMalformed: true));
        } else {
          strings.add('');
        }
      }
    }

    // Walk XML elements starting after the string pool
    int offset = 8 + poolChunkSize;
    String? packageName;
    String? versionName;
    int versionCode = 0;
    int minSdk = 0;
    int targetSdk = 0;
    String? appLabel;

    final permissions = <String>{};
    final activities = <String>[];
    final services = <String>[];
    final receivers = <String>[];
    final providers = <String>[];

    final summaryLines = <String>[];

    while (offset + 8 <= bytes.length) {
      final chunkType = data.getUint16(offset, Endian.little);
      final chunkSize = data.getUint32(offset + 4, Endian.little);
      if (chunkSize <= 0 || offset + chunkSize > bytes.length) break;

      if (chunkType == 0x0102) {
        // RES_XML_START_ELEMENT_TYPE
        if (offset + 36 <= bytes.length) {
          final tagIndex = data.getUint32(offset + 20, Endian.little);
          final attrCount = data.getUint16(offset + 28, Endian.little);
          final tagName = tagIndex < strings.length ? strings[tagIndex] : '';

          final attrs = <String, String>{};
          for (int a = 0; a < attrCount; a++) {
            final aOff = offset + 36 + a * 20;
            if (aOff + 20 > bytes.length) break;

            final attrNameIdx = data.getUint32(aOff + 4, Endian.little);
            final attrRawValIdx = data.getInt32(aOff + 8, Endian.little);
            final dataType = bytes[aOff + 15];
            final dataVal = data.getUint32(aOff + 16, Endian.little);

            final attrName =
                attrNameIdx < strings.length ? strings[attrNameIdx] : 'attr_$a';
            String val = '';
            if (attrRawValIdx >= 0 && attrRawValIdx < strings.length) {
              val = strings[attrRawValIdx];
            } else {
              if (dataType == 0x10 || dataType == 0x11) {
                val = dataVal.toString();
              } else if (dataType == 0x12) {
                val = dataVal != 0 ? 'true' : 'false';
              } else if (dataType == 0x03 && dataVal < strings.length) {
                val = strings[dataVal];
              } else {
                val = dataVal.toString();
              }
            }
            attrs[attrName] = val;
          }

          if (tagName == 'manifest') {
            packageName = attrs['package'] ?? packageName;
            versionName = attrs['versionName'] ?? versionName;
            if (attrs.containsKey('versionCode')) {
              versionCode = int.tryParse(attrs['versionCode']!) ?? versionCode;
            }
          } else if (tagName == 'uses-sdk') {
            if (attrs.containsKey('minSdkVersion')) {
              minSdk = int.tryParse(attrs['minSdkVersion']!) ?? minSdk;
            }
            if (attrs.containsKey('targetSdkVersion')) {
              targetSdk = int.tryParse(attrs['targetSdkVersion']!) ?? targetSdk;
            }
          } else if (tagName == 'uses-permission' ||
              tagName == 'uses-permission-sdk-23') {
            final pName = attrs['name'];
            if (pName != null && pName.isNotEmpty) {
              permissions.add(pName);
            }
          } else if (tagName == 'application') {
            appLabel = attrs['label'] ?? appLabel;
          } else if (tagName == 'activity' || tagName == 'activity-alias') {
            final aName = attrs['name'];
            if (aName != null && aName.isNotEmpty) activities.add(aName);
          } else if (tagName == 'service') {
            final sName = attrs['name'];
            if (sName != null && sName.isNotEmpty) services.add(sName);
          } else if (tagName == 'receiver') {
            final rName = attrs['name'];
            if (rName != null && rName.isNotEmpty) receivers.add(rName);
          } else if (tagName == 'provider') {
            final prName = attrs['name'];
            if (prName != null && prName.isNotEmpty) providers.add(prName);
          }
        }
      }
      offset += chunkSize;
    }

    // Fallback: If permissions or package not captured through elements,
    // search through all extracted strings for permissions & package hints
    for (final str in strings) {
      if (str.startsWith('android.permission.') ||
          str.startsWith('com.android.') && str.contains('.permission.')) {
        permissions.add(str);
      }
      if (packageName == null &&
          RegExp(r'^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$').hasMatch(str) &&
          !str.startsWith('android.') &&
          !str.startsWith('http')) {
        packageName = str;
      }
    }

    final summary = StringBuffer();
    summary.writeln('<manifest package="${packageName ?? ''}"');
    summary.writeln('    android:versionCode="$versionCode"');
    summary.writeln('    android:versionName="${versionName ?? '1.0'}">');
    summary.writeln('    <uses-sdk android:minSdkVersion="$minSdk"');
    summary.writeln('              android:targetSdkVersion="$targetSdk" />');
    for (final perm in permissions) {
      summary.writeln('    <uses-permission android:name="$perm" />');
    }
    summary.writeln('</manifest>');

    return _ManifestData(
      appName: appLabel ?? '',
      packageName: packageName ?? '',
      versionName: versionName ?? '1.0',
      versionCode: versionCode,
      minSdk: minSdk,
      targetSdk: targetSdk,
      permissions: permissions.toList()..sort(),
      activities: activities,
      services: services,
      receivers: receivers,
      providers: providers,
      rawSummary: summary.toString(),
    );
  }

  static String _getPermissionDescription(String perm) {
    if (perm.contains('CAMERA')) return 'Take pictures and record video';
    if (perm.contains('RECORD_AUDIO')) return 'Record audio / microphone';
    if (perm.contains('ACCESS_FINE_LOCATION')) {
      return 'Precise GPS location access';
    }
    if (perm.contains('ACCESS_COARSE_LOCATION')) {
      return 'Approximate network location';
    }
    if (perm.contains('READ_CONTACTS')) return 'Read contacts and address book';
    if (perm.contains('WRITE_CONTACTS')) return 'Modify or add new contacts';
    if (perm.contains('READ_EXTERNAL_STORAGE')) {
      return 'Read files from device storage';
    }
    if (perm.contains('WRITE_EXTERNAL_STORAGE')) {
      return 'Modify or delete storage files';
    }
    if (perm.contains('MANAGE_EXTERNAL_STORAGE')) {
      return 'All files access permission';
    }
    if (perm.contains('SEND_SMS') || perm.contains('READ_SMS')) {
      return 'Send or view SMS text messages';
    }
    if (perm.contains('READ_PHONE_STATE')) {
      return 'Access phone status and identity';
    }
    if (perm.contains('INTERNET')) return 'Full network / internet access';
    if (perm.contains('POST_NOTIFICATIONS')) {
      return 'Display system notifications';
    }
    if (perm.contains('BLUETOOTH')) return 'Scan or pair Bluetooth devices';
    if (perm.contains('WAKE_LOCK')) return 'Prevent device from sleeping';
    if (perm.contains('VIBRATE')) return 'Control device vibration';
    return 'System & application permission';
  }
}

class _ManifestData {
  final String appName;
  final String packageName;
  final String versionName;
  final int versionCode;
  final int minSdk;
  final int targetSdk;
  final List<String> permissions;
  final List<String> activities;
  final List<String> services;
  final List<String> receivers;
  final List<String> providers;
  final String rawSummary;

  _ManifestData({
    required this.appName,
    required this.packageName,
    required this.versionName,
    required this.versionCode,
    required this.minSdk,
    required this.targetSdk,
    required this.permissions,
    required this.activities,
    required this.services,
    required this.receivers,
    required this.providers,
    required this.rawSummary,
  });

  factory _ManifestData.empty() => _ManifestData(
        appName: '',
        packageName: '',
        versionName: '1.0',
        versionCode: 0,
        minSdk: 0,
        targetSdk: 0,
        permissions: [],
        activities: [],
        services: [],
        receivers: [],
        providers: [],
        rawSummary: '',
      );
}

extension _StringHelper on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}
