import 'package:isar/isar.dart';

part 'media_item.g.dart';

@collection
class MediaItem {
  Id id = Isar.autoIncrement;

  @Index(unique: true, replace: true)
  String filePath;

  int fileSize;

  DateTime dateAdded;

  bool isScreenshot;

  bool isProcessed;

  MediaItem({
    this.id = Isar.autoIncrement,
    this.filePath = '',
    this.fileSize = 0,
    required this.dateAdded,
    this.isScreenshot = false,
    this.isProcessed = false,
  });
}
