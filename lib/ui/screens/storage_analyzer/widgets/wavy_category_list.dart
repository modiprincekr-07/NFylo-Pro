import 'dart:math';
import 'package:flutter/material.dart';
import '../../../../core/icon_fonts/broken_icons.dart';
import '../../../../core/utils.dart';
import '../../media_category_screen.dart';
import '../app_manager_screen.dart';
import '../models/storage_analysis_models.dart';

class WavyCategoryList extends StatefulWidget {
  final List<StorageCategoryInfo> categories;
  final int totalStorage;
  final int usedStorage;
  final Function(StorageCategoryInfo)? onCategoryTap;

  const WavyCategoryList({
    super.key,
    required this.categories,
    required this.totalStorage,
    required this.usedStorage,
    this.onCategoryTap,
  });

  @override
  State<WavyCategoryList> createState() => _WavyCategoryListState();
}

class _WavyCategoryListState extends State<WavyCategoryList> with SingleTickerProviderStateMixin {
  late AnimationController _waveController;

  @override
  void initState() {
    super.initState();
    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();
  }

  @override
  void dispose() {
    _waveController.dispose();
    super.dispose();
  }

  void _handleCategoryTap(BuildContext context, StorageCategoryInfo cat) {
    if (widget.onCategoryTap != null) {
      widget.onCategoryTap!(cat);
      return;
    }

    if (cat.id == 'apps') {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const AppManagerScreen()),
      );
    } else if (cat.mediaType != null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => MediaCategoryScreen(mediaType: cat.mediaType!),
        ),
      );
    } else if (cat.id == 'pdfs' || cat.id == 'code' || cat.id == 'text') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => const MediaCategoryScreen(mediaType: MediaType.documents),
        ),
      );
    } else if (cat.id == 'archives') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => const MediaCategoryScreen(mediaType: MediaType.archives),
        ),
      );
    } else if (cat.id == 'apks') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => const MediaCategoryScreen(mediaType: MediaType.apks),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sortedCategories = List<StorageCategoryInfo>.from(widget.categories)
      ..sort((a, b) => b.size.compareTo(a.size));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Category Breakdown',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              Text(
                '${widget.categories.length} categories',
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.onSurface.withOpacity(0.55),
                ),
              ),
            ],
          ),
        ),
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: sortedCategories.length,
          itemBuilder: (context, index) {
            final cat = sortedCategories[index];
            final double proportion = widget.usedStorage > 0 ? (cat.size / widget.usedStorage) : 0.0;
            final double percent = proportion * 100.0;

            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: theme.dividerColor.withOpacity(0.06)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.015),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: InkWell(
                onTap: () => _handleCategoryTap(context, cat),
                borderRadius: BorderRadius.circular(18),
                child: Padding(
                  padding: const EdgeInsets.all(14.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: cat.color.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Icon(cat.icon, color: cat.color, size: 22),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      cat.name,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                    ),
                                    Text(
                                      FileUtils.formatBytes(cat.size, 2),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 3),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      cat.count > 0 ? '${cat.count} files' : 'Calculating files...',
                                      style: TextStyle(
                                        color: theme.colorScheme.onSurface.withOpacity(0.5),
                                        fontSize: 11.5,
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                      decoration: BoxDecoration(
                                        color: cat.color.withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        '${percent.toStringAsFixed(1)}%',
                                        style: TextStyle(
                                          color: cat.color,
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(
                            Broken.arrow_right_3,
                            size: 16,
                            color: theme.colorScheme.onSurface.withOpacity(0.3),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),

                      // Wavy / Animated Progress Bar
                      AnimatedBuilder(
                        animation: _waveController,
                        builder: (context, child) {
                          return ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: SizedBox(
                              height: 7,
                              child: CustomPaint(
                                painter: _WavyProgressPainter(
                                  progress: proportion.clamp(0.0, 1.0),
                                  color: cat.color,
                                  wavePhase: _waveController.value * 2 * pi,
                                  backgroundColor: theme.colorScheme.surfaceVariant.withOpacity(0.3),
                                ),
                                size: const Size(double.infinity, 7),
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _WavyProgressPainter extends CustomPainter {
  final double progress;
  final Color color;
  final double wavePhase;
  final Color backgroundColor;

  _WavyProgressPainter({
    required this.progress,
    required this.color,
    required this.wavePhase,
    required this.backgroundColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Background track
    final bgPaint = Paint()..color = backgroundColor;
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, size.width, size.height), const Radius.circular(6)),
      bgPaint,
    );

    if (progress <= 0) return;

    final double fillWidth = size.width * progress;

    // Fill with wavy top edge
    final Paint fillPaint = Paint()
      ..shader = LinearGradient(
        colors: [
          color.withOpacity(0.75),
          color,
        ],
      ).createShader(Rect.fromLTWH(0, 0, fillWidth, size.height));

    final path = Path();
    path.moveTo(0, size.height);
    path.lineTo(0, 0);

    // Draw wavy crest along top of filled segment
    final double waveHeight = 1.2;
    for (double x = 0; x <= fillWidth; x += 2) {
      final double y = sin((x / 18.0) + wavePhase) * waveHeight + (waveHeight);
      path.lineTo(x, y.clamp(0.0, size.height));
    }

    path.lineTo(fillWidth, size.height);
    path.close();

    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, fillWidth, size.height), const Radius.circular(6)));
    canvas.drawPath(path, fillPaint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _WavyProgressPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.wavePhase != wavePhase ||
        oldDelegate.color != color;
  }
}
