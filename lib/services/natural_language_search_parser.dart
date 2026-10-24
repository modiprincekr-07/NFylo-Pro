import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../models/file_item_model.dart';
import '../core/utils.dart';

class ActiveFilterBadge {
  final String label;
  final IconData icon;
  final Color color;
  final String type; // 'type', 'size', 'date', 'path'

  const ActiveFilterBadge({
    required this.label,
    required this.icon,
    required this.color,
    required this.type,
  });
}

class ParsedSearchQuery {
  final String rawQuery;
  final String? textQuery;
  final Set<String> fileTypes; // 'images', 'videos', 'audio', 'docs', 'pdfs', 'archives', 'apks', 'code'
  final int? minSizeBytes;
  final int? maxSizeBytes;
  final DateTime? minModifiedDate;
  final DateTime? maxModifiedDate;
  final String? dateLabel;
  final List<String> pathKeywords;
  final bool? isFolderOnly;

  const ParsedSearchQuery({
    required this.rawQuery,
    this.textQuery,
    this.fileTypes = const {},
    this.minSizeBytes,
    this.maxSizeBytes,
    this.minModifiedDate,
    this.maxModifiedDate,
    this.dateLabel,
    this.pathKeywords = const [],
    this.isFolderOnly,
  });

  bool get hasSemanticFilters =>
      fileTypes.isNotEmpty ||
      minSizeBytes != null ||
      maxSizeBytes != null ||
      minModifiedDate != null ||
      maxModifiedDate != null ||
      pathKeywords.isNotEmpty ||
      isFolderOnly == true;

  List<ActiveFilterBadge> get activeBadges {
    final badges = <ActiveFilterBadge>[];

    // File Type badges
    for (final ft in fileTypes) {
      badges.add(
        ActiveFilterBadge(
          label: _getTypeLabel(ft),
          icon: _getTypeIcon(ft),
          color: _getTypeColor(ft),
          type: 'type',
        ),
      );
    }

    // Size badges
    if (minSizeBytes != null && maxSizeBytes != null) {
      badges.add(
        ActiveFilterBadge(
          label: '${FileUtils.formatBytes(minSizeBytes!, 0)} - ${FileUtils.formatBytes(maxSizeBytes!, 0)}',
          icon: Icons.data_usage_rounded,
          color: const Color(0xFF3B82F6),
          type: 'size',
        ),
      );
    } else if (minSizeBytes != null) {
      badges.add(
        ActiveFilterBadge(
          label: '> ${FileUtils.formatBytes(minSizeBytes!, 0)}',
          icon: Icons.arrow_upward_rounded,
          color: const Color(0xFFEF4444),
          type: 'size',
        ),
      );
    } else if (maxSizeBytes != null) {
      badges.add(
        ActiveFilterBadge(
          label: '< ${FileUtils.formatBytes(maxSizeBytes!, 0)}',
          icon: Icons.arrow_downward_rounded,
          color: const Color(0xFF10B981),
          type: 'size',
        ),
      );
    }

    // Date badges
    if (dateLabel != null) {
      badges.add(
        ActiveFilterBadge(
          label: dateLabel!,
          icon: Icons.calendar_today_rounded,
          color: const Color(0xFFF59E0B),
          type: 'date',
        ),
      );
    }

    // Path badges
    for (final kw in pathKeywords) {
      badges.add(
        ActiveFilterBadge(
          label: _getPathKeywordLabel(kw),
          icon: Icons.folder_open_rounded,
          color: const Color(0xFF06B6D4),
          type: 'path',
        ),
      );
    }

    return badges;
  }

  String _getTypeLabel(String type) {
    switch (type) {
      case 'pdfs':
        return 'PDFs';
      case 'images':
        return 'Images';
      case 'videos':
        return 'Videos';
      case 'audio':
        return 'Audio';
      case 'docs':
        return 'Documents';
      case 'archives':
        return 'Archives';
      case 'apks':
        return 'APKs';
      case 'code':
        return 'Code';
      default:
        return type.toUpperCase();
    }
  }

