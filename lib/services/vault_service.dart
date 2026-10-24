import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as p;
import 'package:archive/archive.dart';
import 'encryption/aes_256_service.dart';

class VaultFileRecord {
  final String id;
  final String originalName;
  final String originalPath;
  final String scrambledPath;
  final int size;
  final String lockedAt;
  final bool isInPlace;
  final bool isFolder;

  VaultFileRecord({
    required this.id,
    required this.originalName,
    required this.originalPath,
    required this.scrambledPath,
    required this.size,
    required this.lockedAt,
    required this.isInPlace,
    this.isFolder = false,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'originalName': originalName,
    'originalPath': originalPath,
    'scrambledPath': scrambledPath,
    'size': size,
    'lockedAt': lockedAt,
    'isInPlace': isInPlace,
    'isFolder': isFolder,
  };

  factory VaultFileRecord.fromJson(Map<String, dynamic> json) => VaultFileRecord(
    id: json['id'] as String,
    originalName: json['originalName'] as String,
    originalPath: json['originalPath'] as String,
    scrambledPath: json['scrambledPath'] as String,
    size: json['size'] as int,
    lockedAt: json['lockedAt'] as String,
    isInPlace: json['isInPlace'] as bool,
    isFolder: json['isFolder'] as bool? ?? false,
  );
}

class VaultService {
  static const String _magicTagV1 = 'NFILE_VAULT_V1';
  static const String _magicTagV2 = 'NFILE_VAULT_V2'; // AES-256
  static const int _scrambleSize = 16384; // 16 KB

  // Hashing and Password Management
  static Future<bool> isPasswordSet() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey('vault_password_hash');
  }

  static Future<void> setPassword(String password) async {
    final prefs = await SharedPreferences.getInstance();
    final salt = DateTime.now().microsecondsSinceEpoch.toString();
    final saltedPassword = password + salt;
    final hash = sha256.convert(utf8.encode(saltedPassword)).toString();
    await prefs.setString('vault_salt', salt);
    await prefs.setString('vault_password_hash', hash);
    await storeBiometricKey(password);
  }

  static Future<bool> verifyPassword(String password) async {
    final prefs = await SharedPreferences.getInstance();
    final salt = prefs.getString('vault_salt');
    final hash = prefs.getString('vault_password_hash');
    if (salt == null || hash == null) return false;
    final checkHash = sha256.convert(utf8.encode(password + salt)).toString();
    final isValid = hash == checkHash;
    if (isValid) {
      await storeBiometricKey(password);
    }
    return isValid;
  }

