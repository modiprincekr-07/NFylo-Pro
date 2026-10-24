import 'dart:io';
import 'package:path/path.dart' as p;

enum CleanupCategoryType {
  duplicates,
  largeFiles,
  oldFiles,
}

class DuplicateFileItem {
  final String path;
  final String name;
  final int size;
  final DateTime modified;
  final String parentPath;
  bool isOriginal;
  bool isSelected;

  DuplicateFileItem({
    required this.path,
    required this.name,
    required this.size,
    required this.modified,
    required this.parentPath,
    this.isOriginal = false,
    this.isSelected = false,
  });

  factory DuplicateFileItem.fromFile(File file, {bool isOriginal = false, bool isSelected = false}) {
    final stat = file.statSync();
    return DuplicateFileItem(
      path: file.path,
      name: p.basename(file.path),
      size: stat.size,
      modified: stat.modified,
      parentPath: p.dirname(file.path),
      isOriginal: isOriginal,
      isSelected: isSelected,
    );
  }
}

class DuplicateGroup {
  final String groupId;
  final String fileName;
  final int fileSize;
  final List<DuplicateFileItem> files;
  final String hash;
  final bool isSimilarImage;

  DuplicateGroup({
    required this.groupId,
    required this.fileName,
    required this.fileSize,
    required this.files,
    required this.hash,
    this.isSimilarImage = false,
  });

  int get totalWastedBytes => files.length > 1 ? (files.length - 1) * fileSize : 0;
  int get selectedCount => files.where((f) => f.isSelected).length;
  int get selectedBytes => selectedCount * fileSize;

  bool get allDuplicatesSelected {
    final nonOriginals = files.where((f) => !f.isOriginal);
    if (nonOriginals.isEmpty) return false;
    return nonOriginals.every((f) => f.isSelected);
  }

  void selectDuplicatesOnly() {
    for (final f in files) {
      f.isSelected = !f.isOriginal;
    }
  }

  void selectAll() {
    for (final f in files) {
      f.isSelected = true;
    }
  }

  void deselectAll() {
    for (final f in files) {
      f.isSelected = false;
    }
  }
}

class LargeFileCleanupItem {
  final String path;
  final String name;
  final int size;
  final DateTime modified;
  final String extension;
  final String parentPath;
  bool isSelected;

  LargeFileCleanupItem({
    required this.path,
    required this.name,
    required this.size,
    required this.modified,
    required this.extension,
    required this.parentPath,
    this.isSelected = false,
  });
}

class OldFileCleanupItem {
  final String path;
  final String name;
  final int size;
  final DateTime modified;
  final int ageDays;
  final String extension;
  final String parentPath;
  bool isSelected;

  OldFileCleanupItem({
    required this.path,
    required this.name,
    required this.size,
    required this.modified,
    required this.ageDays,
    required this.extension,
    required this.parentPath,
    this.isSelected = false,
  });
}

class CleanupScanProgress {
  final String phase;
  final String currentItem;
  final double progress; // 0.0 to 1.0
  final int scannedCount;
  final int duplicatesFound;

  const CleanupScanProgress({
    required this.phase,
    required this.currentItem,
    required this.progress,
    required this.scannedCount,
    this.duplicatesFound = 0,
  });
}