  IconData _getTypeIcon(String type) {
    switch (type) {
      case 'pdfs':
      case 'docs':
        return Icons.description_rounded;
      case 'images':
        return Icons.image_rounded;
      case 'videos':
        return Icons.video_collection_rounded;
      case 'audio':
        return Icons.music_note_rounded;
      case 'archives':
        return Icons.archive_rounded;
      case 'apks':
        return Icons.android_rounded;
      case 'code':
        return Icons.code_rounded;
      default:
        return Icons.insert_drive_file_rounded;
    }
  }

  Color _getTypeColor(String type) {
    switch (type) {
      case 'pdfs':
        return const Color(0xFFEC4899);
      case 'images':
        return const Color(0xFF8B5CF6);
      case 'videos':
        return const Color(0xFFEF4444);
      case 'audio':
        return const Color(0xFFF97316);
      case 'docs':
        return const Color(0xFF3B82F6);
      case 'archives':
        return const Color(0xFFF59E0B);
      case 'apks':
        return const Color(0xFF10B981);
      case 'code':
        return const Color(0xFF06B6D4);
      default:
        return const Color(0xFF64748B);
    }
  }

  String _getPathKeywordLabel(String kw) {
    switch (kw) {
      case 'screenshot':
        return 'Screenshots';
      case 'whatsapp':
        return 'WhatsApp';
      case 'telegram':
        return 'Telegram';
      case 'download':
        return 'Downloads';
      case 'camera':
        return 'Camera';
      default:
        return kw;
    }
  }

  bool matches(FileItemModel item) {
    // 1. Text Query (Filename)
    if (textQuery != null && textQuery!.isNotEmpty) {
      if (!item.name.toLowerCase().contains(textQuery!.toLowerCase())) {
        return false;
      }
    }

    // 2. Folder Only check
    if (isFolderOnly == true && !item.isDirectory) return false;
    if (fileTypes.isNotEmpty && item.isDirectory) return false;

    // 3. File Types / Extensions
    if (fileTypes.isNotEmpty && !item.isDirectory) {
      final ext = p.extension(item.path).toLowerCase();
      final allowedExts = NaturalLanguageSearchParser.extensionsForTypes(fileTypes);
      if (!allowedExts.contains(ext)) return false;
    }

    // 4. Min Size
    if (minSizeBytes != null && item.size < minSizeBytes!) {
      return false;
    }

    // 5. Max Size
    if (maxSizeBytes != null && item.size > maxSizeBytes!) {
      return false;
    }

    // 6. Date Range
    if (minModifiedDate != null && item.modified.isBefore(minModifiedDate!)) {
      return false;
    }
    if (maxModifiedDate != null && item.modified.isAfter(maxModifiedDate!)) {
      return false;
    }

    // 7. Path Keywords
    if (pathKeywords.isNotEmpty) {
      final lowerPath = item.path.toLowerCase();
      bool pathMatches = false;
      for (final kw in pathKeywords) {
        if (lowerPath.contains(kw)) {
          pathMatches = true;
          break;
        }
      }
      if (!pathMatches) return false;
    }

    return true;
  }
}

class NaturalLanguageSearchParser {
  static const Map<String, List<String>> _typeExtensions = {
    'images': ['.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp', '.heic', '.avif', '.svg'],
    'videos': ['.mp4', '.mkv', '.avi', '.mov', '.wmv', '.flv', '.webm', '.ts', '.3gp'],
    'audio': ['.mp3', '.m4a', '.wav', '.flac', '.aac', '.ogg', '.opus', '.amr', '.wma'],
    'docs': ['.pdf', '.doc', '.docx', '.xls', '.xlsx', '.ppt', '.pptx', '.txt', '.csv', '.odt', '.ods', '.rtf'],
    'pdfs': ['.pdf'],
    'archives': ['.zip', '.rar', '.7z', '.tar', '.gz', '.bz2', '.xz', '.iso'],
    'apks': ['.apk', '.xapk', '.apks'],
    'code': ['.dart', '.py', '.js', '.ts', '.html', '.css', '.java', '.kt', '.c', '.cpp', '.h', '.json', '.xml', '.yaml', '.yml', '.sh', '.sql'],
  };

  static Set<String> extensionsForTypes(Set<String> types) {
    final set = <String>{};
    for (final t in types) {
      final exts = _typeExtensions[t];
      if (exts != null) set.addAll(exts);
    }
    return set;
  }

