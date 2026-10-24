import 'dart:io';
import 'package:flutter/material.dart';
import '../../../core/icon_fonts/broken_icons.dart';
import '../../../models/network_connection_model.dart';
import '../../../services/network_connections_service.dart';
import '../../../services/remote/lan_client.dart';
import '../network_connection_wizard_screen.dart';
import '../remote_explorer_screen.dart';

class SmbFtpClientScreen extends StatefulWidget {
  const SmbFtpClientScreen({super.key});

  @override
  State<SmbFtpClientScreen> createState() => _SmbFtpClientScreenState();
}

class _SmbFtpClientScreenState extends State<SmbFtpClientScreen> {
  List<NetworkConnectionModel> _connections = [];
  bool _isLoading = true;

  // LAN Subnet Scanner State
  bool _isScanning = false;
  double _scanProgress = 0.0;
  final List<LanDiscoveredServer> _discoveredServers = [];

  @override
  void initState() {
    super.initState();
    _loadConnections();
  }

  Future<void> _loadConnections() async {
    await NetworkConnectionsService.init();
    if (mounted) {
      setState(() {
        _connections = NetworkConnectionsService.getConnections();
        _isLoading = false;
      });
    }
  }

  Future<void> _startSubnetScan() async {
    setState(() {
      _isScanning = true;
      _scanProgress = 0.0;
      _discoveredServers.clear();
    });

    try {
      final results = await LanClient.scanSubnet(
        onProgress: (p) {
          if (mounted) setState(() => _scanProgress = p);
        },
      );

      if (mounted) {
        setState(() {
          _discoveredServers.addAll(results);
          _isScanning = false;
        });

        if (results.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No SMB/FTP servers discovered on local subnet.')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isScanning = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Scan error: $e')),
        );
      }
    }
  }

  void _addDiscoveredServer(LanDiscoveredServer server) async {
    final newConn = NetworkConnectionModel(
      id: '${DateTime.now().millisecondsSinceEpoch}',
      name: server.name,
      type: server.type,
      host: server.host,
      port: server.port,
      username: '',
      password: '',
      rootPath: '/',
    );

    await NetworkConnectionsService.saveConnection(newConn);
    await _loadConnections();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Added ${server.name} to connections.'),
          backgroundColor: Colors.green.shade700,
        ),
      );
    }
  }

  Future<void> _deleteConnection(String id) async {
    await NetworkConnectionsService.deleteConnection(id);
    await _loadConnections();
  }

  void _openConnection(NetworkConnectionModel conn) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RemoteExplorerScreen(connection: conn),
      ),
    ).then((_) => _loadConnections());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('SMB & FTP Storage Client'),
        actions: [
          IconButton(
            icon: const Icon(Icons.radar),
            tooltip: 'Scan Local Network',
            onPressed: _isScanning ? null : _startSubnetScan,
          ),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Add Connection',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const NetworkConnectionWizardScreen(),
                ),
              ).then((_) => _loadConnections());
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Subnet Scan Banner if scanning
                  if (_isScanning) ...[
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: theme.colorScheme.primary.withOpacity(0.2)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Scanning local Wi-Fi subnet for servers...',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                              Text(
                                '${(_scanProgress * 100).round()}%',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          LinearProgressIndicator(value: _scanProgress),
                          const SizedBox(height: 6),
                          const Text(
                            'Checking SMB (445), FTP (21), SFTP (22), and WebDav (80/8080)',
                            style: TextStyle(fontSize: 11, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Discovered Servers Card
                  if (_discoveredServers.isNotEmpty) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Discovered on LAN (${_discoveredServers.length})',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                        TextButton(
                          onPressed: () => setState(() => _discoveredServers.clear()),
                          child: const Text('Dismiss', style: TextStyle(fontSize: 12)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ..._discoveredServers.map((server) {
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: theme.colorScheme.primary.withOpacity(0.1),
                            child: Icon(_getIconForType(server.type), color: theme.colorScheme.primary, size: 20),
                          ),
                          title: Text(server.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
                          subtitle: Text('${server.host}:${server.port} • ${server.type}', style: const TextStyle(fontSize: 11.5)),
                          trailing: FilledButton.tonal(
                            onPressed: () => _addDiscoveredServer(server),
                            child: const Text('Add'),
                          ),
                        ),
                      );
                    }),
                    const SizedBox(height: 20),
                  ],

                  // Saved Connections List
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Saved Connections (${_connections.length})',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      TextButton.icon(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const NetworkConnectionWizardScreen(),
                            ),
                          ).then((_) => _loadConnections());
                        },
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('New Server', style: TextStyle(fontSize: 12)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  if (_connections.isEmpty)
                    _buildEmptyState(theme)
                  else
                    ..._connections.map((conn) => _buildConnectionCard(theme, conn)),
                ],
              ),
            ),
    );
  }

  Widget _buildConnectionCard(ThemeData theme, NetworkConnectionModel conn) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: () => _openConnection(conn),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _getColorForType(conn.type).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(_getIconForType(conn.type), color: _getColorForType(conn.type), size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      conn.name,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${conn.type} • ${conn.host}:${conn.port}',
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.textTheme.bodySmall?.color?.withOpacity(0.65),
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, size: 20),
                onSelected: (val) {
                  if (val == 'open') {
                    _openConnection(conn);
                  } else if (val == 'delete') {
                    _deleteConnection(conn.id);
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'open',
                    child: Row(
                      children: [
                        Icon(Icons.folder_open, size: 18),
                        SizedBox(width: 8),
                        Text('Browse Storage'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete_outline, size: 18, color: Colors.redAccent),
                        SizedBox(width: 8),
                        Text('Delete', style: TextStyle(color: Colors.redAccent)),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Column(
          children: [
            Icon(Icons.cloud_off_outlined, size: 56, color: Colors.grey.shade400),
            const SizedBox(height: 14),
            const Text(
              'No Network Connections',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            const SizedBox(height: 6),
            const Text(
              'Connect to SMB (Windows/NAS), FTP, SFTP, or WebDav servers to browse remote files.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FilledButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const NetworkConnectionWizardScreen(),
                      ),
                    ).then((_) => _loadConnections());
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('Add Connection'),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: _isScanning ? null : _startSubnetScan,
                  icon: const Icon(Icons.radar),
                  label: const Text('Scan Subnet'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  IconData _getIconForType(String type) {
    switch (type.toUpperCase()) {
      case 'FTP':
        return Icons.folder_shared;
      case 'SFTP':
        return Icons.lock_outline;
      case 'LAN/SMB':
        return Icons.dns_outlined;
      case 'WEBDAV':
        return Icons.cloud_outlined;
      default:
        return Icons.storage;
    }
  }

  Color _getColorForType(String type) {
    switch (type.toUpperCase()) {
      case 'FTP':
        return Colors.teal;
      case 'SFTP':
        return Colors.indigo;
      case 'LAN/SMB':
        return Colors.blue;
      case 'WEBDAV':
        return Colors.deepPurple;
      default:
        return Colors.blueGrey;
    }
  }
}
