import 'dart:io';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

import '../../../core/utils.dart';
import '../../../services/cloud_drive_service.dart';

class CloudStorageScreen extends StatefulWidget {
  const CloudStorageScreen({super.key});

  @override
  State<CloudStorageScreen> createState() => _CloudStorageScreenState();
}

class _CloudStorageScreenState extends State<CloudStorageScreen> {
  final _driveService = CloudDriveService.instance;

  // Folder navigation stack
  final List<Map<String, String>> _folderStack = [
    {'id': 'root', 'name': 'My Drive'}
  ];

  List<DriveItem> _items = [];
  bool _isLoading = false;
  String? _errorMessage;

  // Search
  final TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;

  // Download state
  String? _downloadingFileId;
  double _downloadProgress = 0.0;

  @override
  void initState() {
    super.initState();
    _driveService.addListener(_onServiceUpdate);
    _driveService.init().then((_) {
      if (_driveService.isSignedIn) {
        _loadCurrentFolder();
      }
    });
  }

  void _onServiceUpdate() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _driveService.removeListener(_onServiceUpdate);
    _searchController.dispose();
    super.dispose();
  }

  String get _currentFolderId => _folderStack.last['id']!;

  Future<void> _loadCurrentFolder() async {
    if (!_driveService.isSignedIn) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final filter = _isSearching ? _searchController.text.trim() : null;
      final results = await _driveService.listFiles(
        folderId: _currentFolderId,
        searchFilter: filter,
      );

      if (mounted) {
        setState(() {
          _items = results;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = '$e';
          _isLoading = false;
        });
      }
    }
  }

  void _navigateToFolder(DriveItem folder) {
    setState(() {
      _folderStack.add({'id': folder.id, 'name': folder.name});
      _isSearching = false;
      _searchController.clear();
    });
    _loadCurrentFolder();
  }

  void _navigateUpTo(int index) {
    if (index < _folderStack.length - 1) {
      setState(() {
        _folderStack.removeRange(index + 1, _folderStack.length);
        _isSearching = false;
        _searchController.clear();
      });
      _loadCurrentFolder();
    }
  }

  Future<void> _downloadItem(DriveItem item) async {
    setState(() {
      _downloadingFileId = item.id;
      _downloadProgress = 0.0;
    });

    try {
      final outPath = await _driveService.downloadFile(
        fileId: item.id,
        fileName: item.name,
        onProgress: (p) => setState(() => _downloadProgress = p),
      );

      setState(() => _downloadingFileId = null);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Downloaded: ${p.basename(outPath)}'),
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
      setState(() => _downloadingFileId = null);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Download failed: $e'), backgroundColor: Colors.red.shade700),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isSignedIn = _driveService.isSignedIn;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Google Drive'),
        actions: [
          if (isSignedIn) ...[
            IconButton(
              icon: Icon(_isSearching ? Icons.close : Icons.search),
              onPressed: () {
                setState(() {
                  _isSearching = !_isSearching;
                  if (!_isSearching) {
                    _searchController.clear();
                    _loadCurrentFolder();
                  }
                });
              },
            ),
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _loadCurrentFolder,
            ),
          ],
        ],
      ),
      body: !isSignedIn
          ? _buildSignInView(theme)
          : _buildDriveWorkspace(theme),
    );
  }

  // ---------------------------------------------------------------------------
  // Sign In View
  // ---------------------------------------------------------------------------

  Widget _buildSignInView(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.add_to_drive, size: 64, color: Colors.blue),
            ),
            const SizedBox(height: 24),
            Text(
              'Connect Google Drive',
              style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Text(
              'Access your cloud files, documents, and photos directly inside NFylo.\nBrowse folders and download files to local storage with one tap.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: theme.textTheme.bodySmall?.color?.withOpacity(0.7),
                height: 1.4,
              ),
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: () async {
                try {
                  final ok = await _driveService.signIn();
                  if (ok) _loadCurrentFolder();
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Sign In error: $e')),
                  );
                }
              },
              icon: const Icon(Icons.login),
              label: const Text('Sign in with Google'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Drive Workspace
  // ---------------------------------------------------------------------------

  Widget _buildDriveWorkspace(ThemeData theme) {
    final user = _driveService.currentUser;

    return Column(
      children: [
        // User Account Header Card
        if (user != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              border: Border(bottom: BorderSide(color: theme.dividerColor.withOpacity(0.08))),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: theme.colorScheme.primary.withOpacity(0.15),
                  child: Text(
                    (user.displayName?.isNotEmpty == true) ? user.displayName![0] : 'G',
                    style: TextStyle(fontWeight: FontWeight.bold, color: theme.colorScheme.primary),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(user.displayName ?? 'Google User', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      Text(user.email, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.logout, size: 20, color: Colors.grey),
                  tooltip: 'Sign Out',
                  onPressed: () => _driveService.signOut(),
                ),
              ],
            ),
          ),

        // Search Bar if active
        if (_isSearching)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: TextField(
              controller: _searchController,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Search Drive files...',
                isDense: true,
                prefixIcon: const Icon(Icons.search, size: 20),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onSubmitted: (_) => _loadCurrentFolder(),
            ),
          ),

        // Breadcrumbs
        Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _folderStack.length,
            separatorBuilder: (_, __) => const Icon(Icons.chevron_right, size: 18, color: Colors.grey),
            itemBuilder: (context, index) {
              final isLast = index == _folderStack.length - 1;
              return Center(
                child: InkWell(
                  onTap: () => _navigateUpTo(index),
                  child: Text(
                    _folderStack[index]['name']!,
                    style: TextStyle(
                      fontWeight: isLast ? FontWeight.bold : FontWeight.normal,
                      color: isLast ? theme.colorScheme.primary : theme.textTheme.bodyMedium?.color,
                      fontSize: 13,
                    ),
                  ),
                ),
              );
            },
          ),
        ),

        const Divider(height: 1),

        // Files List / Loading / Error
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _errorMessage != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          _errorMessage!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.redAccent, fontSize: 13),
                        ),
                      ),
                    )
                  : _items.isEmpty
                      ? const Center(
                          child: Text('This folder is empty.', style: TextStyle(color: Colors.grey)),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          itemCount: _items.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final item = _items[index];
                            final isDownloading = _downloadingFileId == item.id;

                            return ListTile(
                              leading: Icon(
                                item.isFolder
                                    ? Icons.folder
                                    : _getIconForMime(item.mimeType),
                                color: item.isFolder
                                    ? Colors.amber.shade700
                                    : theme.colorScheme.primary,
                                size: 28,
                              ),
                              title: Text(
                                item.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
                              ),
                              subtitle: Text(
                                item.isFolder ? 'Folder' : FileUtils.formatBytes(item.size, 1),
                                style: const TextStyle(fontSize: 11.5, color: Colors.grey),
                              ),
                              trailing: item.isFolder
                                  ? const Icon(Icons.chevron_right, size: 20, color: Colors.grey)
                                  : isDownloading
                                      ? SizedBox(
                                          width: 24,
                                          height: 24,
                                          child: CircularProgressIndicator(
                                            value: _downloadProgress > 0 ? _downloadProgress : null,
                                            strokeWidth: 2.5,
                                          ),
                                        )
                                      : IconButton(
                                          icon: const Icon(Icons.download_rounded),
                                          tooltip: 'Download to Device',
                                          onPressed: () => _downloadItem(item),
                                        ),
                              onTap: () {
                                if (item.isFolder) {
                                  _navigateToFolder(item);
                                } else {
                                  _downloadItem(item);
                                }
                              },
                            );
                          },
                        ),
        ),
      ],
    );
  }

  IconData _getIconForMime(String mime) {
    if (mime.contains('image')) return Icons.image_outlined;
    if (mime.contains('video')) return Icons.movie_outlined;
    if (mime.contains('audio')) return Icons.audio_file_outlined;
    if (mime.contains('pdf')) return Icons.picture_as_pdf_outlined;
    if (mime.contains('document') || mime.contains('text')) return Icons.description_outlined;
    return Icons.insert_drive_file_outlined;
  }
}
