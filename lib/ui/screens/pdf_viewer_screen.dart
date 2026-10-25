import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';

import '../../core/icon_fonts/broken_icons.dart';
import '../../core/icon_fonts/nfile_icons.dart';
import '../../core/utils.dart';
import '../../services/folder_share_service.dart';
import '../widgets/pdf_tools_bottom_sheet.dart';

class PdfViewerScreen extends StatefulWidget {
  final String filePath;

  const PdfViewerScreen({
    super.key,
    required this.filePath,
  });

  @override
  State<PdfViewerScreen> createState() => _PdfViewerScreenState();
}

class _PdfViewerScreenState extends State<PdfViewerScreen> {
  final GlobalKey<SfPdfViewerState> _pdfViewerKey = GlobalKey();
  late final PdfViewerController _pdfViewerController;
  late final PdfTextSearchResult _searchResult;

  int _pageCount = 0;
  int _currentPage = 1;
  bool _isSearchActive = false;
  final TextEditingController _searchController = TextEditingController();
  bool _isNightMode = false;
  double _currentZoomLevel = 1.0;

  @override
  void initState() {
    super.initState();
    _pdfViewerController = PdfViewerController();
    _searchResult = PdfTextSearchResult();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchResult.dispose();
    _pdfViewerController.dispose();
    super.dispose();
  }

  void _showJumpToPageDialog() {
    final controller = TextEditingController(text: '$_currentPage');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Jump to Page', style: TextStyle(fontWeight: FontWeight.bold)),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: InputDecoration(
            hintText: 'Enter page (1-$_pageCount)',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final page = int.tryParse(controller.text.trim());
              if (page != null && page >= 1 && page <= _pageCount) {
                _pdfViewerController.jumpToPage(page);
                Navigator.pop(ctx);
              }
            },
            child: const Text('Go'),
          ),
        ],
      ),
    );
  }

  // Inverted color matrix for buttery night mode
  static const ColorFilter _nightFilter = ColorFilter.matrix([
    -1, 0, 0, 0, 255,
    0, -1, 0, 0, 255,
    0, 0, -1, 0, 255,
    0, 0, 0, 1, 0,
  ]);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final fileName = p.basename(widget.filePath);

    final pdfWidget = SfPdfViewer.file(
      File(widget.filePath),
      key: _pdfViewerKey,
      controller: _pdfViewerController,
      scrollPhysics: const BouncingScrollPhysics(),
      currentSearchTextHighlightColor: Colors.amber.withOpacity(0.55),
      otherSearchTextHighlightColor: Colors.yellow.withOpacity(0.3),
      onDocumentLoaded: (PdfDocumentLoadedDetails details) {
        setState(() {
          _pageCount = details.document.pages.count;
        });
      },
      onPageChanged: (PdfPageChangedDetails details) {
        setState(() {
          _currentPage = details.newPageNumber;
        });
      },
    );

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF101018) : const Color(0xFFF3F4F6),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: isDark ? const Color(0xFF181824) : Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: _isSearchActive
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'Search in document...',
                  border: InputBorder.none,
                  hintStyle: TextStyle(
                    color: theme.textTheme.bodySmall?.color?.withOpacity(0.5),
                  ),
                ),
                onSubmitted: (text) {
                  if (text.isNotEmpty) {
                    _searchResult = _pdfViewerController.searchText(text);
                    _searchResult.addListener(() {
                      if (mounted) setState(() {});
                    });
                  }
                },
              )
            : Row(
                children: [
                  Hero(
                    tag: widget.filePath,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.redAccent.withOpacity(0.18),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.picture_as_pdf_rounded,
                        color: Colors.redAccent,
                        size: 20,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          fileName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (_pageCount > 0)
                          Text(
                            'Page $_currentPage of $_pageCount',
                            style: TextStyle(
                              fontSize: 11,
                              color: theme.textTheme.bodySmall?.color?.withOpacity(0.65),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
        actions: [
          if (_isSearchActive) ...[
            if (_searchResult.totalInstanceCount > 0)
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    '${_searchResult.currentInstanceIndex}/${_searchResult.totalInstanceCount}',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            IconButton(
              icon: const Icon(Icons.navigate_before_rounded),
              onPressed: () {
                _searchResult.previousInstance();
              },
            ),
            IconButton(
              icon: const Icon(Icons.navigate_next_rounded),
              onPressed: () {
                _searchResult.nextInstance();
              },
            ),
            IconButton(
              icon: const Icon(Icons.close_rounded),
              onPressed: () {
                setState(() {
                  _isSearchActive = false;
                  _searchResult.clear();
                  _searchController.clear();
                });
              },
            ),
          ] else ...[
            IconButton(
              tooltip: 'Search',
              icon: const Icon(Broken.search_normal_1, size: 20),
              onPressed: () {
                setState(() {
                  _isSearchActive = true;
                });
              },
            ),
            IconButton(
              tooltip: 'Bookmarks',
              icon: const Icon(Broken.bookmark, size: 20),
              onPressed: () {
                _pdfViewerKey.currentState?.openBookmarkView();
              },
            ),
            IconButton(
              tooltip: 'Night Mode',
              icon: Icon(
                _isNightMode ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
                size: 20,
              ),
              onPressed: () {
                setState(() {
                  _isNightMode = !_isNightMode;
                });
              },
            ),
            IconButton(
              tooltip: 'PDF Tools',
              icon: const Icon(Icons.tune_rounded, size: 20),
              onPressed: () {
                PdfToolsBottomSheet.show(context, File(widget.filePath));
              },
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert_rounded, size: 20),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              onSelected: (action) async {
                if (action == 'jump') {
                  _showJumpToPageDialog();
                } else if (action == 'share') {
                  FolderShareService.sharePaths(context, [widget.filePath]);
                } else if (action == 'open_with') {
                  OpenFilex.open(widget.filePath);
                } else if (action == 'fit') {
                  _pdfViewerController.zoomLevel = 1.0;
                }
              },
              itemBuilder: (ctx) => [
                const PopupMenuItem(
                  value: 'jump',
                  child: Row(
                    children: [
                      Icon(Icons.directions_walk_rounded, size: 18),
                      SizedBox(width: 10),
                      Text('Jump to page'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'fit',
                  child: Row(
                    children: [
                      Icon(Icons.fit_screen_rounded, size: 18),
                      SizedBox(width: 10),
                      Text('Reset Zoom'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'share',
                  child: Row(
                    children: [
                      Icon(Icons.share_outlined, size: 18),
                      SizedBox(width: 10),
                      Text('Share'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'open_with',
                  child: Row(
                    children: [
                      Icon(Broken.eye, size: 18),
                      SizedBox(width: 10),
                      Text('Open with external app'),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
      body: Stack(
        children: [
          _isNightMode
              ? ColorFiltered(colorFilter: _nightFilter, child: pdfWidget)
              : pdfWidget,

          // Floating page indicator pill
          if (_pageCount > 0)
            Positioned(
              bottom: 24,
              right: 20,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: _showJumpToPageDialog,
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF1E1E2C).withOpacity(0.92)
                          : Colors.white.withOpacity(0.92),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isDark ? Colors.white12 : Colors.black12,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.18),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.pages_rounded, size: 14),
                        const SizedBox(width: 6),
                        Text(
                          '$_currentPage / $_pageCount',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
