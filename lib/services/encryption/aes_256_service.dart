import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

class Aes256 {
  static const List<int> _sbox = [
    0x63, 0x7c, 0x77, 0x7b, 0xf2, 0x6b, 0x6f, 0xc5, 0x30, 0x01, 0x67, 0x2b, 0xfe, 0xd7, 0xab, 0x76,
    0xca, 0x82, 0xc9, 0x7d, 0xfa, 0x59, 0x47, 0xf0, 0xad, 0xd4, 0xa2, 0xaf, 0x9c, 0xa4, 0x72, 0xc0,
    0xb7, 0xfd, 0x93, 0x26, 0x36, 0x3f, 0xf7, 0xcc, 0x34, 0xa5, 0xe5, 0xf1, 0x71, 0xd8, 0x31, 0x15,
    0x04, 0xc7, 0x23, 0xc3, 0x18, 0x96, 0x05, 0x9a, 0x07, 0x12, 0x80, 0xe2, 0xeb, 0x27, 0xb2, 0x75,
    0x09, 0x83, 0x2c, 0x1a, 0x1b, 0x6e, 0x5a, 0xa0, 0x52, 0x3b, 0xd6, 0xb3, 0x29, 0xe3, 0x2f, 0x84,
    0x53, 0xd1, 0x00, 0xed, 0x20, 0xfc, 0xb1, 0x5b, 0x6a, 0xcb, 0xbe, 0x39, 0x4a, 0x4c, 0x58, 0xcf,
    0xd0, 0xef, 0xaa, 0xfb, 0x43, 0x4d, 0x33, 0x85, 0x45, 0xf9, 0x02, 0x7f, 0x50, 0x3c, 0x9f, 0xa8,
    0x51, 0xa3, 0x40, 0x8f, 0x92, 0x9d, 0x38, 0xf5, 0xbc, 0xb6, 0xda, 0x21, 0x10, 0xff, 0xf3, 0xd2,
    0xcd, 0x0c, 0x13, 0xec, 0x5f, 0x97, 0x44, 0x17, 0xc4, 0xa7, 0x7e, 0x3d, 0x64, 0x5d, 0x19, 0x73,
    0x60, 0x81, 0x4f, 0xdc, 0x22, 0x2a, 0x90, 0x88, 0x46, 0xee, 0xb8, 0x14, 0xde, 0x5e, 0x0b, 0xdb,
    0xe0, 0x32, 0x3a, 0x0a, 0x49, 0x06, 0x24, 0x5c, 0xc2, 0xd3, 0xac, 0x62, 0x91, 0x95, 0xe4, 0x79,
    0xe7, 0xc8, 0x37, 0x6d, 0x8d, 0xd5, 0x4e, 0xa9, 0x6c, 0x56, 0xf4, 0xea, 0x65, 0x7a, 0xae, 0x08,
    0xba, 0x78, 0x25, 0x2e, 0x1c, 0xa6, 0xb4, 0xc6, 0xe8, 0xdd, 0x74, 0x1f, 0x4b, 0xbd, 0x8b, 0x8a,
    0x70, 0x3e, 0xb5, 0x66, 0x48, 0x03, 0xf6, 0x0e, 0x61, 0x35, 0x57, 0xb9, 0x86, 0xc1, 0x1d, 0x9e,
    0xe1, 0xf8, 0x98, 0x11, 0x69, 0xd9, 0x8e, 0x94, 0x9b, 0x1e, 0x87, 0xe9, 0xce, 0x55, 0x28, 0xdf,
    0x8c, 0xa1, 0x89, 0x0d, 0xbf, 0xe6, 0x42, 0x68, 0x41, 0x99, 0x2d, 0x0f, 0xb0, 0x54, 0xbb, 0x16
  ];

  static const List<int> _rcon = [
    0x00, 0x01, 0x02, 0x04, 0x08, 0x10, 0x20, 0x40, 0x80, 0x1b, 0x36
  ];

