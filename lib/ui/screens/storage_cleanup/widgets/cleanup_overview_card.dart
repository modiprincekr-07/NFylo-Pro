import 'dart:math';
import 'package:flutter/material.dart';
import '../../../../core/icon_fonts/broken_icons.dart';
import '../../../../core/utils.dart';
import '../services/storage_cleanup_service.dart';

class CleanupOverviewCard extends StatelessWidget {
  final StorageCleanupResult result;
  final int selectedCategoryIndex;
  final void Function(int) onSelectCategory;

  const CleanupOverviewCard({
    super.key,
    required this.result,
    required this.selectedCategoryIndex,
    required this.onSelectCategory,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final totalCleanup = result.totalPotentialCleanupBytes;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 12),
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
          // Total Potential Clean Bar
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF10B981), Color(0xFF059669)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF10B981).withOpacity(0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: const Icon(
                  Broken.brush_2,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Potential Space to Reclaim',
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.textTheme.bodySmall?.color?.withOpacity(0.6),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      FileUtils.formatBytes(totalCleanup, 2),
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 18),

          // 3 Category Shortcut Chips
          Row(
            children: [
              Expanded(
                child: _buildCategoryChip(
                  theme: theme,
                  index: 0,
                  icon: Broken.document_copy,
                  title: 'Duplicates',
                  bytes: result.totalDuplicatesWastedBytes,
                  count: result.duplicateGroups.length,
                  unitLabel: 'sets',
                  accentColor: const Color(0xFFEF4444),
                  isSelected: selectedCategoryIndex == 0,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildCategoryChip(
                  theme: theme,
                  index: 1,
                  icon: Broken.document_upload,
                  title: 'Large Files',
                  bytes: result.totalLargeFilesBytes,
                  count: result.largeFiles.length,
                  unitLabel: 'files',
                  accentColor: const Color(0xFF3B82F6),
                  isSelected: selectedCategoryIndex == 1,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildCategoryChip(
                  theme: theme,
                  index: 2,
                  icon: Broken.clock,
                  title: 'Old Files',
                  bytes: result.totalOldFilesBytes,
                  count: result.oldFiles.length,
                  unitLabel: 'files',
                  accentColor: const Color(0xFFF59E0B),
                  isSelected: selectedCategoryIndex == 2,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryChip({
    required ThemeData theme,
    required int index,
    required IconData icon,
    required String title,
    required int bytes,
    required int count,
    required String unitLabel,
    required Color accentColor,
    required bool isSelected,
  }) {
    return InkWell(
      onTap: () => onSelectCategory(index),
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? accentColor.withOpacity(0.12)
              : theme.colorScheme.surfaceVariant.withOpacity(0.2),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? accentColor.withOpacity(0.5)
                : theme.dividerColor.withOpacity(0.06),
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 16, color: accentColor),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                      color: isSelected ? accentColor : theme.textTheme.bodyMedium?.color,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              FileUtils.formatBytes(bytes, 1),
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(
              '$count $unitLabel',
              style: TextStyle(
                fontSize: 10.5,
                color: theme.textTheme.bodySmall?.color?.withOpacity(0.55),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
