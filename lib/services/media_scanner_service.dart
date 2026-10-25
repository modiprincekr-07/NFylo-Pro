import 'dart:io';
import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';
import 'package:photo_manager/photo_manager.dart';
import '../models/media_item.dart';

class MediaScannerService {
  static final MediaScannerService instance = MediaScannerService._internal();
  factory MediaScannerService() => instance;
  MediaScannerService._internal();

  Isar? _isar;

  Future<Isar> get isar async {
    if (_isar != null && _isar!.isOpen) {
      return _isar!;
    }
    _isar = await initIsar();
    return _isar!;
  }

  /// Initializes the local Isar instance with MediaItemSchema
  Future<Isar> initIsar() async {
    final existing = Isar.getInstance('nfile_media_db');
    if (existing != null && existing.isOpen) {
      _isar = existing;
      return existing;
    }
    final dir = await getApplicationDocumentsDirectory();
    _isar = await Isar.open(
      [MediaItemSchema],
      directory: dir.path,
      name: 'nfile_media_db',
    );
    return _isar!;
  }

  /// Scans device storage via PhotoManager, targets screenshots & recent media,
  /// maps them to MediaItem models, and saves them in Isar in a batch transaction.
  Future<int> scanAndSyncMedia({bool includeAllImages = false}) async {
    // Gracefully handle permissions
    final permission = await PhotoManager.requestPermissionExtend();
    if (!permission.isAuth && !permission.hasAccess) {
      return 0;
    }

    final db = await isar;
    final List<MediaItem> mediaItemsToSync = [];
    final Set<String> seenPaths = {};

    try {
      // 1. Fetch all albums/paths containing images
      final List<AssetPathEntity> albums = await PhotoManager.getAssetPathList(
        type: RequestType.image,
        onlyAll: false,
      );

      for (final album in albums) {
        final albumNameLower = album.name.toLowerCase();
        final isScreenshotAlbum = albumNameLower.contains('screenshot') ||
            albumNameLower.contains('screen_shot') ||
            albumNameLower.contains('screen shot');

        // Target screenshots specifically, or include general albums if requested
        if (!isScreenshotAlbum && !includeAllImages) {
          continue;
        }

        // Fetch assets from album (up to 2000 per album in batches)
        final int assetCount = await album.assetCountAsync;
        final int pageSize = 500;
        final int totalPages = (assetCount / pageSize).ceil();

        for (int page = 0; page < totalPages && page < 4; page++) {
          final List<AssetEntity> assets = await album.getAssetListPaged(
            page: page,
            size: pageSize,
          );

          for (final asset in assets) {
            // Check if it looks like a screenshot by album or title/path
            final isScreenshot = isScreenshotAlbum ||
                (asset.title?.toLowerCase().contains('screenshot') ?? false);

            final File? file = await asset.file;
            if (file == null || !file.existsSync()) continue;

            final path = file.path;
            if (seenPaths.contains(path)) continue;
            seenPaths.add(path);

            int fileSize = 0;
            try {
              fileSize = await file.length();
            } catch (_) {}

            final dateAdded = asset.createDateTime;

            mediaItemsToSync.add(
              MediaItem(
                filePath: path,
                fileSize: fileSize,
                dateAdded: dateAdded,
                isScreenshot: isScreenshot,
                isProcessed: false,
              ),
            );
          }
        }
      }

      // Also directly scan filesystem for typical screenshot folders if empty
      if (mediaItemsToSync.isEmpty || includeAllImages) {
        final commonScreenshotDirs = [
          '/storage/emulated/0/Pictures/Screenshots',
          '/storage/emulated/0/DCIM/Screenshots',
        ];

        for (final dirPath in commonScreenshotDirs) {
          final dir = Directory(dirPath);
          if (dir.existsSync()) {
            final entities = dir.listSync(followLinks: false);
            for (final entity in entities) {
              if (entity is File && !seenPaths.contains(entity.path)) {
                final ext = entity.path.split('.').last.toLowerCase();
                if (['jpg', 'jpeg', 'png', 'webp'].contains(ext)) {
                  seenPaths.add(entity.path);
                  int size = 0;
                  try {
                    size = entity.lengthSync();
                  } catch (_) {}
                  DateTime date = DateTime.now();
                  try {
                    date = entity.lastModifiedSync();
                  } catch (_) {}

                  mediaItemsToSync.add(
                    MediaItem(
                      filePath: entity.path,
                      fileSize: size,
                      dateAdded: date,
                      isScreenshot: true,
                      isProcessed: false,
                    ),
                  );
                }
              }
            }
          }
        }
      }

      // Batch put into Isar efficiently
      if (mediaItemsToSync.isNotEmpty) {
        await db.writeTxn(() async {
          await db.mediaItems.putAll(mediaItemsToSync);
        });
      }

      return mediaItemsToSync.length;
    } catch (e) {
      return mediaItemsToSync.length;
    }
  }

  /// Get unprocessed items for the Swipe UI
  Future<List<MediaItem>> getUnprocessedItems({bool onlyScreenshots = false, int limit = 50}) async {
    final db = await isar;
    if (onlyScreenshots) {
      return db.mediaItems
          .filter()
          .isProcessedEqualTo(false)
          .and()
          .isScreenshotEqualTo(true)
          .sortByDateAddedDesc()
          .limit(limit)
          .findAll();
    } else {
      return db.mediaItems
          .filter()
          .isProcessedEqualTo(false)
          .sortByDateAddedDesc()
          .limit(limit)
          .findAll();
    }
  }

  /// Mark item as processed
  Future<void> markProcessed(MediaItem item) async {
    final db = await isar;
    item.isProcessed = true;
    await db.writeTxn(() async {
      await db.mediaItems.put(item);
    });
  }

  /// Delete item from disk and Isar
  Future<bool> deleteMediaItem(MediaItem item) async {
    final db = await isar;
    try {
      final file = File(item.filePath);
      if (file.existsSync()) {
        file.deleteSync();
      }
      await db.writeTxn(() async {
        await db.mediaItems.delete(item.id);
      });
      return true;
    } catch (_) {
      return false;
    }
  }
}