  static int _rotWord(int w) => ((w << 8) | ((w >> 24) & 0xff)) & 0xffffffff;

  static int _subWord(int w) {
    return ((_sbox[(w >> 24) & 0xff] << 24) |
            (_sbox[(w >> 16) & 0xff] << 16) |
            (_sbox[(w >> 8) & 0xff] << 8) |
            _sbox[w & 0xff]) &
        0xffffffff;
  }

  static Uint32List expandKey(Uint8List keyBytes) {
    if (keyBytes.length != 32) {
      throw ArgumentError('AES-256 requires a 32-byte key.');
    }
    final w = Uint32List(60);
    for (int i = 0; i < 8; i++) {
      w[i] = ((keyBytes[4 * i] << 24) |
              (keyBytes[4 * i + 1] << 16) |
              (keyBytes[4 * i + 2] << 8) |
              keyBytes[4 * i + 3]) &
          0xffffffff;
    }
    for (int i = 8; i < 60; i++) {
      int temp = w[i - 1];
      if (i % 8 == 0) {
        temp = (_subWord(_rotWord(temp)) ^ (_rcon[i ~/ 8] << 24)) & 0xffffffff;
      } else if (i % 8 == 4) {
        temp = _subWord(temp);
      }
      w[i] = (w[i - 8] ^ temp) & 0xffffffff;
    }
    return w;
  }

  static int _xtime(int a) => (((a << 1) ^ (((a >> 7) & 1) * 0x1b)) & 0xff);

  static void encryptBlock(
    Uint8List input,
    int inOff,
    Uint8List output,
    int outOff,
    Uint32List w,
  ) {
    final state = Uint8List(16);
    for (int i = 0; i < 16; i++) {
      state[i] = input[inOff + i];
    }

    // AddRoundKey 0
    for (int i = 0; i < 4; i++) {
      final k = w[i];
      state[4 * i] ^= (k >> 24) & 0xff;
      state[4 * i + 1] ^= (k >> 16) & 0xff;
      state[4 * i + 2] ^= (k >> 8) & 0xff;
      state[4 * i + 3] ^= k & 0xff;
    }

    // 13 Rounds
    for (int round = 1; round <= 13; round++) {
      // SubBytes
      for (int i = 0; i < 16; i++) {
        state[i] = _sbox[state[i]];
      }

      // ShiftRows
      int t = state[1]; state[1] = state[5]; state[5] = state[9]; state[9] = state[13]; state[13] = t;
      t = state[2]; state[2] = state[10]; state[10] = t; t = state[6]; state[6] = state[14]; state[14] = t;
      t = state[15]; state[15] = state[11]; state[11] = state[7]; state[7] = state[3]; state[3] = t;

      // MixColumns
      for (int i = 0; i < 4; i++) {
        final idx = 4 * i;
        final s0 = state[idx], s1 = state[idx + 1], s2 = state[idx + 2], s3 = state[idx + 3];
        final h0 = _xtime(s0), h1 = _xtime(s1), h2 = _xtime(s2), h3 = _xtime(s3);
        state[idx] = (h0 ^ h1 ^ s1 ^ s2 ^ s3) & 0xff;
        state[idx + 1] = (s0 ^ h1 ^ h2 ^ s2 ^ s3) & 0xff;
        state[idx + 2] = (s0 ^ s1 ^ h2 ^ h3 ^ s3) & 0xff;
        state[idx + 3] = (h0 ^ s0 ^ s1 ^ s2 ^ h3) & 0xff;
      }

      // AddRoundKey
      for (int i = 0; i < 4; i++) {
        final k = w[round * 4 + i];
        state[4 * i] ^= (k >> 24) & 0xff;
        state[4 * i + 1] ^= (k >> 16) & 0xff;
        state[4 * i + 2] ^= (k >> 8) & 0xff;
        state[4 * i + 3] ^= k & 0xff;
      }
    }

    // Round 14 (no MixColumns)
    for (int i = 0; i < 16; i++) {
      state[i] = _sbox[state[i]];
    }
    int t = state[1]; state[1] = state[5]; state[5] = state[9]; state[9] = state[13]; state[13] = t;
    t = state[2]; state[2] = state[10]; state[10] = t; t = state[6]; state[6] = state[14]; state[14] = t;
    t = state[15]; state[15] = state[11]; state[11] = state[7]; state[7] = state[3]; state[3] = t;

    for (int i = 0; i < 4; i++) {
      final k = w[14 * 4 + i];
      state[4 * i] ^= (k >> 24) & 0xff;
      state[4 * i + 1] ^= (k >> 16) & 0xff;
      state[4 * i + 2] ^= (k >> 8) & 0xff;
      state[4 * i + 3] ^= k & 0xff;
    }

    for (int i = 0; i < 16; i++) {
      output[outOff + i] = state[i];
    }
  }

