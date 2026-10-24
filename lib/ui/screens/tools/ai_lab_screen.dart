import 'package:flutter/material.dart';
import '../../../core/icon_fonts/broken_icons.dart';
import '../../../services/ai_plugin_manager_service.dart';
import 'ai_doc_chat_screen.dart';
import 'ai_whisper_screen.dart';
import 'ai_tts_screen.dart';
import 'ai_image_cutout_screen.dart';
import 'ai_image_restoration_screen.dart';
import 'malware_scanner_screen.dart';

class AiLabScreen extends StatefulWidget {
  const AiLabScreen({super.key});

  @override
  State<AiLabScreen> createState() => _AiLabScreenState();
}

class _AiLabScreenState extends State<AiLabScreen> with SingleTickerProviderStateMixin {
  final AiPluginManagerService _pluginService = AiPluginManagerService();
  late TabController _tabController;
  PluginCategory? _selectedCategory;
  String _searchQuery = '';
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _pluginService.addListener(_onServiceUpdate);
    _pluginService.initialize();
  }

  void _onServiceUpdate() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _pluginService.removeListener(_onServiceUpdate);
    _tabController.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _launchTool(AiPluginModel plugin) {
    Widget destination;
    switch (plugin.id) {
      case 'doc_chat_qwen':
        destination = const AiDocChatScreen();
        break;
      case 'whisper_stt':
        destination = const AiWhisperScreen();
        break;
      case 'neural_tts':
        destination = const AiTtsScreen();
        break;
      case 'sam_cutout':
        destination = const AiImageCutoutScreen();
        break;
      case 'gfpgan_restoration':
        destination = const AiImageRestorationScreen();
        break;
      case 'malware_scanner':
        destination = const MalwareScannerScreen();
        break;
      default:
        return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => destination),
    );
  }

  void _showPluginDetails(AiPluginModel plugin) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E1E24) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: theme.dividerColor.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(_getIconForPlugin(plugin.id), color: theme.colorScheme.primary, size: 28),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          plugin.name,
                          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${plugin.categoryLabel} • ${plugin.version}',
                          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.primary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Text(
                plugin.description,
                style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
              ),
              const SizedBox(height: 20),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _infoChip(theme, 'RAM Req', plugin.ramRequirement, Broken.cpu),
                  _infoChip(theme, 'Quantization', plugin.quantization, Broken.code),
                  _infoChip(theme, 'Download Size', plugin.formattedDownloadSize, Broken.document_download),
                  _infoChip(theme, 'Installed Size', plugin.formattedInstalledSize, Broken.folder_2),
                ],
              ),
              const SizedBox(height: 20),
              Text(
                'Key Capabilities',
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              ...plugin.features.map(
                (f) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      Icon(Broken.tick_circle, size: 16, color: theme.colorScheme.primary),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(f, style: theme.textTheme.bodySmall),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  if (plugin.status == PluginStatus.installed) ...[
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Broken.trash, size: 18),
                        label: const Text('Uninstall'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.redAccent,
                          side: const BorderSide(color: Colors.redAccent),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        onPressed: () {
                          Navigator.pop(ctx);
                          _pluginService.uninstallPlugin(plugin.id);
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: FilledButton.icon(
                        icon: const Icon(Broken.play, size: 18),
                        label: const Text('Launch Tool'),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        onPressed: () {
                          Navigator.pop(ctx);
                          _launchTool(plugin);
                        },
                      ),
                    ),
                  ] else ...[
                    Expanded(
                      child: FilledButton.icon(
                        icon: const Icon(Broken.document_download, size: 18),
                        label: Text('Download Model (${plugin.formattedDownloadSize})'),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        onPressed: () {
                          Navigator.pop(ctx);
                          _pluginService.downloadPlugin(plugin.id);
                        },
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _infoChip(ThemeData theme, String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.5),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: theme.colorScheme.primary),
          const SizedBox(width: 6),
          Text(
            '$label: ',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
          ),
          Text(
            value,
            style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  IconData _getIconForPlugin(String id) {
    switch (id) {
      case 'doc_chat_qwen':
        return Broken.document_text;
      case 'whisper_stt':
        return Broken.microphone_2;
      case 'neural_tts':
        return Broken.music_filter;
      case 'sam_cutout':
        return Broken.scissor;
      case 'gfpgan_restoration':
        return Broken.magicpen;
      case 'malware_scanner':
        return Broken.shield_tick;
      default:
        return Broken.cpu;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('AI Lab & Plugins'),
        elevation: 0,
        backgroundColor: Colors.transparent,
        actions: [
          IconButton(
            icon: const Icon(Broken.refresh_2),
            tooltip: 'Check for Updates',
            onPressed: () => _pluginService.checkForUpdates(),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: theme.colorScheme.primary,
          unselectedLabelColor: theme.hintColor,
          indicatorColor: theme.colorScheme.primary,
          tabs: [
            Tab(text: 'All (${_pluginService.allPlugins.length})'),
            Tab(text: 'Installed (${_pluginService.installedPlugins.length})'),
            Tab(text: 'Updates (${_pluginService.updatesAvailable.length})'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildAllPluginsTab(theme, isDark),
          _buildInstalledTab(theme, isDark),
          _buildUpdatesTab(theme, isDark),
        ],
      ),
    );
  }

  Widget _buildAllPluginsTab(ThemeData theme, bool isDark) {
    final plugins = _pluginService.allPlugins.where((p) {
      if (_selectedCategory != null && p.category != _selectedCategory) {
        return false;
      }
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        return p.name.toLowerCase().contains(q) ||
            p.description.toLowerCase().contains(q) ||
            p.categoryLabel.toLowerCase().contains(q);
      }
      return true;
    }).toList();

    return Column(
      children: [
        _buildHeroBanner(theme, isDark),
        _buildSearchAndFilters(theme),
        Expanded(
          child: plugins.isEmpty
              ? _buildEmptyState(theme, 'No plugins found')
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  itemCount: plugins.length,
                  itemBuilder: (ctx, i) => _buildPluginCard(theme, isDark, plugins[i]),
                ),
        ),
      ],
    );
  }

  Widget _buildInstalledTab(ThemeData theme, bool isDark) {
    final installed = _pluginService.installedPlugins;
    if (installed.isEmpty) {
      return _buildEmptyState(
        theme,
        'No AI plugins installed yet.\nDownload plugins from the "All" tab to unlock on-device AI capabilities.',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: installed.length,
      itemBuilder: (ctx, i) => _buildPluginCard(theme, isDark, installed[i]),
    );
  }

  Widget _buildUpdatesTab(ThemeData theme, bool isDark) {
    final updates = _pluginService.updatesAvailable;
    if (updates.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Broken.tick_circle, size: 64, color: Colors.greenAccent.shade700),
            const SizedBox(height: 16),
            Text(
              'All Plugins Up to Date',
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'All installed on-device models are running the latest weights.',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: updates.length,
      itemBuilder: (ctx, i) => _buildPluginCard(theme, isDark, updates[i]),
    );
  }

  Widget _buildHeroBanner(ThemeData theme, bool isDark) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? [const Color(0xFF1E2640), const Color(0xFF151828)]
              : [const Color(0xFFE8F0FE), const Color(0xFFD6E4FF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.colorScheme.primary.withOpacity(0.15)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withOpacity(0.15),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(Broken.cpu, size: 32, color: theme.colorScheme.primary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'Modular On-Device AI',
                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        '100% Offline',
                        style: TextStyle(color: Colors.green, fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Download lightweight GGUF, TFLite, and ONNX models on demand to keep the base app compact.',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchAndFilters(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        children: [
          TextField(
            controller: _searchCtrl,
            decoration: InputDecoration(
              hintText: 'Search models, quantizations, audio...',
              prefixIcon: const Icon(Broken.search_normal_1, size: 20),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () {
                        setState(() {
                          _searchCtrl.clear();
                          _searchQuery = '';
                        });
                      },
                    )
                  : null,
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
              filled: true,
              fillColor: theme.colorScheme.surfaceContainerHighest.withOpacity(0.4),
            ),
            onChanged: (v) => setState(() => _searchQuery = v),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildFilterChip('All', null),
                const SizedBox(width: 8),
                _buildFilterChip('LLM & Chat', PluginCategory.llm),
                const SizedBox(width: 8),
                _buildFilterChip('Speech & Audio', PluginCategory.audio),
                const SizedBox(width: 8),
                _buildFilterChip('Vision & Image', PluginCategory.vision),
                const SizedBox(width: 8),
                _buildFilterChip('Security', PluginCategory.security),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, PluginCategory? category) {
    final isSelected = _selectedCategory == category;
    final theme = Theme.of(context);

    return FilterChip(
      selected: isSelected,
      label: Text(label),
      labelStyle: TextStyle(
        fontSize: 12,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        color: isSelected ? Colors.white : theme.textTheme.bodyMedium?.color,
      ),
      selectedColor: theme.colorScheme.primary,
      backgroundColor: theme.colorScheme.surfaceContainerHighest.withOpacity(0.4),
      checkmarkColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      onSelected: (val) => setState(() => _selectedCategory = val ? category : null),
    );
  }

  Widget _buildPluginCard(ThemeData theme, bool isDark, AiPluginModel plugin) {
    final isInstalled = plugin.status == PluginStatus.installed;
    final isDownloading = plugin.status == PluginStatus.downloading;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E24) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isInstalled
              ? theme.colorScheme.primary.withOpacity(0.3)
              : theme.dividerColor.withOpacity(0.08),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => _showPluginDetails(plugin),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(_getIconForPlugin(plugin.id), color: theme.colorScheme.primary, size: 24),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  plugin.name,
                                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.primary.withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  plugin.quantization,
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: theme.colorScheme.primary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            plugin.description,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(Broken.cpu, size: 14, color: theme.hintColor),
                    const SizedBox(width: 4),
                    Text(plugin.ramRequirement, style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor)),
                    const SizedBox(width: 14),
                    Icon(Broken.document_download, size: 14, color: theme.hintColor),
                    const SizedBox(width: 4),
                    Text(plugin.formattedDownloadSize, style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor)),
                    const Spacer(),
                    if (isInstalled)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.green.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Broken.tick_circle, size: 12, color: Colors.green),
                            SizedBox(width: 4),
                            Text('Installed', style: TextStyle(color: Colors.green, fontSize: 11, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                  ],
                ),
                if (isDownloading) ...[
                  const SizedBox(height: 12),
                  LinearProgressIndicator(
                    value: plugin.downloadProgress,
                    backgroundColor: theme.dividerColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Downloading weights: ${(plugin.downloadProgress * 100).toInt()}%',
                        style: theme.textTheme.bodySmall?.copyWith(fontSize: 11, color: theme.colorScheme.primary),
                      ),
                      InkWell(
                        onTap: () => _pluginService.cancelDownload(plugin.id),
                        child: Text(
                          'Cancel',
                          style: theme.textTheme.bodySmall?.copyWith(fontSize: 11, color: Colors.redAccent),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (isInstalled) ...[
                      OutlinedButton.icon(
                        icon: const Icon(Broken.play, size: 16),
                        label: const Text('Launch Tool'),
                        style: OutlinedButton.styleFrom(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () => _launchTool(plugin),
                      ),
                    ] else if (!isDownloading) ...[
                      FilledButton.icon(
                        icon: const Icon(Broken.document_download, size: 16),
                        label: Text('Download (${plugin.formattedDownloadSize})'),
                        style: FilledButton.styleFrom(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () => _pluginService.downloadPlugin(plugin.id),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme, String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Broken.cpu, size: 56, color: theme.hintColor.withOpacity(0.4)),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.hintColor),
            ),
          ],
        ),
      ),
    );
  }
}
