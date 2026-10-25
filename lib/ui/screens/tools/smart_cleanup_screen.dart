import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_card_swiper/flutter_card_swiper.dart';
import 'package:path/path.dart' as p;
import '../../../core/utils.dart';
import '../../../models/media_item.dart';
import '../../../services/media_scanner_service.dart';

class SmartCleanupScreen extends StatefulWidget {
  const SmartCleanupScreen({super.key});

  @override
  State<SmartCleanupScreen> createState() => _SmartCleanupScreenState();
}

class _SmartCleanupScreenState extends State<SmartCleanupScreen> {
  final MediaScannerService _scannerService = MediaScannerService();
  late final CardSwiperController _controller;

  List<MediaItem> _items = [];
  bool _isLoading = true;
  bool _isDeckFinished = false;
  bool _onlyScreenshots = false;
  int _currentIndex = 0;

  int _deletedCount = 0;
  int _keptCount = 0;
  int _totalBytesDeleted = 0;

  @override
  void initState() {
    super.initState();
    _controller = CardSwiperController();
    _scanAndLoad();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _scanAndLoad() async {
    setState(() {
      _isLoading = true;
      _isDeckFinished = false;
      _currentIndex = 0;
      _deletedCount = 0;
      _keptCount = 0;
      _totalBytesDeleted = 0;
    });

    try {
      await _scannerService.scanAndSyncMedia(includeAllImages: true);
      final items = await _scannerService.getUnprocessedItems(
        onlyScreenshots: _onlyScreenshots,
        limit: 150,
      );
      if (mounted) {
        setState(() {
          _items = items;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error scanning/loading media: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  bool _onSwipe(
    int previousIndex,
    int? currentIndex,
    CardSwiperDirection direction,
  ) {
    HapticFeedback.mediumImpact();

    if (previousIndex >= 0 && previousIndex < _items.length) {
      final item = _items[previousIndex];

      if (direction == CardSwiperDirection.right) {
        _handleKeep(item);
      } else if (direction == CardSwiperDirection.left) {
        _handleDelete(item);
      } else {
        _handleKeep(item);
      }
    }

    setState(() {
      if (currentIndex != null && currentIndex < _items.length) {
        _currentIndex = currentIndex;
      }
    });

    return true;
  }

  bool _onUndo(
    int? previousIndex,
    int currentIndex,
    CardSwiperDirection direction,
  ) {
    HapticFeedback.lightImpact();
    setState(() {
      _currentIndex = currentIndex;
    });
    return true;
  }

  void _onEnd() {
    setState(() {
      _isDeckFinished = true;
    });
  }

  void _handleKeep(MediaItem item) {
    _keptCount++;
    // Perform DB update asynchronously to guarantee strictly 60fps main-thread rendering
    Future.microtask(() async {
      try {
        await _scannerService.markProcessed(item);
      } catch (e) {
        debugPrint('Error marking item processed: $e');
      }
    });
  }

  void _handleDelete(MediaItem item) {
    _deletedCount++;
    _totalBytesDeleted += item.fileSize;

    // Perform disk deletion & DB deletion asynchronously to prevent frame drops
    Future.microtask(() async {
      try {
        final file = File(item.filePath);
        if (file.existsSync()) {
          file.deleteSync();
        }
      } on FileSystemException catch (e) {
        debugPrint('FileSystemException deleting file: ${e.message}');
      } catch (e) {
        debugPrint('Error deleting file: $e');
      }

      try {
        await _scannerService.deleteMediaItem(item);
      } catch (e) {
        debugPrint('Error deleting item from Isar: $e');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final String? currentImagePath = (_items.isNotEmpty && _currentIndex < _items.length)
        ? _items[_currentIndex].filePath
        : null;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 1. Dynamic Glassmorphism Background: focused card's image
          if (currentImagePath != null && File(currentImagePath).existsSync())
            Positioned.fill(
              child: Image.file(
                File(currentImagePath),
                fit: BoxFit.cover,
                gaplessPlayback: true,
                errorBuilder: (_, __, ___) => Container(color: const Color(0xFF0F172A)),
              ),
            )
          else
            Positioned.fill(
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF0F172A), Color(0xFF020617)],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
              ),
            ),

          // 2. Heavy Blur BackdropFilter + Dark Vignette Overlay
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 25.0, sigmaY: 25.0),
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.black.withOpacity(0.55),
                      Colors.black.withOpacity(0.85),
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
              ),
            ),
          ),

          // 3. Foreground Content
          SafeArea(
            child: Column(
              children: [
                _buildHeader(theme),
                Expanded(
                  child: _isLoading
                      ? const Center(
                          child: CircularProgressIndicator(color: Colors.white70),
                        )
                      : (_items.isEmpty || _isDeckFinished)
                          ? _buildEmptyState()
                          : _buildCardDeck(),
                ),
                if (!_isLoading && _items.isNotEmpty && !_isDeckFinished)
                  _buildBottomActionBar(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    final remaining = (_items.length - _currentIndex).clamp(0, _items.length);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
            onPressed: () => Navigator.pop(context),
            tooltip: 'Back',
          ),
          Column(
            children: [
              const Text(
                'Smart Cleanup',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  letterSpacing: -0.3,
                ),
              ),
              if (!_isLoading && _items.isNotEmpty && !_isDeckFinished)
                Text(
                  '$remaining remaining • ${_currentIndex + 1}/${_items.length}',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.65),
                    fontSize: 11.5,
                  ),
                ),
            ],
          ),
          IconButton(
            icon: Icon(
              _onlyScreenshots ? Icons.screenshot_rounded : Icons.filter_alt_outlined,
              color: _onlyScreenshots ? Colors.amberAccent : Colors.white70,
              size: 22,
            ),
            tooltip: _onlyScreenshots ? 'Showing Screenshots only' : 'Filter Screenshots',
            onPressed: () {
              setState(() {
                _onlyScreenshots = !_onlyScreenshots;
              });
              _scanAndLoad();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCardDeck() {
    return CardSwiper(
      controller: _controller,
      cardsCount: _items.length,
      numberOfCardsDisplayed: _items.length < 3 ? _items.length : 3,
      backCardOffset: const Offset(0, 36),
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
      cardBuilder: (context, index, percentX, percentY) {
        return _buildCard(_items[index], percentX.toDouble(), percentY.toDouble());
      },
      onSwipe: _onSwipe,
      onUndo: _onUndo,
      onEnd: _onEnd,
    );
  }

  Widget _buildCard(MediaItem item, double percentX, double percentY) {
    final file = File(item.filePath);
    final fileName = p.basename(item.filePath);
    final formattedSize = FileUtils.formatBytes(item.fileSize, 1);
    final formattedDate = FileUtils.formatDate(item.dateAdded);

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.12), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.45),
            blurRadius: 28,
            spreadRadius: 2,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Image Content
            file.existsSync()
                ? Image.file(
                    file,
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                    errorBuilder: (_, __, ___) => const Center(
                      child: Icon(Icons.broken_image_rounded, size: 56, color: Colors.white38),
                    ),
                  )
                : const Center(
                    child: Icon(Icons.broken_image_rounded, size: 56, color: Colors.white38),
                  ),

            // Bottom Gradient Scrim
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 150,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.transparent,
                      Colors.black.withOpacity(0.9),
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
              ),
            ),

            // Item Metadata Overlay
            Positioned(
              left: 20,
              right: 20,
              bottom: 20,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      if (item.isScreenshot)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          margin: const EdgeInsets.only(right: 8),
                          decoration: BoxDecoration(
                            color: Colors.amber.withOpacity(0.25),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.amberAccent.withOpacity(0.6)),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.screenshot_rounded, size: 12, color: Colors.amberAccent),
                              SizedBox(width: 4),
                              Text(
                                'SCREENSHOT',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.amberAccent,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          formattedSize,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    formattedDate,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withOpacity(0.7),
                    ),
                  ),
                ],
              ),
            ),

            // Dynamic Swipe Badges (KEEP on right swipe, DELETE on left swipe)
            if (percentX > 15)
              Positioned(
                top: 28,
                left: 28,
                child: Transform.rotate(
                  angle: -0.15,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00E676).withOpacity((percentX / 100).clamp(0.0, 0.95)),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white, width: 2.5),
                    ),
                    child: const Text(
                      'KEEP',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 2,
                      ),
                    ),
                  ),
                ),
              ),

            if (percentX < -15)
              Positioned(
                top: 28,
                right: 28,
                child: Transform.rotate(
                  angle: 0.15,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withOpacity(((-percentX) / 100).clamp(0.0, 0.95)),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white, width: 2.5),
                    ),
                    child: const Text(
                      'DELETE',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 2,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomActionBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(36, 12, 36, 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // Delete Button (Left Swipe)
          _buildActionButton(
            icon: Icons.delete_outline_rounded,
            color: Colors.redAccent,
            label: 'Delete',
            sublabel: 'Swipe Left',
            onTap: () {
              HapticFeedback.lightImpact();
              _controller.swipe(CardSwiperDirection.left);
            },
          ),

          // Undo Button
          _buildUndoButton(),

          // Keep Button (Right Swipe)
          _buildActionButton(
            icon: Icons.check_rounded,
            color: const Color(0xFF00E676),
            label: 'Keep',
            sublabel: 'Swipe Right',
            onTap: () {
              HapticFeedback.lightImpact();
              _controller.swipe(CardSwiperDirection.right);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required Color color,
    required String label,
    required String sublabel,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(30),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withOpacity(0.18),
                border: Border.all(color: color.withOpacity(0.55), width: 2),
                boxShadow: [
                  BoxShadow(
                    color: color.withOpacity(0.2),
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Icon(icon, color: color, size: 28),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.bold,
                fontSize: 12.5,
              ),
            ),
            Text(
              sublabel,
              style: TextStyle(
                color: Colors.white.withOpacity(0.5),
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUndoButton() {
    return InkWell(
      onTap: () {
        HapticFeedback.lightImpact();
        _controller.undo();
      },
      borderRadius: BorderRadius.circular(24),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.12),
                border: Border.all(color: Colors.white.withOpacity(0.25), width: 1.5),
              ),
              child: const Icon(Icons.undo_rounded, color: Colors.white70, size: 20),
            ),
            const SizedBox(height: 6),
            Text(
              'Undo',
              style: TextStyle(
                color: Colors.white.withOpacity(0.7),
                fontWeight: FontWeight.w600,
                fontSize: 11.5,
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 36),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(26),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF00E676).withOpacity(0.15),
                border: Border.all(color: const Color(0xFF00E676).withOpacity(0.4), width: 2),
              ),
              child: const Icon(
                Icons.check_circle_outline_rounded,
                size: 68,
                color: Color(0xFF00E676),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'All Clean!',
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              _deletedCount > 0
                  ? 'You deleted $_deletedCount items (${FileUtils.formatBytes(_totalBytesDeleted, 1)} freed) and kept $_keptCount items.'
                  : 'No unprocessed screenshots or media to review.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Colors.white.withOpacity(0.7),
                height: 1.4,
              ),
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              icon: const Icon(Icons.refresh_rounded, size: 20),
              label: const Text('Rescan Storage'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF3B82F6),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              onPressed: _scanAndLoad,
            ),
          ],
        ),
      ),
    );
  }
}