  /// Parses user natural language query string into a [ParsedSearchQuery].
  static ParsedSearchQuery parse(String input) {
    String remaining = input.trim();
    if (remaining.isEmpty) {
      return const ParsedSearchQuery(rawQuery: '');
    }

    final Set<String> fileTypes = {};
    int? minSize;
    int? maxSize;
    DateTime? minDate;
    DateTime? maxDate;
    String? dateLabel;
    final List<String> pathKeywords = [];
    bool? isFolderOnly;

    // 1. Path keywords
    final pathPatterns = [
      (RegExp(r'\b(screenshots?)\b', caseSensitive: false), 'screenshot'),
      (RegExp(r'\b(whatsapp|wa)\b', caseSensitive: false), 'whatsapp'),
      (RegExp(r'\b(telegrams?)\b', caseSensitive: false), 'telegram'),
      (RegExp(r'\b(downloads?)\b', caseSensitive: false), 'download'),
      (RegExp(r'\b(cameras?|dcim)\b', caseSensitive: false), 'camera'),
    ];

    for (final p in pathPatterns) {
      if (p.$1.hasMatch(remaining)) {
        pathKeywords.add(p.$2);
        remaining = remaining.replaceAll(p.$1, ' ');
      }
    }

    // 2. Size rules
    final sizeMultipliers = <String, int>{
      'b': 1,
      'bytes': 1,
      'k': 1024,
      'kb': 1024,
      'm': 1024 * 1024,
      'mb': 1024 * 1024,
      'g': 1024 * 1024 * 1024,
      'gb': 1024 * 1024 * 1024,
    };

    // "Large files" / "heavy files"
    final largeFilesPattern = RegExp(r'\b(large|heavy)\s+files?\b', caseSensitive: false);
    if (largeFilesPattern.hasMatch(remaining)) {
      minSize = 25 * 1024 * 1024; // 25 MB
      remaining = remaining.replaceAll(largeFilesPattern, ' ');
    }

    // Min Size: bigger than X, larger than X, more than X, > X
    final minSizePattern = RegExp(
      r'(?:(?:bigger|larger|greater|more|over|above)\s+(?:than\s+)?|>|>=)\s*(\d+(?:\.\d+)?)\s*(kb|mb|gb|k|m|g|bytes|b)?\b',
      caseSensitive: false,
    );
    final minMatch = minSizePattern.firstMatch(remaining);
    if (minMatch != null) {
      final val = double.tryParse(minMatch.group(1) ?? '0') ?? 0;
      final unit = (minMatch.group(2) ?? 'mb').toLowerCase();
      final mult = sizeMultipliers[unit] ?? (1024 * 1024);
      minSize = (val * mult).round();
      remaining = remaining.replaceAll(minMatch.group(0)!, ' ');
    }

    // Max Size: smaller than X, less than X, under X, < X
    final maxSizePattern = RegExp(
      r'(?:(?:smaller|less|under|below)\s+(?:than\s+)?|<|<=)\s*(\d+(?:\.\d+)?)\s*(kb|mb|gb|k|m|g|bytes|b)?\b',
      caseSensitive: false,
    );
    final maxMatch = maxSizePattern.firstMatch(remaining);
    if (maxMatch != null) {
      final val = double.tryParse(maxMatch.group(1) ?? '0') ?? 0;
      final unit = (maxMatch.group(2) ?? 'mb').toLowerCase();
      final mult = sizeMultipliers[unit] ?? (1024 * 1024);
      maxSize = (val * mult).round();
      remaining = remaining.replaceAll(maxMatch.group(0)!, ' ');
    }

    // 3. Date rules
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);

