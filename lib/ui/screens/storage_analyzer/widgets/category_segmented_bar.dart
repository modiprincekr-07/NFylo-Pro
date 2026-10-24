import 'package:flutter/material.dart';
import '../../../../core/utils.dart';
import '../models/storage_analysis_models.dart';

class CategorySegmentedBar extends StatelessWidget {
  final List<StorageCategoryInfo> categories;
  final int totalStorage;
  final int usedStorage;
  final double animationValue;
  final Function(StorageCategoryInfo)? onCategoryTap;

  const CategorySegmentedBar({
    super.key,
    required this.categories,
    required this.totalStorage,
    required this.usedStorage,
    this.animationValue = 1.0,
    this.onCategoryTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final activeCategories = categories.where((c) => c.size > 0).toList();
    final double usedPercent = totalStorage > 0 ? (usedStorage / totalStorage) * 100 : 0.0;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: theme.dividerColor.withOpacity(0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header info
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Category Distribution',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${usedPercent.toStringAsFixed(1)}% Used',
                  style: TextStyle(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Multi-color Segmented Progress Bar
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              height: 16,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final totalWidth = constraints.maxWidth;
                  if (usedStorage <= 0 || activeCategories.isEmpty) {
                    return Container(
                      width: totalWidth,
                      color: theme.colorScheme.surfaceVariant.withOpacity(0.4),
                    );
                  }

                  return Row(
                    children: activeCategories.map((cat) {
                      final double proportion = (cat.size / usedStorage) * animationValue;
                      final double segWidth = (proportion * totalWidth).clamp(2.0, totalWidth);

                      return Container(
                        width: segWidth,
                        height: 16,
                        margin: const EdgeInsets.only(right: 1.5),
                        decoration: BoxDecoration(
                          color: cat.color,
                        ),
                      );
                    }).toList(),
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 18),

          // Legend grid with percentage and file count
          Wrap(
            spacing: 12,
            runSpacing: 10,
            children: activeCategories.map((cat) {
              final double catPercent = usedStorage > 0 ? (cat.size / usedStorage) * 100 : 0.0;

              return InkWell(
                onTap: onCategoryTap != null ? () => onCategoryTap!(cat) : null,
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: cat.color.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: cat.color.withOpacity(0.15)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: cat.color,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        cat.name,
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 11.5),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '(${catPercent.toStringAsFixed(1)}%)',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.bold,
                          color: cat.color,
                        ),
                      ),
                      if (cat.count > 0) ...[
                        const SizedBox(width: 4),
                        Text(
                          '• ${cat.count}',
                          style: TextStyle(
                            fontSize: 10,
                            color: theme.colorScheme.onSurface.withOpacity(0.55),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
