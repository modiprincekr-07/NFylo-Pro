import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:path/path.dart' as p;
import '../../providers/file_manager_provider.dart';
import '../../providers/media_provider.dart';
import '../../models/file_item_model.dart';
import '../../core/icon_fonts/broken_icons.dart';
import '../../services/preferences_service.dart';
import '../../services/natural_language_search_parser.dart';
import '../widgets/file_item.dart';
import '../widgets/folder_item.dart';
import '../widgets/nfile_icon.dart';
import '../widgets/quick_convert_bottom_sheet.dart';
import '../../utils/ecosystem_handoff.dart';
import 'tools/video_trimmer_screen.dart';

class SearchTabScreen extends StatefulWidget {
  final Function(int) onNavigateTab;
  const SearchTabScreen({super.key, required this.onNavigateTab});

  @override
  State<SearchTabScreen> createState() => _SearchTabScreenState();
}

class _CategoryChipData {
  final String label;
  final IconData icon;
  final Color color;
  const _CategoryChipData(this.label, this.icon, this.color);
}

class _SmartChipData {
  final String label;
  final IconData icon;
  final Color color;
  const _SmartChipData(this.label, this.icon, this.color);
}

class _SearchTabScreenState extends State<SearchTabScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  String _query = '';
  String _selectedFilter = 'All';
  ParsedSearchQuery? _parsedQuery;
  List<FileItemModel> _results = [];
  bool _isSearching = false;
  StreamSubscription<FileSystemEntity>? _searchSubscription;
  final Set<String> _seenPaths = {};

  final List<_CategoryChipData> _categoryFilters = const [
    _CategoryChipData('All', Broken.category_2, Color(0xFF64748B)),
    _CategoryChipData('Images', Broken.image, Color(0xFF8B5CF6)),
    _CategoryChipData('Videos', Broken.video, Color(0xFFEF4444)),
    _CategoryChipData('Audio', Broken.music, Color(0xFFF97316)),
    _CategoryChipData('Docs', Broken.document, Color(0xFF3B82F6)),
    _CategoryChipData('PDFs', Broken.document_text, Color(0xFFEC4899)),
    _CategoryChipData('Archives', Broken.archive, Color(0xFFF59E0B)),
  ];

  final List<_SmartChipData> _smartFilterChips = const [
    _SmartChipData('Screenshots', Broken.camera, Color(0xFF8B5CF6)),
    _SmartChipData('PDFs bigger than 10 MB', Broken.document_text, Color(0xFFEC4899)),
    _SmartChipData('Videos from last month', Broken.video, Color(0xFFEF4444)),
    _SmartChipData('Photos from yesterday', Broken.image, Color(0xFFA855F7)),
    _SmartChipData('WhatsApp images', Broken.message, Color(0xFF10B981)),
    _SmartChipData('Large files', Broken.box, Color(0xFF3B82F6)),
    _SmartChipData('Downloads this week', Broken.document_download, Color(0xFF06B6D4)),
    _SmartChipData('Documents modified today', Broken.document, Color(0xFFF59E0B)),
  ];

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _searchSubscription?.cancel();
    super.dispose();
  }

  void _executeSearch(String query) {
    _searchSubscription?.cancel();
    _seenPaths.clear();

    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      setState(() {
        _query = '';
        _parsedQuery = null;
        _results = [];
        _isSearching = false;
      });
      return;
    }

    final parsed = NaturalLanguageSearchParser.parse(trimmed);

    setState(() {
      _query = trimmed;
      _parsedQuery = parsed;
      _results = [];
      _isSearching = true;
    });

    _saveRecentSearch(trimmed);

    final rootPath = '/storage/emulated/0';
    final rootDir = Directory(rootPath);
    if (!rootDir.existsSync()) {
      setState(() => _isSearching = false);
      return;
    }

    final mediaProvider = context.read<MediaProvider>();
    final List<FileItemModel> instantResults = [];

    // Instant match from cached audios if applicable
    if (_selectedFilter == 'All' || _selectedFilter == 'Audio') {
      if (parsed.fileTypes.isEmpty || parsed.fileTypes.contains('audio')) {
        for (final song in mediaProvider.audios) {
          final songPath = song.data;
          if (!_seenPaths.contains(songPath)) {
            final item = FileItemModel(
              entity: File(songPath),
              name: song.title,
              path: songPath,
              isDirectory: false,
              size: song.size,
              modified: DateTime.fromMillisecondsSinceEpoch((song.dateModified ?? 0) * 1000),
            );

            if (parsed.matches(item) && _matchesCategoryFilter(item)) {
              _seenPaths.add(songPath);
              instantResults.add(item);
            }
          }
        }
      }
    }

    if (instantResults.isNotEmpty) {
      setState(() => _results = List.from(instantResults));
    }

    DateTime lastUiBatch = DateTime.now();
    final List<FileItemModel> batch = [];

    _searchSubscription = rootDir.list(recursive: true, followLinks: false).listen(
      (entity) {
        if (_seenPaths.contains(entity.path)) return;

        try {
          final item = FileItemModel.fromEntity(entity);

          if (parsed.matches(item) && _matchesCategoryFilter(item)) {
            _seenPaths.add(entity.path);
            batch.add(item);

            final now = DateTime.now();
            if (now.difference(lastUiBatch).inMilliseconds > 120 || _results.length < 15) {
              lastUiBatch = now;
              if (mounted) {
                setState(() {
                  _results.addAll(batch);
                  batch.clear();
                });
              }
            }
          }
        } catch (_) {}
      },
      onDone: () {
        if (mounted) {
          setState(() {
            if (batch.isNotEmpty) {
              _results.addAll(batch);
              batch.clear();
            }
            _isSearching = false;
          });
        }
      },
      onError: (_) {
        if (mounted) setState(() => _isSearching = false);
      },
    );
  }

  bool _matchesCategoryFilter(FileItemModel item) {
    if (_selectedFilter == 'All') return true;
    if (item.isDirectory) return false;
    final ext = p.extension(item.path).toLowerCase();
    switch (_selectedFilter) {
      case 'Images':
        return ['.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp', '.heic', '.avif'].contains(ext);
      case 'Videos':
        return ['.mp4', '.mkv', '.avi', '.mov', '.wmv', '.flv', '.webm', '.ts'].contains(ext);
      case 'Audio':
        return ['.mp3', '.m4a', '.wav', '.flac', '.aac', '.ogg', '.opus', '.amr'].contains(ext);
      case 'Docs':
        return ['.pdf', '.doc', '.docx', '.xls', '.xlsx', '.ppt', '.pptx', '.txt', '.csv'].contains(ext);
      case 'PDFs':
        return ext == '.pdf';
      case 'Archives':
        return ['.zip', '.rar', '.7z', '.tar', '.gz', '.bz2', '.xz'].contains(ext);
      default:
        return true;
    }
  }

  List<String> _getRecentSearches() {
    return PreferencesService.getRecentSearches();
  }

  void _saveRecentSearch(String query) {
    PreferencesService.addRecentSearch(query);
  }

  void _clearRecentSearches() {
    PreferencesService.clearRecentSearches();
    setState(() {});
  }

  void _applySmartChip(String text) {
    _searchController.text = text;
    _executeSearch(text);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final recentSearches = _getRecentSearches();
    final activeBadges = _parsedQuery?.activeBadges ?? [];

    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Search',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 12),

                // Search Bar
                TextField(
                  controller: _searchController,
                  focusNode: _searchFocusNode,
                  onChanged: (val) {
                    if (val.length >= 2 || val.isEmpty) {
                      _executeSearch(val);
                    }
                  },
                  onSubmitted: _executeSearch,
                  decoration: InputDecoration(
                    hintText: 'Search or ask e.g. "PDFs > 10MB"',
                    prefixIcon: const Padding(
                      padding: EdgeInsets.only(left: 12, right: 8),
                      child: NfileIcon(Broken.search_normal, size: 20),
                    ),
                    prefixIconConstraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                    suffixIcon: _query.isNotEmpty
                        ? IconButton(
                            icon: const NfileIcon(Broken.close_circle, size: 20),
                            onPressed: () {
                              _searchController.clear();
                              _executeSearch('');
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: theme.colorScheme.surfaceVariant.withOpacity(0.4),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
                const SizedBox(height: 12),

                // 1. Quick Category Filter Row
                SizedBox(
                  height: 38,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    itemCount: _categoryFilters.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final cat = _categoryFilters[index];
                      final isSelected = _selectedFilter == cat.label;

                      return FilterChip(
                        avatar: Icon(
                          cat.icon,
                          size: 16,
                          color: isSelected ? cat.color : theme.textTheme.bodySmall?.color,
                        ),
                        label: Text(
                          cat.label,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                            color: isSelected ? cat.color : theme.textTheme.bodyMedium?.color,
                          ),
                        ),
                        selected: isSelected,
                        onSelected: (val) {
                          setState(() => _selectedFilter = cat.label);
                          if (_query.isNotEmpty) _executeSearch(_query);
                        },
                        showCheckmark: false,
                        selectedColor: cat.color.withOpacity(0.16),
                        backgroundColor: theme.colorScheme.surfaceVariant.withOpacity(0.25),
                        side: BorderSide(
                          color: isSelected ? cat.color.withOpacity(0.4) : Colors.transparent,
                        ),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        visualDensity: VisualDensity.compact,
                      );
                    },
                  ),
                ),

                // Active Smart Filter Badges (if query parsed natural language filters)
                if (activeBadges.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 30,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      itemCount: activeBadges.length + 1,
                      separatorBuilder: (_, __) => const SizedBox(width: 6),
                      itemBuilder: (context, index) {
                        if (index == 0) {
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primary.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Broken.magic_star, size: 14, color: theme.colorScheme.primary),
                                const SizedBox(width: 4),
                                Text(
                                  'Smart Filters:',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: theme.colorScheme.primary,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }

                        final badge = activeBadges[index - 1];
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: badge.color.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: badge.color.withOpacity(0.3)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(badge.icon, size: 13, color: badge.color),
                              const SizedBox(width: 5),
                              Text(
                                badge.label,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: badge.color,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ],
            ),
          ),

          // Body: Hub or Results
          Expanded(
            child: _query.isEmpty
                ? _buildSearchHub(theme, recentSearches)
                : _buildSearchResults(theme),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchHub(ThemeData theme, List<String> recentSearches) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 2. "Ask in your own words" Section
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF8B5CF6), Color(0xFF6366F1)],
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Broken.magic_star, size: 16, color: Colors.white),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Ask in your own words',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.2,
                    ),
                  ),
                  Text(
                    'Tap to search with smart natural filters',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: theme.textTheme.bodySmall?.color?.withOpacity(0.6),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Smart Filter Chips Grid / Wrap
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _smartFilterChips.map((chip) {
              return InkWell(
                onTap: () => _applySmartChip(chip.label),
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: chip.color.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: chip.color.withOpacity(0.2)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(chip.icon, size: 16, color: chip.color),
                      const SizedBox(width: 8),
                      Text(
                        chip.label,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: theme.textTheme.bodyMedium?.color,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),

          const SizedBox(height: 28),

          // Recent Searches Section
          if (recentSearches.isNotEmpty) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Recent Searches',
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                ),
                TextButton(
                  onPressed: _clearRecentSearches,
                  child: Text(
                    'Clear All',
                    style: TextStyle(fontSize: 12, color: theme.colorScheme.primary),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            ...recentSearches.map(
              (search) => ListTile(
                leading: NfileIcon(
                  Broken.clock,
                  size: 20,
                  color: theme.colorScheme.onSurface.withOpacity(0.5),
                ),
                title: Text(search, style: const TextStyle(fontSize: 14)),
                dense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                onTap: () {
                  _searchController.text = search;
                  _executeSearch(search);
                },
                trailing: IconButton(
                  icon: NfileIcon(
                    Broken.close_circle,
                    size: 16,
                    color: theme.colorScheme.onSurface.withOpacity(0.4),
                  ),
                  onPressed: () {
                    PreferencesService.removeRecentSearch(search);
                    setState(() {});
                  },
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSearchResults(ThemeData theme) {
    if (_isSearching && _results.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (!_isSearching && _results.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              NfileIcon(
                Broken.search_normal_1,
                size: 64,
                color: theme.colorScheme.onSurface.withOpacity(0.2),
              ),
              const SizedBox(height: 16),
              Text(
                'No matching files found',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withOpacity(0.6),
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Try adjusting your search query or removing some smart filters',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12.5,
                  color: theme.textTheme.bodySmall?.color?.withOpacity(0.5),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            children: [
              Text(
                '${_results.length} result${_results.length == 1 ? '' : 's'}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withOpacity(0.6),
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (_isSearching) ...[
                const SizedBox(width: 8),
                SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            physics: const BouncingScrollPhysics(),
            itemCount: _results.length,
            itemBuilder: (context, index) {
              final item = _results[index];
              if (item.isDirectory) {
                return FolderItem(
                  folder: item,
                  onTap: () {
                    final fileManager = context.read<FileManagerProvider>();
                    fileManager.loadDirectory(item.path);
                    widget.onNavigateTab(1);
                  },
                  onAction: (action) {},
                );
              }
              return FileItem(
                file: item,
                onTap: () {
                  context.read<FileManagerProvider>().openFile(context, item.path);
                },
                onAction: (action) {
                  if (action == 'quick_convert') {
                    QuickConvertBottomSheet.show(context, File(item.path));
                  } else if (action == 'edit_image_toolbox') {
                    EcosystemHandoff.launchImageToolbox(File(item.path), context: context);
                  } else if (action == 'trim_video') {
                    Navigator.of(context).push(
                      PageRouteBuilder(
                        pageBuilder: (context, animation, secondaryAnimation) =>
                            VideoTrimmerScreen(videoPath: item.path),
                        transitionsBuilder: (context, animation, secondaryAnimation, child) {
                          return const FadeUpwardsPageTransitionsBuilder().buildTransitions(
                            MaterialPageRoute(builder: (_) => const SizedBox()),
                            context,
                            animation,
                            secondaryAnimation,
                            child,
                          );
                        },
                      ),
                    );
                  }
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
