import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_manager/photo_manager.dart';

class SmartCleanupScreen extends StatefulWidget {
  const SmartCleanupScreen({super.key});

  @override
  State<SmartCleanupScreen> createState() => _SmartCleanupScreenState();
}

class _SmartCleanupScreenState extends State<SmartCleanupScreen> {
  List<AssetEntity> _photos = [];
  bool _isLoading = true;
  bool _permissionDenied = false;
  final Map<String, Uint8List> _thumbCache = {};

  @override
  void initState() {
    super.initState();
    _fetchMedia();
  }

  /// Request PhotoManager permission and fetch the recent 50 items
  /// from "Screenshots" or "Camera" albums.
  Future<void> _fetchMedia() async {
    setState(() {
      _isLoading = true;
      _permissionDenied = false;
    });

    try {
      final PermissionState ps = await PhotoManager.requestPermissionExtend();
      if (!ps.isAuth && !ps.hasAccess) {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _permissionDenied = true;
          });
        }
        return;
      }

      final List<AssetPathEntity> albums = await PhotoManager.getAssetPathList(
        type: RequestType.image,
        onlyAll: false,
      );

      // Filter for Screenshots or Camera albums
      List<AssetPathEntity> targetAlbums = albums.where((album) {
        final name = album.name.toLowerCase();
        return name.contains('screenshot') ||
            name.contains('camera') ||
            name.contains('dcim');
      }).toList();

      // Fallback if specific album names are not present
      if (targetAlbums.isEmpty && albums.isNotEmpty) {
        targetAlbums = [albums.first];
      }

      final List<AssetEntity> collected = [];
      for (final album in targetAlbums) {
        final count = await album.assetCountAsync;
        if (count > 0) {
          final assets = await album.getAssetListRange(start: 0, end: 50);
          collected.addAll(assets);
        }
      }

      // Deduplicate by ID and sort descending by createDateTime
      final Map<String, AssetEntity> unique = {};
      for (final asset in collected) {
        unique[asset.id] = asset;
      }
      final sorted = unique.values.toList()
        ..sort((a, b) => b.createDateTime.compareTo(a.createDateTime));

      final recent50 = sorted.take(50).toList();

      if (mounted) {
        setState(() {
          _photos = recent50;
          _isLoading = false;
          _permissionDenied = false;
        });
        _preloadThumbnails();
      }
    } catch (e) {
      debugPrint('Error fetching media for smart cleanup: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _preloadThumbnails() {
    for (int i = 0; i < 4 && i < _photos.length; i++) {
      final asset = _photos[i];
      if (!_thumbCache.containsKey(asset.id)) {
        asset
            .thumbnailDataWithSize(const ThumbnailSize(1080, 1920))
            .then((data) {
          if (data != null && mounted) {
            setState(() {
              _thumbCache[asset.id] = data;
            });
          }
        });
      }
    }
  }

  Future<void> _trashTopAsset() async {
    if (_photos.isEmpty) return;
    HapticFeedback.heavyImpact();
    final asset = _photos.removeAt(0);
    _thumbCache.remove(asset.id);
    _preloadThumbnails();
    setState(() {});

    try {
      await PhotoManager.editor.deleteWithTrash([asset]);
    } catch (e) {
      debugPrint('Error moving photo to native trash: $e');
    }
  }

  void _keepTopAsset() {
    if (_photos.isEmpty) return;
    HapticFeedback.heavyImpact();
    final asset = _photos.removeAt(0);
    _thumbCache.remove(asset.id);
    _preloadThumbnails();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final topAsset = _photos.isNotEmpty ? _photos.first : null;
    final topThumb = topAsset != null ? _thumbCache[topAsset.id] : null;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0E1A),
      body: Stack(
        children: [
          // 1. Dark, Premium Background Gradient
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Color(0xFF0B0F19),
                    Color(0xFF0E1322),
                    Color(0xFF030712),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
          ),

          // 2. Dynamic Ambient Background from top card
          if (topThumb != null)
            Positioned.fill(
              child: Opacity(
                opacity: 0.28,
                child: Image.memory(
                  topThumb,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                ),
              ),
            ),

          // 3. Glassmorphism BackdropFilter Effect behind the main card
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
              child: Container(
                color: Colors.black.withOpacity(0.35),
              ),
            ),
          ),

          // 4. Main Foreground UI
          SafeArea(
            child: Column(
              children: [
                _buildHeader(context),
                Expanded(
                  child: _isLoading
                      ? const Center(
                          child: CircularProgressIndicator(
                            color: Colors.amberAccent,
                          ),
                        )
                      : _permissionDenied
                          ? _buildPermissionDeniedView()
                          : _photos.isEmpty
                              ? _buildEmptyState()
                              : _buildCardStack(),
                ),
                if (!_isLoading && !_permissionDenied && _photos.isNotEmpty)
                  _buildBottomActions(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
            tooltip: 'Back',
          ),
          Column(
            children: [
              const Text(
                'Smart Cleanup',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 19,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _photos.isNotEmpty
                    ? '${_photos.length} photos to review'
                    : 'Screenshots & Camera',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.6),
                  fontSize: 12,
                ),
              ),
            ],
          ),
          IconButton(
            onPressed: _isLoading ? null : _fetchMedia,
            icon: const Icon(Icons.refresh_rounded, color: Colors.white),
            tooltip: 'Reload',
          ),
        ],
      ),
    );
  }

  Widget _buildCardStack() {
    final int renderCount = _photos.length < 3 ? _photos.length : 3;
    final List<Widget> children = [];

    // Render from back to front in the Stack (index renderCount - 1 down to 0)
    for (int i = renderCount - 1; i >= 0; i--) {
      final asset = _photos[i];
      final double scale = i == 0 ? 1.0 : (i == 1 ? 0.94 : 0.88);
      final double translateY = i == 0 ? 0.0 : (i == 1 ? 14.0 : 28.0);
      final double opacity = i == 0 ? 1.0 : (i == 1 ? 0.82 : 0.60);

      Widget card = Transform.translate(
        offset: Offset(0, translateY),
        child: Transform.scale(
          scale: scale,
          child: Opacity(
            opacity: opacity,
            child: _buildPhotoCard(asset),
          ),
        ),
      );

      // Top card wrapped in Dismissible for Tinder-style swiping
      if (i == 0) {
        card = Dismissible(
          key: ValueKey(asset.id),
          direction: DismissDirection.horizontal,
          // background (Left Swipe): Red container with Trash icon
          background: Container(
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 28),
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.85),
              borderRadius: BorderRadius.circular(24),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.delete_outline_rounded, color: Colors.white, size: 40),
                SizedBox(width: 10),
                Text(
                  'Trash',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                  ),
                ),
              ],
            ),
          ),
          // secondaryBackground (Right Swipe): Green container with Keep/Check icon
          secondaryBackground: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.symmetric(horizontal: 28),
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.85),
              borderRadius: BorderRadius.circular(24),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  'Keep',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                  ),
                ),
                SizedBox(width: 10),
                Icon(Icons.check_circle_outline_rounded, color: Colors.white, size: 40),
              ],
            ),
          ),
          onDismissed: (direction) async {
            HapticFeedback.heavyImpact();
            final removedAsset = _photos.removeAt(0);
            _thumbCache.remove(removedAsset.id);
            _preloadThumbnails();
            setState(() {});

            if (direction == DismissDirection.endToStart) {
              // If swiped LEFT (Trash): Remove item from UI state, THEN call deleteWithTrash
              try {
                await PhotoManager.editor.deleteWithTrash([removedAsset]);
              } catch (e) {
                debugPrint('Error deleting asset with trash: $e');
              }
            } else {
              // If swiped RIGHT (Keep): Just remove the item from the UI state (remains safely in storage)
            }
          },
          child: card,
        );
      }

      children.add(card);
    }

    return Center(
      child: Stack(
        alignment: Alignment.center,
        children: children,
      ),
    );
  }

  Widget _buildPhotoCard(AssetEntity asset) {
    final cached = _thumbCache[asset.id];
    final size = MediaQuery.of(context).size;
    final cardWidth = size.width * 0.88;
    final cardHeight = size.height * 0.62;

    return Container(
      width: cardWidth,
      height: cardHeight,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.4),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Card Image
            if (cached != null)
              Image.memory(
                cached,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                width: double.infinity,
                height: double.infinity,
              )
            else
              FutureBuilder<Uint8List?>(
                future: asset.thumbnailDataWithSize(const ThumbnailSize(1080, 1920)),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.done &&
                      snapshot.data != null) {
                    return Image.memory(
                      snapshot.data!,
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                      width: double.infinity,
                      height: double.infinity,
                    );
                  }
                  return Container(
                    color: const Color(0xFF1E293B),
                    child: const Center(
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white38),
                      ),
                    ),
                  );
                },
              ),

            // Bottom Gradient Scrim
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 140,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.transparent,
                      Colors.black.withOpacity(0.85),
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
              ),
            ),

            // Metadata info
            Positioned(
              left: 18,
              right: 18,
              bottom: 16,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    asset.title ?? 'Screenshot / Photo',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 17,
                      shadows: [
                        Shadow(color: Colors.black87, blurRadius: 4),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        Icons.calendar_today_rounded,
                        size: 13,
                        color: Colors.white.withOpacity(0.8),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        '${asset.createDateTime.year}-${asset.createDateTime.month.toString().padLeft(2, '0')}-${asset.createDateTime.day.toString().padLeft(2, '0')}',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.85),
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Icon(
                        Icons.photo_size_select_actual_outlined,
                        size: 14,
                        color: Colors.white.withOpacity(0.8),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        '${asset.width} × ${asset.height}',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.85),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Card Glassmorphism Border Overlay
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: Colors.white.withOpacity(0.18),
                  width: 1.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomActions() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 18),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // Trash Action Button
          _buildActionButton(
            icon: Icons.delete_outline_rounded,
            color: Colors.redAccent,
            label: 'Trash',
            onTap: _trashTopAsset,
          ),
          // Keep Action Button
          _buildActionButton(
            icon: Icons.check_rounded,
            color: Colors.greenAccent.shade400,
            label: 'Keep',
            onTap: _keepTopAsset,
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required Color color,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(32),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
        decoration: BoxDecoration(
          color: color.withOpacity(0.14),
          borderRadius: BorderRadius.circular(32),
          border: Border.all(
            color: color.withOpacity(0.4),
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 26),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.06),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withOpacity(0.12)),
              ),
              child: const Icon(
                Icons.check_circle_outline_rounded,
                size: 64,
                color: Colors.greenAccent,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'All Cleaned Up! 🎉',
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'No screenshots or photos left to review.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withOpacity(0.65),
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _fetchMedia,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Scan Again'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white.withOpacity(0.12),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: Colors.white.withOpacity(0.2)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPermissionDeniedView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: Colors.redAccent.withOpacity(0.12),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.redAccent.withOpacity(0.3)),
              ),
              child: const Icon(
                Icons.no_photography_outlined,
                size: 64,
                color: Colors.redAccent,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Photo Access Required',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Smart Cleanup requires photo permission to scan screenshots and camera media.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withOpacity(0.65),
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _fetchMedia,
              icon: const Icon(Icons.lock_open_rounded),
              label: const Text('Grant Access'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.amberAccent,
                foregroundColor: Colors.black87,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
