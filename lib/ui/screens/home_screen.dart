import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../providers/file_manager_provider.dart';
import '../../providers/media_provider.dart';
import '../../core/icon_fonts/broken_icons.dart';
import '../widgets/swipable_storage_overview.dart';
import '../widgets/quick_categories_grid.dart';
import '../widgets/recent_files_section.dart';
import '../widgets/nfile_drawer.dart';
import '../widgets/nfile_icon.dart';
import 'directory_screen.dart';
import 'search_tab_screen.dart';
import 'tools_tab_screen.dart';
import 'storage_analyzer/storage_analyzer_screen.dart';
import 'storage_cleanup/storage_cleanup_screen.dart';
import '../../services/picker_mode_service.dart';

class HomeScreen extends StatefulWidget {
  final VoidCallback toggleTheme;
  const HomeScreen({super.key, required this.toggleTheme});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  int _currentIndex = 0;
  DateTime? _lastBrowseTapTime;
  DateTime? _lastPressedAt;
  late AnimationController _refreshIconController;
  bool _isRefreshing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshIconController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    );
    _currentIndex = context.read<FileManagerProvider>().defaultToBrowseScreen ? 1 : 0;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!PickerModeService.isPickerMode) {
        context.read<MediaProvider>().loadMedia();
      }
    });
  }

  @override
  void dispose() {
    _refreshIconController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      context.read<MediaProvider>().refreshMediaBackground();
    }
  }

  Future<void> _handleRefresh() async {
    if (_isRefreshing) return;
    setState(() {
      _isRefreshing = true;
    });
    _refreshIconController.repeat();
    try {
      await Future.wait([
        context.read<FileManagerProvider>().updateStorageSpace(),
        context.read<MediaProvider>().loadMedia(forceRefresh: true),
      ]);
    } catch (_) {
    } finally {
      if (mounted) {
        _refreshIconController.stop();
        setState(() {
          _isRefreshing = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Dashboard refreshed successfully'),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 1),
          ),
        );
      }
    }
  }

  void _showExitConfirmationDialog(BuildContext context) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Exit Confirmation',
      barrierColor: Colors.black.withOpacity(0.5),
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, anim1, anim2) {
        return const SizedBox.shrink();
      },
      transitionBuilder: (context, anim1, anim2, child) {
        final theme = Theme.of(context);
        return ScaleTransition(
          scale: CurvedAnimation(parent: anim1, curve: Curves.easeOutBack),
          child: FadeTransition(
            opacity: anim1,
            child: PopScope(
              canPop: false,
              onPopInvoked: (didPop) {
                if (didPop) return;
                SystemNavigator.pop();
              },
              child: AlertDialog(
                backgroundColor: theme.colorScheme.surface,
                elevation: 10,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                title: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.errorContainer.withOpacity(0.2),
                        shape: BoxShape.circle,
                      ),
                      child: NfileIcon(
                        Broken.logout,
                        color: theme.colorScheme.error,
                        size: 32,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Exit Application',
                      style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                content: const Text(
                  'Are you sure you want to exit? Press back again or tap Exit to close the app.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 15, height: 1.4),
                ),
                actionsAlignment: MainAxisAlignment.spaceEvenly,
                actionsPadding: const EdgeInsets.only(bottom: 20, left: 16, right: 16),
                actions: [
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.colorScheme.error,
                      foregroundColor: theme.colorScheme.onError,
                      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
                    ),
                    onPressed: () => SystemNavigator.pop(),
                    child: const Text('Exit', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<FileManagerProvider>();
    final theme = Theme.of(context);
    final canPopHomeScreen = _currentIndex == 1 && !provider.isSelectionMode && provider.canGoBack;

    return PopScope(
      canPop: canPopHomeScreen,
      onPopInvoked: (didPop) {
        if (didPop) return;
        if (_currentIndex == 1) {
          if (!provider.canGoBack) {
            setState(() {
              _currentIndex = 0;
            });
            context.read<MediaProvider>().refreshMediaBackground();
          }
        } else if (_currentIndex > 1) {
          setState(() {
            _currentIndex = 0;
          });
          context.read<MediaProvider>().refreshMediaBackground();
        } else {
          if (provider.exitOption == 'double_press') {
            final now = DateTime.now();
            if (_lastPressedAt == null || now.difference(_lastPressedAt!) > const Duration(seconds: 2)) {
              _lastPressedAt = now;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text(
                    'Press back again to exit',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                  ),
                  backgroundColor: theme.colorScheme.primary,
                  behavior: SnackBarBehavior.floating,
                  duration: const Duration(seconds: 2),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              );
            } else {
              SystemNavigator.pop();
            }
          } else {
            _showExitConfirmationDialog(context);
          }
        }
      },
      child: Scaffold(
        drawer: NFileDrawer(
          toggleTheme: widget.toggleTheme,
          onNavigateTab: (index) => setState(() => _currentIndex = index),
        ),
        body: IndexedStack(
          index: _currentIndex,
          children: [
            _buildHomeTab(),
            DirectoryScreen(
              toggleTheme: widget.toggleTheme,
              onNavigateTab: (index) => setState(() => _currentIndex = index),
            ),
            SearchTabScreen(
              onNavigateTab: (index) => setState(() => _currentIndex = index),
            ),
            const ToolsTabScreen(),
          ],
        ),
        bottomNavigationBar: provider.showHomeBrowseNav
            ? NavigationBar(
                height: provider.hideNavLabels ? 58.0 : null,
                labelBehavior: provider.hideNavLabels
                    ? NavigationDestinationLabelBehavior.alwaysHide
                    : null,
                selectedIndex: _currentIndex,
                onDestinationSelected: (index) {
                  if (index == 1) {
                    final now = DateTime.now();
                    if (_currentIndex == 1 && _lastBrowseTapTime != null && now.difference(_lastBrowseTapTime!) < const Duration(milliseconds: 800)) {
                      provider.loadDirectory(provider.rootPath);
                    }
                    _lastBrowseTapTime = now;
                  } else if (index == 0) {
                    context.read<MediaProvider>().refreshMediaBackground();
                  }
                  setState(() => _currentIndex = index);
                },
                destinations: const [
                  NavigationDestination(
                    icon: NfileIcon(Broken.home),
                    selectedIcon: NfileIcon(Broken.home_1),
                    label: 'Home',
                  ),
                  NavigationDestination(
                    icon: NfileIcon(Broken.folder),
                    selectedIcon: NfileIcon(Broken.folder_open),
                    label: 'Browse',
                  ),
                  NavigationDestination(
                    icon: NfileIcon(Broken.search_normal),
                    selectedIcon: NfileIcon(Broken.search_normal_1),
                    label: 'Search',
                  ),
                  NavigationDestination(
                    icon: NfileIcon(Broken.element_3),
                    selectedIcon: NfileIcon(Broken.element_4),
                    label: 'Tools',
                  ),
                ],
              )
            : null,
      ),
    );
  }

  Widget _buildHomeTab() {
    final theme = Theme.of(context);
    final provider = context.watch<FileManagerProvider>();
    final sections = provider.homeSectionOrder;

    return SafeArea(
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'My Files',
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        onPressed: () => _showHomeSectionsDialog(context, provider, theme),
                        tooltip: 'Customize Sections',
                        icon: const NfileIcon(Broken.element_3, size: 20),
                      ),
                      IconButton(
                        onPressed: _handleRefresh,
                        tooltip: 'Refresh Dashboard',
                        icon: RotationTransition(
                          turns: _refreshIconController,
                          child: const NfileIcon(Broken.refresh),
                        ),
                      ),
                      IconButton(
                        onPressed: widget.toggleTheme,
                        icon: NfileIcon(
                          theme.brightness == Brightness.dark ? Broken.sun_1 : Broken.moon,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            for (final section in sections)
              if (provider.isHomeSectionVisible(section))
                _buildSectionWidget(section, theme),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionWidget(String section, ThemeData theme) {
    switch (section) {
      case 'storage_overview':
        return SwipableStorageOverview(
          onBrowseVolume: (path) {
            final provider = context.read<FileManagerProvider>();
            provider.loadDirectory(path);
            setState(() => _currentIndex = 1);
          },
        );
      case 'storage_shortcuts':
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6.0),
          child: Row(
            children: [
              Expanded(
                child: _buildShortcutCard(
                  theme,
                  icon: Broken.chart,
                  label: 'Storage Analyzer',
                  subtitle: 'Analyze usage',
                  color: theme.colorScheme.primary,
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const StorageAnalyzerScreen())),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildShortcutCard(
                  theme,
                  icon: Broken.brush_2,
                  label: 'Storage Cleanup',
                  subtitle: 'Free up space',
                  color: Colors.green,
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const StorageCleanupScreen())),
                ),
              ),
            ],
          ),
        );
      case 'quick_categories':
        return Padding(
          padding: const EdgeInsets.only(top: 8.0, bottom: 4.0),
          child: QuickCategoriesGrid(
            onNavigateTab: (index) => setState(() => _currentIndex = index),
          ),
        );
      case 'recent_files':
        return Padding(
          padding: const EdgeInsets.only(top: 8.0),
          child: RecentFilesSection(
            onNavigateTab: (index) => setState(() => _currentIndex = index),
          ),
        );
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildShortcutCard(
    ThemeData theme, {
    required IconData icon,
    required String label,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: color.withOpacity(0.08),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        splashColor: color.withOpacity(0.15),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: NfileIcon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        fontSize: 12.5,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withOpacity(0.5),
                        fontSize: 10.5,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showHomeSectionsDialog(BuildContext context, FileManagerProvider fileManager, ThemeData theme) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: theme.scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setStateModal) {
            final sections = fileManager.homeSectionOrder;
            final visibility = fileManager.homeSectionVisibility;

            final sectionMeta = {
              'storage_overview': {'name': 'Storage Overview', 'desc': 'Storage cards and volume details', 'icon': Broken.chart},
              'storage_shortcuts': {'name': 'Storage Shortcuts', 'desc': 'Storage Analyzer & Cleanup cards', 'icon': Broken.brush_2},
              'quick_categories': {'name': 'Quick Categories', 'desc': 'Media category shortcuts grid', 'icon': Broken.category},
              'recent_files': {'name': 'Recent Files', 'desc': 'Horizontal strip of recently opened files', 'icon': Broken.clock},
            };

            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(ctx).viewInsets.bottom,
                ),
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Center(
                          child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.withOpacity(0.3), borderRadius: BorderRadius.circular(2))),
                        ),
                        const SizedBox(height: 16),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8.0),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('Customize Sections', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                              TextButton(
                                onPressed: () => Navigator.pop(ctx),
                                child: const Text('Done', style: TextStyle(fontWeight: FontWeight.bold)),
                              ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                          child: Text(
                            'Drag handle to reorder sections. Toggle switch to show or hide.',
                            style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withOpacity(0.6)),
                          ),
                        ),
                        const SizedBox(height: 12),
                        ReorderableListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: sections.length,
                          onReorder: (oldIndex, newIndex) {
                            fileManager.reorderHomeSection(oldIndex, newIndex);
                            setStateModal(() {});
                          },
                          itemBuilder: (context, index) {
                            final sectionKey = sections[index];
                            final meta = sectionMeta[sectionKey] ?? {'name': sectionKey, 'desc': '', 'icon': Broken.element_3};
                            final isVisible = visibility[sectionKey] ?? true;

                            return ListTile(
                              key: ValueKey(sectionKey),
                              leading: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: isVisible ? theme.colorScheme.primary.withOpacity(0.12) : theme.colorScheme.surfaceVariant.withOpacity(0.4),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: NfileIcon(meta['icon'] as IconData, color: isVisible ? theme.colorScheme.primary : Colors.grey, size: 20),
                              ),
                              title: Text(meta['name'] as String, style: TextStyle(fontWeight: isVisible ? FontWeight.bold : FontWeight.normal)),
                              subtitle: Text(meta['desc'] as String, style: const TextStyle(fontSize: 11)),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Switch(
                                    value: isVisible,
                                    activeColor: theme.colorScheme.primary,
                                    onChanged: (_) {
                                      fileManager.toggleHomeSectionVisibility(sectionKey);
                                      setStateModal(() {});
                                    },
                                  ),
                                  const SizedBox(width: 4),
                                  ReorderableDragStartListener(
                                    index: index,
                                    child: const Icon(Icons.drag_handle, color: Colors.grey),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
