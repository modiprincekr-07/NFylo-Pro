import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

class DiscoveredPeer {
  final String name;
  final String ip;
  final int port;
  final DateTime lastSeen;

  DiscoveredPeer({
    required this.name,
    required this.ip,
    required this.port,
    required this.lastSeen,
  });

  String get endpoint => 'http://$ip:$port';
}

class TransferFileProgress {
  final String fileName;
  final int totalBytes;
  final int bytesSentOrReceived;
  final double speedMbps;
  final double progressPercent;

  TransferFileProgress({
    required this.fileName,
    required this.totalBytes,
    required this.bytesSentOrReceived,
    required this.speedMbps,
    required this.progressPercent,
  });
}

class NearbyTransferService extends ChangeNotifier {
  static final NearbyTransferService instance = NearbyTransferService._();
  NearbyTransferService._();

  static const int _p2pPort = 41235;
  static const int _beaconPort = 41234;
  static const String _defaultNearbyDir =
      '/storage/emulated/0/Download/NFylo_Nearby';

  HttpServer? _receiverServer;
  RawDatagramSocket? _beaconSocket;
  Timer? _beaconTimer;

  bool _isReceiving = false;
  String _localIp = '';
  String _deviceName = '';

  // Peer discovery state for sender
  final Map<String, DiscoveredPeer> _discoveredPeers = {};
  RawDatagramSocket? _listenerSocket;

  // Active Transfer State
  bool _isTransferActive = false;
  TransferFileProgress? _activeProgress;
  final List<String> _receivedFiles = [];

  bool get isReceiving => _isReceiving;
  bool get isTransferActive => _isTransferActive;
  String get localIp => _localIp;
  int get port => _p2pPort;
  String get deviceName => _deviceName;
  List<DiscoveredPeer> get discoveredPeers => _discoveredPeers.values.toList();
  TransferFileProgress? get activeProgress => _activeProgress;
  List<String> get receivedFiles => List.unmodifiable(_receivedFiles);

  static Directory _getOutputDir() {
    final dir = Directory(_defaultNearbyDir);
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return dir;
  }

