import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/utils.dart';
import '../../../services/media_server_service.dart';

class MediaServerScreen extends StatefulWidget {
  const MediaServerScreen({super.key});

  @override
  State<MediaServerScreen> createState() => _MediaServerScreenState();
}

class _MediaServerScreenState extends State<MediaServerScreen> {
  final _service = MediaServerService.instance;
  String _selectedStoragePath = '/storage/emulated/0';

  final List<Map<String, String>> _storagePresets = [
    {'name': 'All Internal Storage', 'path': '/storage/emulated/0'},
    {'name': 'Downloads Only', 'path': '/storage/emulated/0/Download'},
    {'name': 'Camera & Photos (DCIM)', 'path': '/storage/emulated/0/DCIM'},
    {'name': 'Movies & Videos', 'path': '/storage/emulated/0/Movies'},
  ];

  @override
  void initState() {
    super.initState();
    _service.addListener(_onServiceUpdate);
  }

  void _onServiceUpdate() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _service.removeListener(_onServiceUpdate);
    super.dispose();
  }

  Future<void> _toggleServer() async {
    if (_service.isRunning) {
      await _service.stopServer();
    } else {
      await _service.startServer(rootStoragePath: _selectedStoragePath);
    }
  }

  void _copyUrl() {
    Clipboard.setData(ClipboardData(text: _service.serverUrl));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Copied URL: ${_service.serverUrl}')),
    );
  }

  void _openInBrowser() async {
    final uri = Uri.parse(_service.serverUrl);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isRunning = _service.isRunning;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Media Server & Manage on PC'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // Server Switch & Status Header Card
            Container(
              padding: const EdgeInsets.all(20),
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
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 14,
                            height: 14,
                            decoration: BoxDecoration(
                              color: isRunning ? Colors.green : Colors.grey,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            isRunning ? 'Server Online' : 'Server Stopped',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              color: isRunning ? Colors.green : Colors.grey,
                            ),
                          ),
                        ],
                      ),
                      Switch(
                        value: isRunning,
                        onChanged: (_) => _toggleServer(),
                      ),
                    ],
                  ),

                  if (isRunning) ...[
                    const SizedBox(height: 18),
                    // QR Code
                    Center(
                      child: QrImageView(
                        data: _service.serverUrl,
                        version: QrVersions.auto,
                        size: 150,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _service.serverUrl,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Open this URL in any PC, Mac, iPad, or Smart TV web browser.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        OutlinedButton.icon(
                          onPressed: _copyUrl,
                          icon: const Icon(Icons.copy, size: 16),
                          label: const Text('Copy URL'),
                        ),
                        const SizedBox(width: 10),
                        FilledButton.tonalIcon(
                          onPressed: _openInBrowser,
                          icon: const Icon(Icons.open_in_browser, size: 16),
                          label: const Text('Open'),
                        ),
                      ],
                    ),
                  ] else ...[
                    const SizedBox(height: 12),
                    const Text(
                      'Turn on to stream videos and music to Smart TVs and browse/manage phone files from a PC web browser on the same Wi-Fi.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12.5, color: Colors.grey),
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 20),

            // DLNA & UPnP Indicator Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withOpacity(0.08),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: theme.colorScheme.primary.withOpacity(0.2)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withOpacity(0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.tv, color: theme.colorScheme.primary, size: 24),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'DLNA / UPnP Media Broadcaster',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          isRunning
                              ? 'Active on SSDP 239.255.255.250:1900. Discoverable on Smart TVs, Windows Media Player, and VLC.'
                              : 'Broadcasts media server beacon automatically when server is turned on.',
                          style: const TextStyle(fontSize: 11.5, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Shared Storage Path Selector
            if (!isRunning) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Storage Folder to Share',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: theme.dividerColor.withOpacity(0.08)),
                ),
                child: Column(
                  children: _storagePresets.map((preset) {
                    final isSelected = _selectedStoragePath == preset['path'];
                    return RadioListTile<String>(
                      title: Text(preset['name']!, style: const TextStyle(fontSize: 13.5)),
                      subtitle: Text(preset['path']!, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                      value: preset['path']!,
                      groupValue: _selectedStoragePath,
                      onChanged: (val) {
                        if (val != null) setState(() => _selectedStoragePath = val);
                      },
                    );
                  }).toList(),
                ),
              ),
            ] else ...[
              // Live Traffic Metrics Card
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: theme.dividerColor.withOpacity(0.08)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        children: [
                          const Text('Active Clients', style: TextStyle(fontSize: 11, color: Colors.grey)),
                          const SizedBox(height: 4),
                          Text(
                            '${_service.activeClientsCount}',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
                          ),
                        ],
                      ),
                    ),
                    Container(height: 30, width: 1, color: theme.dividerColor.withOpacity(0.1)),
                    Expanded(
                      child: Column(
                        children: [
                          const Text('Total Streamed', style: TextStyle(fontSize: 11, color: Colors.grey)),
                          const SizedBox(height: 4),
                          Text(
                            FileUtils.formatBytes(_service.totalStreamedBytes, 1),
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
