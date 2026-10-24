import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';
import 'package:provider/provider.dart';

import '../../../core/icon_fonts/broken_icons.dart';
import '../../../core/utils.dart';
import '../../../models/app_info_model.dart';
import '../../../providers/file_manager_provider.dart';
import '../../../services/apk_parser_service.dart';
import '../../../services/app_manager_service.dart';
import '../internal_file_picker_screen.dart';

class ApkInspectorScreen extends StatefulWidget {
  final String? initialApkPath;
  final String? initialAppName;

  const ApkInspectorScreen({
    super.key,
    this.initialApkPath,
    this.initialAppName,
  });

  @override
  State<ApkInspectorScreen> createState() => _ApkInspectorScreenState();
}

class _ApkInspectorScreenState extends State<ApkInspectorScreen>
    with SingleTickerProviderStateMixin {
  // Tabs: 0 = Installed Apps, 1 = Pick File
  int _currentMode = 0;

  // Installed Apps state
  List<AppInfoModel> _installedApps = [];
  List<AppInfoModel> _filteredApps = [];
  bool _isLoadingApps = false;
  bool _includeSystemApps = false;
  final TextEditingController _searchController = TextEditingController();

  // Active Inspection State
  ApkInspectionResult? _inspectionResult;
  bool _isAnalyzing = false;
  String? _analysisError;
  Uint8List? _activeAppIcon;
  AppInfoModel? _activeInstalledApp;

  // Extraction state
  bool _isExtracting = false;
  String? _extractedFilePath;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_filterApps);

    if (widget.initialApkPath != null) {
      _currentMode = 1;
      _inspectPath(
        widget.initialApkPath!,
        fallbackAppName: widget.initialAppName,
      );
    } else {
      _loadInstalledApps();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadInstalledApps() async {
    setState(() => _isLoadingApps = true);
    try {
      final apps = await AppManagerService.getInstalledApps(
        includeSystem: _includeSystemApps,
      );
      apps.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      if (mounted) {
        setState(() {
          _installedApps = apps;
          _isLoadingApps = false;
        });
        _filterApps();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingApps = false);
      }
    }
  }

  void _filterApps() {
    final query = _searchController.text.trim().toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _filteredApps = List.from(_installedApps);
      } else {
        _filteredApps = _installedApps.where((app) {
          return app.name.toLowerCase().contains(query) ||
              app.packageName.toLowerCase().contains(query);
        }).toList();
      }
    });
  }

  Future<void> _inspectInstalledApp(AppInfoModel app) async {
    setState(() {
      _activeInstalledApp = app;
      _activeAppIcon = null;
    });

    // Load icon asynchronously
    AppManagerService.getAppIcon(app.packageName).then((iconBytes) {
      if (mounted && _activeInstalledApp?.packageName == app.packageName) {
        setState(() => _activeAppIcon = iconBytes);
      }
    });

    await _inspectPath(
      app.sourceDir,
      fallbackAppName: app.name,
      splitPaths: app.splitSourceDirs,
    );
  }

  Future<void> _inspectPath(
    String path, {
    String? fallbackAppName,
    List<String>? splitPaths,
  }) async {
    setState(() {
      _isAnalyzing = true;
      _analysisError = null;
      _inspectionResult = null;
      _extractedFilePath = null;
    });

    try {
      final result = await ApkParserService.inspectApk(
        path,
        fallbackAppName: fallbackAppName,
        splitPaths: splitPaths,
      );

      // If standalone file and no icon loaded yet, load APK icon
      if (_activeAppIcon == null) {
        final icon = await AppManagerService.getApkIcon(path);
        if (mounted && icon != null) {
          setState(() => _activeAppIcon = icon);
        }
      }

      if (mounted) {
        setState(() {
          _inspectionResult = result;
          _isAnalyzing = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _analysisError = 'Failed to inspect APK: $e';
          _isAnalyzing = false;
        });
      }
    }
  }

  Future<void> _pickApkFromFilePicker() async {
    final rootPath = context.read<FileManagerProvider>().rootPath;
    final picked = await InternalFilePickerScreen.show(
      context,
      rootPath: rootPath,
      pickDirectory: false,
    );

    if (picked != null && picked.isNotEmpty) {
      final selectedPath = picked.first;
      if (!selectedPath.toLowerCase().endsWith('.apk') &&
          !selectedPath.toLowerCase().endsWith('.apks') &&
          !selectedPath.toLowerCase().endsWith('.xapk')) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select an APK or APKS file.')),
        );
        return;
      }

      setState(() {
        _activeInstalledApp = null;
        _activeAppIcon = null;
      });
      _inspectPath(selectedPath);
    }
  }

  Future<void> _extractBaseApk() async {
    if (_inspectionResult == null) return;
    setState(() => _isExtracting = true);

    try {
      final targetDir = '/storage/emulated/0/Download/Extracted_APKs';
      final outPath = await ApkParserService.extractBaseApk(
        sourceApkPath: _inspectionResult!.filePath,
        targetDirPath: targetDir,
        appName: _inspectionResult!.appName,
        version: _inspectionResult!.versionName,
      );

      if (mounted) {
        setState(() {
          _isExtracting = false;
          _extractedFilePath = outPath;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Extracted to: ${p.basename(outPath)}'),
            backgroundColor: Colors.green.shade700,
            action: SnackBarAction(
              label: 'Share',
              textColor: Colors.white,
              onPressed: () => Share.shareXFiles([XFile(outPath)]),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isExtracting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to extract APK: $e')),
        );
      }
    }
  }

  Future<void> _extractSplitApks() async {
    if (_inspectionResult == null) return;
    setState(() => _isExtracting = true);

    try {
      final targetDir = '/storage/emulated/0/Download/Extracted_APKs';
      final outPath = await ApkParserService.extractSplitApks(
        baseApkPath: _inspectionResult!.filePath,
        splitPaths: _inspectionResult!.splitFilePaths,
        targetDirPath: targetDir,
        appName: _inspectionResult!.appName,
        version: _inspectionResult!.versionName,
      );

      if (mounted) {
        setState(() {
          _isExtracting = false;
          _extractedFilePath = outPath;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Bundled splits to: ${p.basename(outPath)}'),
            backgroundColor: Colors.teal.shade700,
            action: SnackBarAction(
              label: 'Share',
              textColor: Colors.white,
              onPressed: () => Share.shareXFiles([XFile(outPath)]),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isExtracting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to bundle splits: $e')),
        );
      }
    }
  }

  void _shareCurrentApk() {
    if (_inspectionResult == null) return;
    Share.shareXFiles(
      [XFile(_inspectionResult!.filePath)],
      text: '${_inspectionResult!.appName} v${_inspectionResult!.versionName}',
    );
  }

  void _copyToClipboard(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    HapticFeedback.lightImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label copied to clipboard'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          _inspectionResult != null ? 'APK Details' : 'APK Inspector & Extractor',
        ),
        elevation: 0,
        backgroundColor: theme.colorScheme.surface,
        leading: _inspectionResult != null
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () {
                  setState(() {
                    _inspectionResult = null;
                    _analysisError = null;
                  });
                },
              )
            : null,
        actions: [
          if (_inspectionResult != null) ...[
            IconButton(
              icon: const Icon(Icons.share_outlined),
              tooltip: 'Share APK',
              onPressed: _shareCurrentApk,
            ),
          ],
        ],
      ),
      body: _inspectionResult != null
          ? _buildInspectionDetailView(theme)
          : _buildSelectionView(theme),
    );
  }

  // --------------------------------------------------------------------------
  // Selection View: Mode switcher (Installed Apps vs Select APK File)
  // --------------------------------------------------------------------------

  Widget _buildSelectionView(ThemeData theme) {
    return Column(
      children: [
        // Mode Selector Tab Bar
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceVariant.withOpacity(0.4),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Expanded(
                child: _buildModeTab(
                  label: 'Installed Apps',
                  icon: Broken.mobile,
                  isSelected: _currentMode == 0,
                  onTap: () {
                    setState(() => _currentMode = 0);
                    if (_installedApps.isEmpty) _loadInstalledApps();
                  },
                ),
              ),
              Expanded(
                child: _buildModeTab(
                  label: 'Pick APK File',
                  icon: Broken.document_download,
                  isSelected: _currentMode == 1,
                  onTap: () => setState(() => _currentMode = 1),
                ),
              ),
            ],
          ),
        ),

        if (_isAnalyzing)
          const Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Parsing APK structure & manifest...'),
                ],
              ),
            ),
          )
        else if (_analysisError != null)
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline, size: 48, color: Colors.redAccent),
                    const SizedBox(height: 12),
                    Text(
                      _analysisError!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.redAccent),
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () => setState(() => _analysisError = null),
                      child: const Text('Try Again'),
                    ),
                  ],
                ),
              ),
            ),
          )
        else if (_currentMode == 0)
          Expanded(child: _buildInstalledAppsList(theme))
        else
          Expanded(child: _buildPickApkFileView(theme)),
      ],
    );
  }

  Widget _buildModeTab({
    required String label,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? theme.colorScheme.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 18,
              color: isSelected
                  ? theme.colorScheme.onPrimary
                  : theme.textTheme.bodyMedium?.color,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                fontSize: 13,
                color: isSelected
                  ? theme.colorScheme.onPrimary
                  : theme.textTheme.bodyMedium?.color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --------------------------------------------------------------------------
  // Mode 0: Installed Apps List with search and system apps filter
  // --------------------------------------------------------------------------

  Widget _buildInstalledAppsList(ThemeData theme) {
    return Column(
      children: [
        // Search & Filter header
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search installed apps...',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () => _searchController.clear(),
                          )
                        : null,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    filled: true,
                    fillColor: theme.colorScheme.surfaceVariant.withOpacity(0.3),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilterChip(
                label: const Text('System', style: TextStyle(fontSize: 12)),
                selected: _includeSystemApps,
                onSelected: (val) {
                  setState(() => _includeSystemApps = val);
                  _loadInstalledApps();
                },
              ),
            ],
          ),
        ),

        // Apps count
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
          child: Row(
            children: [
              Text(
                '${_filteredApps.length} Apps found',
                style: TextStyle(
                  fontSize: 12,
                  color: theme.textTheme.bodySmall?.color?.withOpacity(0.7),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),

        // App list
        if (_isLoadingApps)
          const Expanded(child: Center(child: CircularProgressIndicator()))
        else if (_filteredApps.isEmpty)
          const Expanded(child: Center(child: Text('No apps found.')))
        else
          Expanded(
            child: ListView.separated(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              itemCount: _filteredApps.length,
              separatorBuilder: (_, __) => const SizedBox(height: 6),
              itemBuilder: (context, index) {
                final app = _filteredApps[index];
                final isSplit = app.splitSourceDirs.isNotEmpty;

                return InkWell(
                  onTap: () => _inspectInstalledApp(app),
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: theme.dividerColor.withOpacity(0.06),
                      ),
                    ),
                    child: Row(
                      children: [
                        // App Icon
                        FutureBuilder<Uint8List?>(
                          future: AppManagerService.getAppIcon(app.packageName),
                          builder: (context, snapshot) {
                            if (snapshot.hasData && snapshot.data != null) {
                              return ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: Image.memory(
                                  snapshot.data!,
                                  width: 44,
                                  height: 44,
                                  fit: BoxFit.cover,
                                ),
                              );
                            }
                            return Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primary.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                Broken.mobile,
                                color: theme.colorScheme.primary,
                                size: 24,
                              ),
                            );
                          },
                        ),
                        const SizedBox(width: 14),

                        // App Title & Package
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                app.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                app.packageName,
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: theme.textTheme.bodySmall?.color?.withOpacity(0.6),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Text(
                                    'v${app.version}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: theme.colorScheme.primary,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    FileUtils.formatBytes(app.apkSize, 1),
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: theme.textTheme.bodySmall?.color?.withOpacity(0.5),
                                    ),
                                  ),
                                  if (isSplit) ...[
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                      decoration: BoxDecoration(
                                        color: Colors.amber.withOpacity(0.15),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: const Text(
                                        'Split APK',
                                        style: TextStyle(
                                          fontSize: 9.5,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.amber,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),

                        const Icon(Icons.chevron_right, size: 20),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  // --------------------------------------------------------------------------
  // Mode 1: Pick Standalone APK File View
  // --------------------------------------------------------------------------

  Widget _buildPickApkFileView(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Broken.document_code,
                size: 56,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Inspect Any APK File',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Select an APK, APKS, or XAPK file from your device storage to inspect its manifest, permissions, signing certificates, and DEX structure.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: theme.textTheme.bodySmall?.color?.withOpacity(0.7),
                height: 1.4,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _pickApkFromFilePicker,
              icon: const Icon(Icons.folder_open, size: 20),
              label: const Text('Browse Files'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --------------------------------------------------------------------------
  // Inspection Details View (Tabs for Structure, Permissions, Manifest)
  // --------------------------------------------------------------------------

  Widget _buildInspectionDetailView(ThemeData theme) {
    final res = _inspectionResult!;
    final isDark = theme.brightness == Brightness.dark;

    return DefaultTabController(
      length: 4,
      child: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) {
          return [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    // Main App Card
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: theme.dividerColor.withOpacity(0.08),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.03),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // App Icon
                              if (_activeAppIcon != null)
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(16),
                                  child: Image.memory(
                                    _activeAppIcon!,
                                    width: 60,
                                    height: 60,
                                    fit: BoxFit.cover,
                                  ),
                                )
                              else
                                Container(
                                  width: 60,
                                  height: 60,
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.primary.withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: Icon(
                                    Broken.mobile,
                                    color: theme.colorScheme.primary,
                                    size: 32,
                                  ),
                                ),
                              const SizedBox(width: 14),

                              // App Name & Package
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      res.appName,
                                      style: const TextStyle(
                                        fontSize: 17,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    InkWell(
                                      onTap: () => _copyToClipboard(res.packageName, 'Package name'),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              res.packageName,
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: theme.textTheme.bodySmall?.color?.withOpacity(0.7),
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          const SizedBox(width: 4),
                                          const Icon(Icons.copy, size: 13, color: Colors.grey),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Wrap(
                                      spacing: 6,
                                      runSpacing: 4,
                                      children: [
                                        _buildSmallBadge(
                                          'v${res.versionName} (${res.versionCode})',
                                          isDark ? Colors.blue.shade300 : Colors.blue.shade700,
                                          isDark ? Colors.blue.withOpacity(0.2) : Colors.blue.shade50,
                                        ),
                                        _buildSmallBadge(
                                          FileUtils.formatBytes(res.fileSize, 2),
                                          isDark ? Colors.purple.shade300 : Colors.purple.shade700,
                                          isDark ? Colors.purple.withOpacity(0.2) : Colors.purple.shade50,
                                        ),
                                        if (res.isSplitApk)
                                          _buildSmallBadge(
                                            'Split (${res.splitFilePaths.length + 1} APKs)',
                                            Colors.amber.shade800,
                                            Colors.amber.withOpacity(0.15),
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 14),
                          const Divider(height: 1),
                          const SizedBox(height: 12),

                          // SDK Badges Row
                          Row(
                            children: [
                              Expanded(
                                child: _buildSdkCard(
                                  theme,
                                  title: 'Min SDK',
                                  sdk: res.minSdk,
                                  androidVer: _getAndroidVersionName(res.minSdk),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _buildSdkCard(
                                  theme,
                                  title: 'Target SDK',
                                  sdk: res.targetSdk,
                                  androidVer: _getAndroidVersionName(res.targetSdk),
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 14),

                          // Extraction Action Buttons
                          Row(
                            children: [
                              Expanded(
                                child: FilledButton.icon(
                                  onPressed: _isExtracting ? null : _extractBaseApk,
                                  icon: const Icon(Icons.file_download_outlined, size: 18),
                                  label: Text(res.isSplitApk ? 'Extract Base APK' : 'Extract APK'),
                                  style: FilledButton.styleFrom(
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    padding: const EdgeInsets.symmetric(vertical: 11),
                                  ),
                                ),
                              ),
                              if (res.isSplitApk && res.splitFilePaths.isNotEmpty) ...[
                                const SizedBox(width: 8),
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: _isExtracting ? null : _extractSplitApks,
                                    icon: const Icon(Icons.archive_outlined, size: 18),
                                    label: const Text('Bundle .apks'),
                                    style: OutlinedButton.styleFrom(
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      padding: const EdgeInsets.symmetric(vertical: 11),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),

                          if (_isExtracting) ...[
                            const SizedBox(height: 8),
                            const LinearProgressIndicator(),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Tab Bar
            SliverPersistentHeader(
              pinned: true,
              delegate: _SliverAppBarDelegate(
                TabBar(
                  isScrollable: true,
                  physics: const BouncingScrollPhysics(),
                  indicatorColor: theme.colorScheme.primary,
                  labelColor: theme.colorScheme.primary,
                  unselectedLabelColor: theme.textTheme.bodyMedium?.color?.withOpacity(0.6),
                  tabs: [
                    Tab(text: 'Structure (${res.dexFiles.length} DEX)'),
                    Tab(text: 'Permissions (${res.permissions.length})'),
                    Tab(text: 'Components (${res.activities.length + res.services.length})'),
                    Tab(text: 'Certificates (${res.certificates.length})'),
                  ],
                ),
                backgroundColor: theme.scaffoldBackgroundColor,
              ),
            ),
          ];
        },
        body: TabBarView(
          children: [
            _buildStructureTab(theme, res),
            _buildPermissionsTab(theme, res),
            _buildComponentsTab(theme, res),
            _buildCertificatesTab(theme, res),
          ],
        ),
      ),
    );
  }

  Widget _buildSmallBadge(String text, Color textColor, Color bgColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.bold,
          color: textColor,
        ),
      ),
    );
  }

  Widget _buildSdkCard(
    ThemeData theme, {
    required String title,
    required int sdk,
    required String androidVer,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceVariant.withOpacity(0.3),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 11,
              color: theme.textTheme.bodySmall?.color?.withOpacity(0.6),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'API $sdk ($androidVer)',
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  // --------------------------------------------------------------------------
  // Tab 1: Package Structure (DEX files, Native libs, Assets, Resources)
  // --------------------------------------------------------------------------

  Widget _buildStructureTab(ThemeData theme, ApkInspectionResult res) {
    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        // 1. DEX Summary
        _buildSectionTitle(theme, 'DEX Files (${res.dexFiles.length})', Broken.code),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: theme.dividerColor.withOpacity(0.06)),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Total Code Size', style: TextStyle(fontWeight: FontWeight.w600)),
                  Text(
                    FileUtils.formatBytes(res.totalDexSize, 2),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ],
              ),
              const Divider(height: 16),
              ...res.dexFiles.map((dex) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(dex.name, style: const TextStyle(fontSize: 13, fontFamily: 'monospace')),
                        Text(
                          FileUtils.formatBytes(dex.size, 1),
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.textTheme.bodySmall?.color?.withOpacity(0.6),
                          ),
                        ),
                      ],
                    ),
                  )),
            ],
          ),
        ),

        const SizedBox(height: 18),

        // 2. Native ABIs & Libraries
        _buildSectionTitle(
          theme,
          'Native Libraries (${res.totalNativeLibsCount} in ${res.supportedAbis.length} ABIs)',
          Broken.cpu,
        ),
        if (res.nativeLibraries.isEmpty)
          _buildEmptyCard('Pure Java/Kotlin APK (No native .so libraries)')
        else
          ...res.nativeLibraries.entries.map((entry) {
            final abi = entry.key;
            final libs = entry.value;
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: theme.dividerColor.withOpacity(0.06)),
              ),
              child: ExpansionTile(
                title: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        abi,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text('${libs.length} libraries', style: const TextStyle(fontSize: 12)),
                  ],
                ),
                children: libs.take(20).map((lib) {
                  return ListTile(
                    dense: true,
                    leading: const Icon(Icons.code, size: 16),
                    title: Text(
                      lib,
                      style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                    ),
                  );
                }).toList(),
              ),
            );
          }),

        const SizedBox(height: 18),

        // 3. Assets & Resources
        _buildSectionTitle(theme, 'Assets & Resources', Broken.folder),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: theme.dividerColor.withOpacity(0.06)),
          ),
          child: Column(
            children: [
              _buildInfoRow('Assets Count', '${res.totalAssetsCount} files'),
              const SizedBox(height: 6),
              _buildInfoRow('Assets Size', FileUtils.formatBytes(res.totalAssetsSize, 2)),
              const SizedBox(height: 6),
              _buildInfoRow('Resources Count', '${res.totalResFilesCount} res items'),
              const SizedBox(height: 6),
              _buildInfoRow('Compiled resources.arsc', FileUtils.formatBytes(res.resourcesArscSize, 2)),
            ],
          ),
        ),
      ],
    );
  }

  // --------------------------------------------------------------------------
  // Tab 2: Permissions Tab (Grouped into Dangerous vs Normal)
  // --------------------------------------------------------------------------

  Widget _buildPermissionsTab(ThemeData theme, ApkInspectionResult res) {
    final dangerous = res.permissions.where((p) => p.isDangerous).toList();
    final normal = res.permissions.where((p) => !p.isDangerous).toList();

    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        // Permission metrics card
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: dangerous.isNotEmpty
                ? Colors.amber.withOpacity(0.12)
                : Colors.green.withOpacity(0.12),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: dangerous.isNotEmpty ? Colors.amber.shade700 : Colors.green.shade700,
              width: 0.8,
            ),
          ),
          child: Row(
            children: [
              Icon(
                dangerous.isNotEmpty ? Icons.warning_amber_rounded : Icons.check_circle_outline,
                color: dangerous.isNotEmpty ? Colors.amber.shade800 : Colors.green.shade700,
                size: 28,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${dangerous.length} Sensitive / Dangerous Permissions',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13.5,
                        color: dangerous.isNotEmpty ? Colors.amber.shade900 : Colors.green.shade900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${normal.length} Normal & System Permissions (${res.permissions.length} total)',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: theme.textTheme.bodySmall?.color?.withOpacity(0.7),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        if (dangerous.isNotEmpty) ...[
          _buildSectionTitle(theme, 'Dangerous Permissions (${dangerous.length})', Broken.shield_cross),
          ...dangerous.map((p) => _buildPermissionTile(theme, p, isDangerous: true)),
          const SizedBox(height: 14),
        ],

        if (normal.isNotEmpty) ...[
          _buildSectionTitle(theme, 'Standard Permissions (${normal.length})', Broken.shield_tick),
          ...normal.map((p) => _buildPermissionTile(theme, p, isDangerous: false)),
        ],

        if (res.permissions.isEmpty)
          _buildEmptyCard('This APK requests no special permissions.'),
      ],
    );
  }

  Widget _buildPermissionTile(
    ThemeData theme,
    ApkPermissionInfo perm, {
    required bool isDangerous,
  }) {
    final shortName = perm.name.replaceAll('android.permission.', '');

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDangerous
              ? Colors.amber.shade600.withOpacity(0.3)
              : theme.dividerColor.withOpacity(0.06),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isDangerous ? Icons.security_rounded : Icons.lock_outline,
            size: 20,
            color: isDangerous ? Colors.amber.shade700 : theme.colorScheme.primary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  shortName,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: isDangerous ? Colors.amber.shade800 : null,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  perm.description,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: theme.textTheme.bodySmall?.color?.withOpacity(0.7),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  perm.name,
                  style: TextStyle(
                    fontSize: 10,
                    fontFamily: 'monospace',
                    color: theme.textTheme.bodySmall?.color?.withOpacity(0.4),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.copy, size: 16),
            tooltip: 'Copy permission name',
            onPressed: () => _copyToClipboard(perm.name, 'Permission'),
          ),
        ],
      ),
    );
  }

  // --------------------------------------------------------------------------
  // Tab 3: Components & Manifest Summary
  // --------------------------------------------------------------------------

  Widget _buildComponentsTab(ThemeData theme, ApkInspectionResult res) {
    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        _buildComponentExpansionCard(
          theme,
          title: 'Activities',
          items: res.activities,
          icon: Broken.direct_normal,
        ),
        const SizedBox(height: 10),
        _buildComponentExpansionCard(
          theme,
          title: 'Services',
          items: res.services,
          icon: Broken.cpu,
        ),
        const SizedBox(height: 10),
        _buildComponentExpansionCard(
          theme,
          title: 'Broadcast Receivers',
          items: res.receivers,
          icon: Broken.notification,
        ),
        const SizedBox(height: 10),
        _buildComponentExpansionCard(
          theme,
          title: 'Content Providers',
          items: res.providers,
          icon: Broken.data,
        ),
        const SizedBox(height: 18),

        // Raw Manifest Summary
        _buildSectionTitle(theme, 'AndroidManifest.xml Summary', Broken.document_text),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceVariant.withOpacity(0.3),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Generated XML overview', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  IconButton(
                    icon: const Icon(Icons.copy, size: 16),
                    onPressed: () => _copyToClipboard(res.rawManifestSummary, 'Manifest XML'),
                  ),
                ],
              ),
              const Divider(height: 12),
              SelectableText(
                res.rawManifestSummary,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildComponentExpansionCard(
    ThemeData theme, {
    required String title,
    required List<String> items,
    required IconData icon,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.dividerColor.withOpacity(0.06)),
      ),
      child: ExpansionTile(
        leading: Icon(icon, color: theme.colorScheme.primary, size: 20),
        title: Text(
          '$title (${items.length})',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
        ),
        children: items.isEmpty
            ? [
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text('None declared in manifest', style: TextStyle(fontSize: 12, color: Colors.grey)),
                ),
              ]
            : items.map((item) {
                return ListTile(
                  dense: true,
                  title: SelectableText(
                    item,
                    style: const TextStyle(fontSize: 11.5, fontFamily: 'monospace'),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.copy, size: 14),
                    onPressed: () => _copyToClipboard(item, title),
                  ),
                );
              }).toList(),
      ),
    );
  }

  // --------------------------------------------------------------------------
  // Tab 4: Certificates & Signatures
  // --------------------------------------------------------------------------

  Widget _buildCertificatesTab(ThemeData theme, ApkInspectionResult res) {
    if (res.certificates.isEmpty) {
      return Center(child: _buildEmptyCard('No signing certificates detected in META-INF.'));
    }

    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: res.certificates.map((cert) {
        return Container(
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: theme.dividerColor.withOpacity(0.06)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.02),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.verified_outlined, color: Colors.green, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          cert.fileName,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                        Text(
                          'Size: ${FileUtils.formatBytes(cert.size, 1)}',
                          style: TextStyle(
                            fontSize: 11,
                            color: theme.textTheme.bodySmall?.color?.withOpacity(0.6),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const Divider(height: 20),
              _buildHashRow(theme, 'SHA-256 Fingerprint', cert.sha256Digest),
              const SizedBox(height: 10),
              _buildHashRow(theme, 'SHA-1 Fingerprint', cert.sha1Digest),
              const SizedBox(height: 10),
              _buildHashRow(theme, 'MD5 Fingerprint', cert.md5Digest),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildHashRow(ThemeData theme, String label, String hash) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: theme.textTheme.bodySmall?.color?.withOpacity(0.7),
              ),
            ),
            InkWell(
              onTap: () => _copyToClipboard(hash, label),
              child: const Row(
                children: [
                  Text('Copy', style: TextStyle(fontSize: 11, color: Colors.blue)),
                  SizedBox(width: 2),
                  Icon(Icons.copy, size: 12, color: Colors.blue),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 3),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceVariant.withOpacity(0.3),
            borderRadius: BorderRadius.circular(8),
          ),
          child: SelectableText(
            hash,
            style: const TextStyle(
              fontSize: 11,
              fontFamily: 'monospace',
              letterSpacing: 0.5,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSectionTitle(ThemeData theme, String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Text(
            title,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 13.5,
              color: theme.colorScheme.primary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 12.5)),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5)),
      ],
    );
  }

  Widget _buildEmptyCard(String msg) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.grey.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Center(
        child: Text(
          msg,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 12.5, color: Colors.grey),
        ),
      ),
    );
  }

  String _getAndroidVersionName(int sdk) {
    switch (sdk) {
      case 35:
        return 'Android 15';
      case 34:
        return 'Android 14';
      case 33:
        return 'Android 13';
      case 32:
        return 'Android 12L';
      case 31:
        return 'Android 12';
      case 30:
        return 'Android 11';
      case 29:
        return 'Android 10';
      case 28:
        return 'Pie 9.0';
      case 27:
        return 'Oreo 8.1';
      case 26:
        return 'Oreo 8.0';
      case 25:
        return 'Nougat 7.1';
      case 24:
        return 'Nougat 7.0';
      case 23:
        return 'Marshmallow 6.0';
      case 21:
        return 'Lollipop 5.0';
      default:
        return sdk > 35 ? 'Android 16+' : 'Legacy';
    }
  }
}

class _SliverAppBarDelegate extends SliverPersistentHeaderDelegate {
  final TabBar _tabBar;
  final Color backgroundColor;

  _SliverAppBarDelegate(this._tabBar, {required this.backgroundColor});

  @override
  double get minExtent => _tabBar.preferredSize.height;
  @override
  double get maxExtent => _tabBar.preferredSize.height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Container(
      color: backgroundColor,
      child: _tabBar,
    );
  }

  @override
  bool shouldRebuild(_SliverAppBarDelegate oldDelegate) {
    return false;
  }
}