  /// Obtains current device's local Wi-Fi / Hotspot IPv4 address.
  static Future<String> getLocalIpAddress() async {
    try {
      final interfaces = await NetworkInterface.list();
      for (final interface in interfaces) {
        for (final addr in interface.addresses) {
          if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
            return addr.address;
          }
        }
      }
    } catch (_) {}
    return '127.0.0.1';
  }

  // ---------------------------------------------------------------------------
  // Receiver Mode
  // ---------------------------------------------------------------------------

  /// Starts listening as a P2P receiver and broadcasts presence on local network.
  Future<void> startReceiving({String? customDeviceName}) async {
    if (_isReceiving) return;

    _localIp = await getLocalIpAddress();
    _deviceName = customDeviceName ?? (Platform.isAndroid ? 'Android Device' : 'NFylo Peer');

    // 1. Start HTTP upload listener
    _receiverServer = await HttpServer.bind(InternetAddress.anyIPv4, _p2pPort);
    _receiverServer!.listen(_handleIncomingRequest);

    // 2. Start UDP beacon broadcasting
    try {
      _beaconSocket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      _beaconSocket!.broadcastEnabled = true;

      _beaconTimer = Timer.periodic(const Duration(milliseconds: 1500), (_) {
        if (_beaconSocket != null) {
          final payload = json.encode({
            'type': 'NFYLO_P2P',
            'name': _deviceName,
            'ip': _localIp,
            'port': _p2pPort,
          });
          _beaconSocket!.send(
            utf8.encode(payload),
            InternetAddress('255.255.255.255'),
            _beaconPort,
          );
        }
      });
    } catch (_) {}

    _isReceiving = true;
    notifyListeners();
  }

  /// Stops receiver server and beacon.
  Future<void> stopReceiving() async {
    _beaconTimer?.cancel();
    _beaconTimer = null;
    _beaconSocket?.close();
    _beaconSocket = null;

    await _receiverServer?.close(force: true);
    _receiverServer = null;

    _isReceiving = false;
    notifyListeners();
  }

  Future<void> _handleIncomingRequest(HttpRequest request) async {
    final path = request.uri.path;

    if (request.method == 'GET' && path == '/info') {
      request.response
        ..headers.contentType = ContentType.json
        ..write(json.encode({
          'name': _deviceName,
          'ip': _localIp,
          'port': _p2pPort,
          'status': 'ready',
        }));
      await request.response.close();
      return;
    }

    if (request.method == 'POST' && path == '/upload') {
      final queryParams = request.uri.queryParameters;
      final rawName = queryParams['name'] ?? 'received_file_${DateTime.now().millisecondsSinceEpoch}';
      final fileName = p.basename(rawName);
      final totalSize = int.tryParse(queryParams['size'] ?? '0') ?? 0;

      final outDir = _getOutputDir();
      final destinationFile = File(p.join(outDir.path, fileName));
      final sink = destinationFile.openWrite();

      _isTransferActive = true;
      int received = 0;
      final stopwatch = Stopwatch()..start();

      try {
        await for (final chunk in request) {
          sink.add(chunk);
          received += chunk.length;

          final elapsedSec = stopwatch.elapsedMilliseconds / 1000.0;
          final speedMbps = elapsedSec > 0
              ? ((received * 8) / (1024 * 1024)) / elapsedSec
              : 0.0;
          final progress = totalSize > 0 ? (received / totalSize).clamp(0.0, 1.0) : 0.5;

          _activeProgress = TransferFileProgress(
            fileName: fileName,
            totalBytes: totalSize,
            bytesSentOrReceived: received,
            speedMbps: speedMbps,
            progressPercent: progress,
          );
          notifyListeners();
        }

        await sink.flush();
        await sink.close();

        _receivedFiles.insert(0, destinationFile.path);

        request.response
          ..statusCode = HttpStatus.ok
          ..write(json.encode({'status': 'success', 'path': destinationFile.path}));
        await request.response.close();
      } catch (e) {
        await sink.close();
        request.response
          ..statusCode = HttpStatus.internalServerError
          ..write(json.encode({'status': 'error', 'message': '$e'}));
        await request.response.close();
      } finally {
        _isTransferActive = false;
        _activeProgress = null;
        notifyListeners();
      }
      return;
    }

    request.response
      ..statusCode = HttpStatus.notFound
      ..write('Not Found');
    await request.response.close();
  }

  // ---------------------------------------------------------------------------
  // Sender Mode: Peer Discovery & Sending
  // ---------------------------------------------------------------------------

  /// Starts listening for nearby peer discovery beacons.
  Future<void> startDiscovery() async {
    _discoveredPeers.clear();

    try {
      _listenerSocket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        _beaconPort,
        reuseAddress: true,
        reusePort: true,
      );

      _listenerSocket!.listen((event) {
        if (event == RawSocketEvent.read) {
          final datagram = _listenerSocket?.receive();
          if (datagram != null) {
            try {
              final str = utf8.decode(datagram.data);
              final map = json.decode(str) as Map<String, dynamic>;
              if (map['type'] == 'NFYLO_P2P') {
                final ip = map['ip'] as String;
                final port = map['port'] as int;
                final name = map['name'] as String;

                _discoveredPeers[ip] = DiscoveredPeer(
                  name: name,
                  ip: ip,
                  port: port,
                  lastSeen: DateTime.now(),
                );
                notifyListeners();
              }
            } catch (_) {}
          }
        }
      });
    } catch (_) {}
    notifyListeners();
  }

  /// Stops peer discovery.
  void stopDiscovery() {
    _listenerSocket?.close();
    _listenerSocket = null;
  }

  /// Sends a list of files to the target peer endpoint via high-speed HTTP streaming.
  Future<void> sendFiles({
    required String peerIp,
    required int peerPort,
    required List<String> filePaths,
    required void Function(TransferFileProgress progress) onProgress,
  }) async {
    final client = HttpClient();
    _isTransferActive = true;

    try {
      for (final filePath in filePaths) {
        final file = File(filePath);
        if (!file.existsSync()) continue;

        final fileName = p.basename(filePath);
        final totalSize = await file.length();

        final uri = Uri.parse(
          'http://$peerIp:$peerPort/upload?name=${Uri.encodeComponent(fileName)}&size=$totalSize',
        );

        final request = await client.postUrl(uri);
        request.headers.chunkedTransferEncoding = true;

        int sent = 0;
        final stopwatch = Stopwatch()..start();

        final fileStream = file.openRead();
        await for (final chunk in fileStream) {
          request.add(chunk);
          sent += chunk.length;

          final elapsedSec = stopwatch.elapsedMilliseconds / 1000.0;
          final speedMbps = elapsedSec > 0
              ? ((sent * 8) / (1024 * 1024)) / elapsedSec
              : 0.0;
          final pct = totalSize > 0 ? (sent / totalSize).clamp(0.0, 1.0) : 0.5;

          final prog = TransferFileProgress(
            fileName: fileName,
            totalBytes: totalSize,
            bytesSentOrReceived: sent,
            speedMbps: speedMbps,
            progressPercent: pct,
          );

          _activeProgress = prog;
          onProgress(prog);
          notifyListeners();
        }

        final response = await request.close();
        if (response.statusCode != HttpStatus.ok) {
          throw Exception('Receiver rejected file: ${response.statusCode}');
        }
      }
    } finally {
      client.close();
      _isTransferActive = false;
      _activeProgress = null;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    stopReceiving();
    stopDiscovery();
    super.dispose();
  }
}