    if (RegExp(r'\b(today|from today|modified today)\b', caseSensitive: false).hasMatch(remaining)) {
      minDate = todayStart;
      dateLabel = 'Today';
      remaining = remaining.replaceAll(RegExp(r'\b(from\s+)?(modified\s+)?today\b', caseSensitive: false), ' ');
    } else if (RegExp(r'\b(yesterday|from yesterday|modified yesterday)\b', caseSensitive: false).hasMatch(remaining)) {
      minDate = todayStart.subtract(const Duration(days: 1));
      maxDate = todayStart;
      dateLabel = 'Yesterday';
      remaining = remaining.replaceAll(RegExp(r'\b(from\s+)?(modified\s+)?yesterday\b', caseSensitive: false), ' ');
    } else if (RegExp(r'\b(this week|from this week)\b', caseSensitive: false).hasMatch(remaining)) {
      minDate = todayStart.subtract(Duration(days: now.weekday - 1));
      dateLabel = 'This Week';
      remaining = remaining.replaceAll(RegExp(r'\b(from\s+)?this\s+week\b', caseSensitive: false), ' ');
    } else if (RegExp(r'\b(last week|from last week)\b', caseSensitive: false).hasMatch(remaining)) {
      final startOfThisWeek = todayStart.subtract(Duration(days: now.weekday - 1));
      minDate = startOfThisWeek.subtract(const Duration(days: 7));
      maxDate = startOfThisWeek;
      dateLabel = 'Last Week';
      remaining = remaining.replaceAll(RegExp(r'\b(from\s+)?last\s+week\b', caseSensitive: false), ' ');
    } else if (RegExp(r'\b(this month|from this month)\b', caseSensitive: false).hasMatch(remaining)) {
      minDate = DateTime(now.year, now.month, 1);
      dateLabel = 'This Month';
      remaining = remaining.replaceAll(RegExp(r'\b(from\s+)?this\s+month\b', caseSensitive: false), ' ');
    } else if (RegExp(r'\b(last month|from last month)\b', caseSensitive: false).hasMatch(remaining)) {
      minDate = DateTime(now.year, now.month - 1, 1);
      maxDate = DateTime(now.year, now.month, 1);
      dateLabel = 'Last Month';
      remaining = remaining.replaceAll(RegExp(r'\b(from\s+)?last\s+month\b', caseSensitive: false), ' ');
    }

    // 4. File Types
    final typePatterns = [
      (RegExp(r'\b(pdfs?|pdf files?)\b', caseSensitive: false), 'pdfs'),
      (RegExp(r'\b(images?|photos?|pictures?|pics?)\b', caseSensitive: false), 'images'),
      (RegExp(r'\b(videos?|movies?|clips?)\b', caseSensitive: false), 'videos'),
      (RegExp(r'\b(audio|music|songs?|tracks?|mp3s?)\b', caseSensitive: false), 'audio'),
      (RegExp(r'\b(documents?|docs?)\b', caseSensitive: false), 'docs'),
      (RegExp(r'\b(archives?|zips?|compressed)\b', caseSensitive: false), 'archives'),
      (RegExp(r'\b(apks?|apps?)\b', caseSensitive: false), 'apks'),
      (RegExp(r'\b(code|scripts?)\b', caseSensitive: false), 'code'),
    ];

    for (final p in typePatterns) {
      if (p.$1.hasMatch(remaining)) {
        fileTypes.add(p.$2);
        remaining = remaining.replaceAll(p.$1, ' ');
      }
    }

    // "Folders only" check
    if (RegExp(r'\b(folders?|directories|directory)\b', caseSensitive: false).hasMatch(remaining)) {
      isFolderOnly = true;
      remaining = remaining.replaceAll(RegExp(r'\b(folders?|directories|directory)\b', caseSensitive: false), ' ');
    }

    // Infer image type if "Screenshots" is queried without explicit type
    if (pathKeywords.contains('screenshot') && fileTypes.isEmpty) {
      fileTypes.add('images');
    }

    // 5. Clean up remaining residual text
    final cleanText = remaining
        .replaceAll(RegExp(r'\b(from|in|modified|created|files?|than|of|with|bigger|smaller|larger)\b', caseSensitive: false), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    return ParsedSearchQuery(
      rawQuery: input,
      textQuery: cleanText.isNotEmpty ? cleanText : null,
      fileTypes: fileTypes,
      minSizeBytes: minSize,
      maxSizeBytes: maxSize,
      minModifiedDate: minDate,
      maxModifiedDate: maxDate,
      dateLabel: dateLabel,
      pathKeywords: pathKeywords,
      isFolderOnly: isFolderOnly,
    );
  }
}