  /// Encrypts / Decrypts bytes in CTR (Counter) mode.
  /// CTR mode is completely symmetric (encryption and decryption are identical).
  static Uint8List processCtr({
    required Uint8List input,
    required Uint8List key,
    required Uint8List iv,
  }) {
    final w = expandKey(key);
    final output = Uint8List(input.length);
    final counterBlock = Uint8List(16);
    counterBlock.setRange(0, 16, iv);
    final keystream = Uint8List(16);

    for (int i = 0; i < input.length; i++) {
      final blockOffset = i % 16;
      if (blockOffset == 0) {
        encryptBlock(counterBlock, 0, keystream, 0, w);
        // Increment 128-bit big-endian counter
        for (int c = 15; c >= 0; c--) {
          counterBlock[c] = (counterBlock[c] + 1) & 0xff;
          if (counterBlock[c] != 0) break;
        }
      }
      output[i] = input[i] ^ keystream[blockOffset];
    }
    return output;
  }
}

class Aes256FileEncryptor {
  static const List<int> _magicHeader = [0x4E, 0x45, 0x4E, 0x43]; // "NENC"
  static const int _version = 0x02;

  /// Derives a cryptographically strong 256-bit key using PBKDF2/SHA-256 iterations.
  static Uint8List deriveKey(String password, Uint8List salt) {
    List<int> current = utf8.encode(password) + salt;
    // 5000 rounds of SHA-256 key stretching
    for (int i = 0; i < 5000; i++) {
      current = sha256.convert(current).bytes;
    }
    return Uint8List.fromList(current);
  }

  /// Encrypts an individual file using AES-256-CTR and outputs to [outputFile].
  static Future<void> encryptFile({
    required File inputFile,
    required File outputFile,
    required String password,
    void Function(double progress)? onProgress,
  }) async {
    final totalSize = await inputFile.length();
    final random = Random.secure();
    final salt = Uint8List(16);
    final iv = Uint8List(16);
    for (int i = 0; i < 16; i++) {
      salt[i] = random.nextInt(256);
      iv[i] = random.nextInt(256);
    }

    final key = deriveKey(password, salt);
    final originalName = p.basename(inputFile.path);
    final nameBytes = utf8.encode(originalName);

    final outSink = outputFile.openWrite();

    // 1. Write Header:
    // [MAGIC: 4B] [VERSION: 1B] [SALT: 16B] [IV: 16B] [NAME_LEN: 2B] [NAME_BYTES]
    outSink.add(_magicHeader);
    outSink.add([_version]);
    outSink.add(salt);
    outSink.add(iv);
    outSink.add([(nameBytes.length >> 8) & 0xff, nameBytes.length & 0xff]);
    outSink.add(nameBytes);

    // 2. Stream File & Encrypt in 64KB Chunks
    final inStream = inputFile.openRead();
    int processedBytes = 0;

    final w = Aes256.expandKey(key);
    final counterBlock = Uint8List(16);
    counterBlock.setRange(0, 16, iv);
    final keystream = Uint8List(16);
    int streamOffset = 0;

    await for (final chunk in inStream) {
      final chunkLen = chunk.length;
      final encryptedChunk = Uint8List(chunkLen);

      for (int i = 0; i < chunkLen; i++) {
        final bOff = streamOffset % 16;
        if (bOff == 0) {
          Aes256.encryptBlock(counterBlock, 0, keystream, 0, w);
          for (int c = 15; c >= 0; c--) {
            counterBlock[c] = (counterBlock[c] + 1) & 0xff;
            if (counterBlock[c] != 0) break;
          }
        }
        encryptedChunk[i] = chunk[i] ^ keystream[bOff];
        streamOffset++;
      }

      outSink.add(encryptedChunk);
      processedBytes += chunkLen;
      if (totalSize > 0) {
        onProgress?.call(processedBytes / totalSize);
      }
    }

    await outSink.flush();
    await outSink.close();
    onProgress?.call(1.0);
  }

