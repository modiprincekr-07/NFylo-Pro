import 'package:flutter/material.dart';
import '../../media_category_screen.dart';

class StorageCategoryInfo {
  final String id;
  final String name;
  int size;
  int count;
  final Color color;
  final IconData icon;
  final List<String> extensions;
  final MediaType? mediaType;

  StorageCategoryInfo({
    required this.id,
    required this.name,
    this.size = 0,
    this.count = 0,
    required this.color,
    required this.icon,
    this.extensions = const [],
    this.mediaType,
  });

  double percentageOf(int total) {
    if (total <= 0) return 0.0;
    return (size / total) * 100.0;
  }
}

class FolderSpaceTile {
  final String name;
  final String path;
  final int size;
  final Color color;
  final IconData icon;
  final double proportion; // relative to total folders size (0.0 - 1.0)

  const FolderSpaceTile({
    required this.name,
    required this.path,
    required this.size,
    required this.color,
    required this.icon,
    required this.proportion,
  });
}

class LargestFileItem {
  final String path;
  final String name;
  final int size;
  final DateTime modified;
  final String extension;
  final Color color;
  final IconData icon;

  const LargestFileItem({
    required this.path,
    required this.name,
    required this.size,
    required this.modified,
    required this.extension,
    required this.color,
    required this.icon,
  });
}