  // Biometric Authentication Settings & Key Storage
  static Future<bool> isBiometricEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('vault_biometric_enabled') ?? true;
  }

  static Future<void> setBiometricEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('vault_biometric_enabled', enabled);
  }

  static Future<void> storeBiometricKey(String password) async {
    final prefs = await SharedPreferences.getInstance();
    // Obfuscate stored pin with device salt
    final salt = prefs.getString('vault_salt') ?? 'NFYLO_BIO_SALT';
    final encBytes = Aes256.processCtr(
      input: Uint8List.fromList(utf8.encode(password)),
      key: sha256.convert(utf8.encode('BIO_$salt')).bytes as Uint8List,
      iv: Uint8List(16),
    );
    await prefs.setString('vault_bio_key', base64Encode(encBytes));
  }

  static Future<String?> getBiometricKey() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = prefs.getString('vault_bio_key');
    if (encoded == null) return null;
    final salt = prefs.getString('vault_salt') ?? 'NFYLO_BIO_SALT';
    final encBytes = base64Decode(encoded);
    final decBytes = Aes256.processCtr(
      input: Uint8List.fromList(encBytes),
      key: sha256.convert(utf8.encode('BIO_$salt')).bytes as Uint8List,
      iv: Uint8List(16),
    );
    return utf8.decode(decBytes);
  }

  // Get Vault Directory
  static Future<Directory> getVaultDir() async {
    final docDir = await getApplicationDocumentsDirectory();
    final vaultDir = Directory(p.join(docDir.path, 'vault'));
    if (!await vaultDir.exists()) {
      await vaultDir.create(recursive: true);
    }
    return vaultDir;
  }

  // Get Metadata JSON File path
  static Future<File> getMetadataFile() async {
    final vaultDir = await getVaultDir();
    return File(p.join(vaultDir.path, 'metadata.json'));
  }

  // Load locked file records
  static Future<List<VaultFileRecord>> loadRecords() async {
    final file = await getMetadataFile();
    if (!await file.exists()) return [];
    try {
      final str = await file.readAsString();
      final list = jsonDecode(str) as List;
      return list.map((e) => VaultFileRecord.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  // Save locked file records
  static Future<void> saveRecords(List<VaultFileRecord> records) async {
    final file = await getMetadataFile();
    final str = jsonEncode(records.map((e) => e.toJson()).toList());
    await file.writeAsString(str);
  }

  // Legacy V1 XOR key derivation
  static List<int> _deriveKeyV1(String password, int length) {
    final hash = sha256.convert(utf8.encode(password)).bytes;
    final key = List<int>.filled(length, 0);
    for (int i = 0; i < length; i++) {
      key[i] = hash[i % hash.length] ^ (i & 0xFF);
    }
    return key;
  }

  static List<int> _xorBytes(List<int> bytes, List<int> key) {
    final result = List<int>.from(bytes);
    for (int i = 0; i < bytes.length; i++) {
      result[i] = bytes[i] ^ key[i % key.length];
    }
    return result;
  }

  // AES-256 Vault Encryption (V2)
  static Future<VaultFileRecord> lockFile({
    required File file,
    required String password,
    required bool inPlace,
    String? customName,
    String? customPath,
    bool isFolder = false,
  }) async {
    if (!await file.exists()) {
      throw Exception('File does not exist: ${file.path}');
    }

    final originalPath = customPath ?? file.path;
    final originalName = customName ?? p.basename(originalPath);
    final size = await file.length();
    final timestamp = DateTime.now().millisecondsSinceEpoch.toString();

    String scrambledPath;
    if (inPlace) {
      final dir = isFolder ? originalPath : p.dirname(originalPath);
      scrambledPath = p.join(dir, '.vault_$timestamp.nfv');
    } else {
      final vaultDir = await getVaultDir();
      scrambledPath = p.join(vaultDir.path, 'vault_$timestamp.nfv');
    }

    final fileBytes = await file.readAsBytes();

    // 16-byte random salt and 16-byte random IV
    final rand = Random.secure();
    final salt = Uint8List(16);
    final iv = Uint8List(16);
    for (int i = 0; i < 16; i++) {
      salt[i] = rand.nextInt(256);
      iv[i] = rand.nextInt(256);
    }

    // Derive 256-bit AES key
    final aesKey = Aes256FileEncryptor.deriveKey(password, salt);

    // Partition bytes for signature encryption
    final scrambleLen = min(_scrambleSize, fileBytes.length);
    final scrambleBytes = Uint8List.fromList(fileBytes.sublist(0, scrambleLen));
    final restBytes = fileBytes.sublist(scrambleLen);

    // AES-256-CTR encrypt the signature part
    final encryptedSignature = Aes256.processCtr(
      input: scrambleBytes,
      key: aesKey,
      iv: iv,
    );

    // Build metadata payload
    final metadata = {
      'name': originalName,
      'path': originalPath,
      'size': size,
      'timestamp': timestamp,
      'isFolder': isFolder,
    };
    final metadataStr = jsonEncode(metadata);
    final metadataBytes = Uint8List.fromList(utf8.encode(metadataStr));

    // AES-256-CTR encrypt metadata payload
    final encryptedMetadata = Aes256.processCtr(
      input: metadataBytes,
      key: aesKey,
      iv: iv,
    );

    // Create the scrambled file format (V2):
    // [MAGIC_TAG_V2] (14 bytes)
    // [SALT] (16 bytes)
    // [IV] (16 bytes)
    // [METADATA_LENGTH] (4 bytes int)
    // [ENCRYPTED_METADATA]
    // [ENCRYPTED_SIGNATURE]
    // [REST_OF_FILE]
    final headerBytes = BytesBuilder();
    headerBytes.add(utf8.encode(_magicTagV2));
    headerBytes.add(salt);
    headerBytes.add(iv);

    final metaLen = encryptedMetadata.length;
    headerBytes.add([
      (metaLen >> 24) & 0xFF,
      (metaLen >> 16) & 0xFF,
      (metaLen >> 8) & 0xFF,
      metaLen & 0xFF,
    ]);

    headerBytes.add(encryptedMetadata);
    headerBytes.add(encryptedSignature);
    headerBytes.add(restBytes);

    final targetFile = File(scrambledPath);
    await targetFile.writeAsBytes(headerBytes.toBytes());

    await file.delete();

    final record = VaultFileRecord(
      id: timestamp,
      originalName: originalName,
      originalPath: originalPath,
      scrambledPath: scrambledPath,
      size: size,
      lockedAt: DateTime.now().toIso8601String(),
      isInPlace: inPlace,
      isFolder: isFolder,
    );

    final records = await loadRecords();
    records.add(record);
    await saveRecords(records);

    return record;
  }

  // Unlocks and restores a vault file (Supports both V2 AES-256 and V1 legacy)
  static Future<File> unlockFile({
    required VaultFileRecord record,
    required String password,
  }) async {
    final scrambledFile = File(record.scrambledPath);
    if (!await scrambledFile.exists()) {
      throw Exception('Scrambled vault file not found: ${record.scrambledPath}');
    }

    final bytes = await scrambledFile.readAsBytes();
    if (bytes.length < 18) {
      throw Exception('Invalid vault file format (Too short)');
    }

    final magicBytes = bytes.sublist(0, 14);
    final magic = utf8.decode(magicBytes, allowMalformed: true);

    BytesBuilder originalBytes = BytesBuilder();

    if (magic == _magicTagV2) {
      // -------------------------------------------------------------
      // V2: AES-256 Encryption
      // -------------------------------------------------------------
      final salt = Uint8List.fromList(bytes.sublist(14, 30));
      final iv = Uint8List.fromList(bytes.sublist(30, 46));
      final lenBytes = bytes.sublist(46, 50);
      final metaLen = (lenBytes[0] << 24) | (lenBytes[1] << 16) | (lenBytes[2] << 8) | lenBytes[3];

      final metaStart = 50;
      final metaEnd = metaStart + metaLen;
      if (bytes.length < metaEnd) {
        throw Exception('Invalid vault file format (Corrupted header)');
      }
      final encryptedMeta = Uint8List.fromList(bytes.sublist(metaStart, metaEnd));

      final aesKey = Aes256FileEncryptor.deriveKey(password, salt);
      final decryptedMetaBytes = Aes256.processCtr(
        input: encryptedMeta,
        key: aesKey,
        iv: iv,
      );

      Map<String, dynamic> metadata;
      try {
        final metaStr = utf8.decode(decryptedMetaBytes);
        metadata = jsonDecode(metaStr) as Map<String, dynamic>;
      } catch (_) {
        throw Exception('Incorrect PIN / password or corrupted vault file');
      }

      final fileDataStart = metaEnd;
      final originalSize = metadata['size'] as int;
      final scrambleLen = min(_scrambleSize, originalSize);

      if (bytes.length < fileDataStart + scrambleLen) {
        throw Exception('Invalid vault file format (Corrupted payload)');
      }
      final encryptedSignature = Uint8List.fromList(bytes.sublist(fileDataStart, fileDataStart + scrambleLen));
      final restBytes = bytes.sublist(fileDataStart + scrambleLen);

      final decryptedSignature = Aes256.processCtr(
        input: encryptedSignature,
        key: aesKey,
        iv: iv,
      );

      originalBytes.add(decryptedSignature);
      originalBytes.add(restBytes);
    } else if (magic == _magicTagV1) {
      // -------------------------------------------------------------
      // V1: Legacy XOR Obfuscation (Backwards Compatibility)
      // -------------------------------------------------------------
      final lenBytes = bytes.sublist(14, 18);
      final metaLen = (lenBytes[0] << 24) | (lenBytes[1] << 16) | (lenBytes[2] << 8) | lenBytes[3];
      final metaStart = 18;
      final metaEnd = metaStart + metaLen;
      final obfuscatedMetadata = bytes.sublist(metaStart, metaEnd);

      final metaKey = _deriveKeyV1(password, obfuscatedMetadata.length);
      final decryptedMetadataBytes = _xorBytes(obfuscatedMetadata, metaKey);

      Map<String, dynamic> metadata;
      try {
        final decryptedMetadataStr = utf8.decode(decryptedMetadataBytes);
        metadata = jsonDecode(decryptedMetadataStr) as Map<String, dynamic>;
      } catch (_) {
        throw Exception('Incorrect PIN or corrupted file');
      }

      final fileDataStart = metaEnd;
      final originalSize = metadata['size'] as int;
      final scrambleLen = min(8192, originalSize);

      final obfuscatedSignature = bytes.sublist(fileDataStart, fileDataStart + scrambleLen);
      final restBytes = bytes.sublist(fileDataStart + scrambleLen);

      final key = _deriveKeyV1(password, scrambleLen);
      final decryptedSignature = _xorBytes(obfuscatedSignature, key);

      originalBytes.add(decryptedSignature);
      originalBytes.add(restBytes);
    } else {
      throw Exception('Unrecognized vault file format ($magic)');
    }

    final originalFile = File(record.originalPath);

    if (record.isFolder) {
      final archive = ZipDecoder().decodeBytes(originalBytes.toBytes());
      final destinationDir = p.dirname(record.originalPath);

      for (final file in archive) {
        final filename = file.name;
        final fullPath = p.join(destinationDir, filename);
        if (file.isFile) {
          final data = file.content as List<int>;
          final destFile = File(fullPath);
          await destFile.parent.create(recursive: true);
          await destFile.writeAsBytes(data);
        } else {
          await Directory(fullPath).create(recursive: true);
        }
      }
    } else {
      final originalDir = originalFile.parent;
      if (!await originalDir.exists()) {
        await originalDir.create(recursive: true);
      }
      await originalFile.writeAsBytes(originalBytes.toBytes());
    }

    await scrambledFile.delete();

    final records = await loadRecords();
    records.removeWhere((e) => e.id == record.id);
    await saveRecords(records);

    return originalFile;
  }

  static Future<VaultFileRecord> lockDirectory({
    required Directory directory,
    required String password,
    required bool inPlace,
  }) async {
    if (!await directory.exists()) {
      throw Exception('Directory does not exist: ${directory.path}');
    }

    final originalPath = directory.path;
    final originalName = p.basename(originalPath);

    final list = directory.listSync(recursive: true);
    final archive = Archive();

    for (final entity in list) {
      if (entity is File) {
        final relPath = p.relative(entity.path, from: p.dirname(originalPath)).replaceAll('\\', '/');
        final bytes = await entity.readAsBytes();
        archive.addFile(ArchiveFile(relPath, bytes.length, bytes));
      }
    }

    final zipBytes = ZipEncoder().encode(archive);
    if (zipBytes == null) {
      throw Exception('Failed to zip directory contents');
    }

    final tempDir = await getTemporaryDirectory();
    final tempZipFile = File(p.join(tempDir.path, 'temp_vault_zip_${DateTime.now().millisecondsSinceEpoch}.zip'));
    await tempZipFile.writeAsBytes(zipBytes);

    try {
      final record = await lockFile(
        file: tempZipFile,
        password: password,
        inPlace: inPlace,
        customName: originalName,
        customPath: originalPath,
        isFolder: true,
      );

      if (inPlace) {
        final children = directory.listSync();
        for (final child in children) {
          if (child.path != record.scrambledPath) {
            await child.delete(recursive: true);
          }
        }
      } else {
        await directory.delete(recursive: true);
      }

      return record;
    } finally {
      if (await tempZipFile.exists()) {
        await tempZipFile.delete();
      }
    }
  }

  static Future<File> decryptTemporary({
    required VaultFileRecord record,
    required String password,
  }) async {
    final scrambledFile = File(record.scrambledPath);
    if (!await scrambledFile.exists()) {
      throw Exception('Scrambled vault file not found');
    }

    final bytes = await scrambledFile.readAsBytes();
    final magicBytes = bytes.sublist(0, 14);
    final magic = utf8.decode(magicBytes, allowMalformed: true);

    BytesBuilder originalBytes = BytesBuilder();

    if (magic == _magicTagV2) {
      final salt = Uint8List.fromList(bytes.sublist(14, 30));
      final iv = Uint8List.fromList(bytes.sublist(30, 46));
      final lenBytes = bytes.sublist(46, 50);
      final metaLen = (lenBytes[0] << 24) | (lenBytes[1] << 16) | (lenBytes[2] << 8) | lenBytes[3];

      final metaStart = 50;
      final metaEnd = metaStart + metaLen;
      final encryptedMeta = Uint8List.fromList(bytes.sublist(metaStart, metaEnd));

      final aesKey = Aes256FileEncryptor.deriveKey(password, salt);
      final decryptedMetaBytes = Aes256.processCtr(
        input: encryptedMeta,
        key: aesKey,
        iv: iv,
      );

      final metaStr = utf8.decode(decryptedMetaBytes);
      final metadata = jsonDecode(metaStr) as Map<String, dynamic>;

      final fileDataStart = metaEnd;
      final originalSize = metadata['size'] as int;
      final scrambleLen = min(_scrambleSize, originalSize);

      final encryptedSignature = Uint8List.fromList(bytes.sublist(fileDataStart, fileDataStart + scrambleLen));
      final restBytes = bytes.sublist(fileDataStart + scrambleLen);

      final decryptedSignature = Aes256.processCtr(
        input: encryptedSignature,
        key: aesKey,
        iv: iv,
      );

      originalBytes.add(decryptedSignature);
      originalBytes.add(restBytes);
    } else {
      // V1 fallback
      final lenBytes = bytes.sublist(14, 18);
      final metaLen = (lenBytes[0] << 24) | (lenBytes[1] << 16) | (lenBytes[2] << 8) | lenBytes[3];
      final metaStart = 18;
      final metaEnd = metaStart + metaLen;
      final obfuscatedMetadata = bytes.sublist(metaStart, metaEnd);
      final metaKey = _deriveKeyV1(password, obfuscatedMetadata.length);
      final decryptedMetadataBytes = _xorBytes(obfuscatedMetadata, metaKey);
      final decryptedMetadataStr = utf8.decode(decryptedMetadataBytes);
      final metadata = jsonDecode(decryptedMetadataStr) as Map<String, dynamic>;

      final originalSize = metadata['size'] as int;
      final scrambleLen = min(8192, originalSize);

      final fileDataStart = metaEnd;
      final obfuscatedSignature = bytes.sublist(fileDataStart, fileDataStart + scrambleLen);
      final restBytes = bytes.sublist(fileDataStart + scrambleLen);

      final key = _deriveKeyV1(password, scrambleLen);
      final decryptedSignature = _xorBytes(obfuscatedSignature, key);

      originalBytes.add(decryptedSignature);
      originalBytes.add(restBytes);
    }

    final cacheDir = await getTemporaryDirectory();
    final extension = record.isFolder ? '.zip' : '';
    final tempFilePath = p.join(cacheDir.path, 'temp_vault_${record.id}_${record.originalName}$extension');
    final tempFile = File(tempFilePath);

    await tempFile.writeAsBytes(originalBytes.toBytes());
    return tempFile;
  }
}
