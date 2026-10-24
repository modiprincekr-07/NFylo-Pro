import 'dart:io';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/utils.dart';
import '../../../providers/file_manager_provider.dart';
import '../../../services/nearby_transfer_service.dart';
import '../internal_file_picker_screen.dart';

class NearbyTransferScreen extends StatefulWidget {
  final List<String>? initialFilesToSend;

  const NearbyTransferScreen({super.key, this.initialFilesToSend});

  @override
  State<NearbyTransferScreen> createState() => _NearbyTransferScreenState();
}

class _NearbyTransferScreenState extends State<NearbyTransferScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _service = NearbyTransferService.instance;

  // Sender State
  final List<String> _filesToSend = [];
  DiscoveredPeer? _selectedPeer;
  final TextEditingController _manualIpController = TextEditingController();

  // Pulse animation for radar
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();

    if (widget.initialFilesToSend != null) {
      _filesToSend.addAll(widget.initialFilesToSend!);
    }

    _service.addListener(_onServiceUpdate);
    _service.startDiscovery();
  }

  void _onServiceUpdate() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _service.removeListener(_onServiceUpdate);
    _service.stopDiscovery();
    _pulseController.dispose();
    _tabController.dispose();
    _manualIpController.dispose();
    super.dispose();
  }

  Future<void> _pickFiles() async {
    final rootPath = context.read<FileManagerProvider>().rootPath;
    final picked = await InternalFilePickerScreen.show(
      context,
      rootPath: rootPath,
      pickDirectory: false,
    );

    if (picked != null && picked.isNotEmpty) {
      setState(() {
        for (final p in picked) {
          if (!_filesToSend.contains(p)) _filesToSend.add(p);
        }
      });
    }
  }

  Future<void> _startSending(String targetIp, int targetPort) async {
    if (_filesToSend.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select files to send.')),
      );
      return;
    }

    try {
      await _service.sendFiles(
        peerIp: targetIp,
        peerPort: targetPort,
        filePaths: _filesToSend,
        onProgress: (prog) {},
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Transferred ${_filesToSend.length} files successfully!'),
            backgroundColor: Colors.green.shade700,
          ),
        );
        setState(() => _filesToSend.clear());
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Transfer failed: $e'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Nearby Transfer (Wi-Fi Direct)'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.send_rounded), text: 'Send Files'),
            Tab(icon: Icon(Icons.download_rounded), text: 'Receive'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildSendTab(theme),
          _buildReceiveTab(theme),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Tab 1: Send Files
  // ---------------------------------------------------------------------------

  Widget _buildSendTab(ThemeData theme) {
    final peers = _service.discoveredPeers;
    final isTransferring = _service.isTransferActive;
    final progress = _service.activeProgress;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Transfer Progress Card if active
          if (isTransferring && progress != null) ...[
            _buildTransferProgressBanner(theme, progress),
            const SizedBox(height: 16),
          ],

          // 1. Files to send section
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Selected Files (${_filesToSend.length})',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              FilledButton.tonalIcon(
                onPressed: isTransferring ? null : _pickFiles,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add Files'),
              ),
            ],
          ),
          const SizedBox(height: 10),

          if (_filesToSend.isEmpty)
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: theme.dividerColor.withOpacity(0.08)),
              ),
              child: const Center(
                child: Text(
                  'No files selected. Tap "Add Files" to pick photos, videos, or documents to send.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ),
            )
          else
            Container(
              constraints: const BoxConstraints(maxHeight: 180),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: theme.dividerColor.withOpacity(0.08)),
              ),
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 4),
                itemCount: _filesToSend.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final fPath = _filesToSend[index];
                  final size = File(fPath).existsSync() ? File(fPath).lengthSync() : 0;
                  return ListTile(
                    dense: true,
                    title: Text(
                      p.basename(fPath),
                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(FileUtils.formatBytes(size, 1), style: const TextStyle(fontSize: 11)),
                    trailing: IconButton(
                      icon: const Icon(Icons.close, size: 18, color: Colors.redAccent),
                      onPressed: isTransferring
                          ? null
                          : () => setState(() => _filesToSend.removeAt(index)),
                    ),
                  );
                },
              ),
            ),

          const SizedBox(height: 24),

          // 2. Discovered nearby receivers
          const Text(
            'Nearby Devices on Wi-Fi',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
          const SizedBox(height: 10),

          if (peers.isEmpty)
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: theme.dividerColor.withOpacity(0.08)),
              ),
              child: Column(
                children: [
                  RotationTransition(
                    turns: _pulseController,
                    child: Icon(Icons.radar, size: 40, color: theme.colorScheme.primary),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Searching for receiving devices...',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Make sure the other device opens the "Receive" tab on the same Wi-Fi or Hotspot.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11.5, color: Colors.grey),
                  ),
                ],
              ),
            )
          else
            ...peers.map((peer) {
              final isSelected = _selectedPeer?.ip == peer.ip;
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(
                    color: isSelected ? theme.colorScheme.primary : Colors.transparent,
                    width: 2,
                  ),
                ),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: theme.colorScheme.primary.withOpacity(0.12),
                    child: Icon(Icons.phone_android, color: theme.colorScheme.primary, size: 22),
                  ),
                  title: Text(peer.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
                  subtitle: Text('${peer.ip}:${peer.port}', style: const TextStyle(fontSize: 11.5)),
                  trailing: FilledButton(
                    onPressed: isTransferring
                        ? null
                        : () => _startSending(peer.ip, peer.port),
                    child: const Text('Send'),
                  ),
                ),
              );
            }),

          const SizedBox(height: 20),

          // 3. Manual IP Connect Option
          ExpansionTile(
            title: const Text('Connect Manually by IP', style: TextStyle(fontSize: 13)),
            leading: const Icon(Icons.settings_ethernet, size: 20),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _manualIpController,
                        decoration: InputDecoration(
                          hintText: 'Receiver IP (e.g. 192.168.1.50)',
                          isDense: true,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    FilledButton(
                      onPressed: isTransferring
                          ? null
                          : () {
                              final ip = _manualIpController.text.trim();
                              if (ip.isNotEmpty) _startSending(ip, 41235);
                            },
                      child: const Text('Send'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Tab 2: Receive Mode
  // ---------------------------------------------------------------------------

  Widget _buildReceiveTab(ThemeData theme) {
    final isReceiving = _service.isReceiving;
    final isTransferring = _service.isTransferActive;
    final progress = _service.activeProgress;
    final receivedFiles = _service.receivedFiles;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Transfer Progress Banner if receiving
          if (isTransferring && progress != null) ...[
            _buildTransferProgressBanner(theme, progress),
            const SizedBox(height: 16),
          ],

          // Receiver Status Card
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: theme.dividerColor.withOpacity(0.08)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.02),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
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
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: isReceiving ? Colors.green : Colors.grey,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          isReceiving ? 'Ready to Receive' : 'Receiver Offline',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: isReceiving ? Colors.green : Colors.grey,
                          ),
                        ),
                      ],
                    ),
                    Switch(
                      value: isReceiving,
                      onChanged: (val) {
                        if (val) {
                          _service.startReceiving();
                        } else {
                          _service.stopReceiving();
                        }
                      },
                    ),
                  ],
                ),

                if (isReceiving) ...[
                  const SizedBox(height: 16),
                  // QR Code for Quick Pair
                  QrImageView(
                    data: 'http://${_service.localIp}:${_service.port}',
                    version: QrVersions.auto,
                    size: 150,
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'IP Address: ${_service.localIp}',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Port: ${_service.port} • Saved in Download/NFylo_Nearby',
                    style: const TextStyle(fontSize: 11.5, color: Colors.grey),
                  ),
                ] else ...[
                  const SizedBox(height: 12),
                  const Text(
                    'Turn on receiver mode to become discoverable to nearby senders on the same Wi-Fi or Hotspot.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Received Files List
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Received Files (${receivedFiles.length})',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
          ),
          const SizedBox(height: 8),

          if (receivedFiles.isEmpty)
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.grey.withOpacity(0.06),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Center(
                child: Text('No files received yet in this session.', style: TextStyle(fontSize: 12, color: Colors.grey)),
              ),
            )
          else
            ...receivedFiles.map((fPath) {
              final size = File(fPath).existsSync() ? File(fPath).lengthSync() : 0;
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: const Icon(Icons.file_present_outlined, color: Colors.green),
                  title: Text(
                    p.basename(fPath),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(FileUtils.formatBytes(size, 1), style: const TextStyle(fontSize: 11)),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.open_in_new, size: 20),
                        tooltip: 'Open',
                        onPressed: () => OpenFilex.open(fPath),
                      ),
                      IconButton(
                        icon: const Icon(Icons.share, size: 20),
                        tooltip: 'Share',
                        onPressed: () => Share.shareXFiles([XFile(fPath)]),
                      ),
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildTransferProgressBanner(ThemeData theme, TransferFileProgress prog) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.colorScheme.primary.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  prog.fileName,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                '${prog.speedMbps.toStringAsFixed(1)} MB/s',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(value: prog.progressPercent),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${FileUtils.formatBytes(prog.bytesSentOrReceived, 1)} / ${FileUtils.formatBytes(prog.totalBytes, 1)}',
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
              Text(
                '${(prog.progressPercent * 100).round()}%',
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