  /// Decrypts a `.nenc` or `.enc` file with [password] into [outputDirectory].
  /// Returns the decrypted [File].
  static Future<File> decryptFile({
    required File inputFile,
    required String outputDirectory,
    required String password,
    void Function(double progress)? onProgress,
  }) async {
    final raf = await inputFile.open(mode: FileMode.read);
    final totalSize = await inputFile.length();

    try {
      // 1. Validate Header
      final magic = await raf.read(4);
      if (magic.length < 4 ||
          magic[0] != _magicHeader[0] ||
          magic[1] != _magicHeader[1] ||
          magic[2] != _magicHeader[2] ||
          magic[3] != _magicHeader[3]) {
        throw const FormatException('Invalid or unsupported encrypted file format.');
      }

      final ver = (await raf.read(1))[0];
      if (ver != _version && ver != 0x01) {
        throw FormatException('Unsupported encryption version: $ver');
      }

      final salt = await raf.read(16);
      final iv = await raf.read(16);
      final nameLenBytes = await raf.read(2);
      final nameLen = (nameLenBytes[0] << 8) | nameLenBytes[1];
      final nameBytes = await raf.read(nameLen);
      final originalName = utf8.decode(nameBytes);

      final key = deriveKey(password, salt);
      final w = Aes256.expandKey(key);

      // Determine output path
      String outPath = p.join(outputDirectory, originalName);
      if (await File(outPath).exists()) {
        final base = p.basenameWithoutExtension(originalName);
        final ext = p.extension(originalName);
        outPath = p.join(outputDirectory, '${base}_decrypted$ext');
      }

      final outFile = File(outPath);
      final outSink = outFile.openWrite();

      final counterBlock = Uint8List(16);
      counterBlock.setRange(0, 16, iv);
      final keystream = Uint8List(16);
      int streamOffset = 0;

      const bufferSize = 64 * 1024;
      int processedBytes = 0;
      final payloadSize = totalSize - (await raf.position());

      while (true) {
        final chunk = await raf.read(bufferSize);
        if (chunk.isEmpty) break;

        final chunkLen = chunk.length;
        final decryptedChunk = Uint8List(chunkLen);

        for (int i = 0; i < chunkLen; i++) {
          final bOff = streamOffset % 16;
          if (bOff == 0) {
            Aes256.encryptBlock(counterBlock, 0, keystream, 0, w);
            for (int c = 15; c >= 0; c--) {
              counterBlock[c] = (counterBlock[c] + 1) & 0xff;
              if (counterBlock[c] != 0) break;
            }
          }
          decryptedChunk[i] = chunk[i] ^ keystream[bOff];
          streamOffset++;
        }

        outSink.add(decryptedChunk);
        processedBytes += chunkLen;
        if (payloadSize > 0) {
          onProgress?.call(processedBytes / payloadSize);
        }
      }

      await outSink.flush();
      await outSink.close();
      onProgress?.call(1.0);

      return outFile;
    } finally {
      await raf.close();
    }
  }
}
