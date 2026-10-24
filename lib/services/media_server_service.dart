import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;

class MediaServerService extends ChangeNotifier {
  static final MediaServerService instance = MediaServerService._();
  MediaServerService._();

  static const int defaultPort = 8085;
  static const int _ssdpPort = 1900;
  static final InternetAddress _ssdpAddress = InternetAddress('239.255.255.250');

  HttpServer? _httpServer;
  RawDatagramSocket? _ssdpSocket;
  Timer? _ssdpTimer;

  bool _isRunning = false;
  String _localIp = '';
  int _port = defaultPort;
  String _rootPath = '/storage/emulated/0';
  int _activeClientsCount = 0;
  int _totalStreamedBytes = 0;

  bool get isRunning => _isRunning;
  String get localIp => _localIp;
  int get port => _port;
  String get rootPath => _rootPath;
  String get serverUrl => 'http://$_localIp:$_port';
  int get activeClientsCount => _activeClientsCount;
  int get totalStreamedBytes => _totalStreamedBytes;

  /// Starts the HTTP Streaming Server & DLNA SSDP broadcaster.
  Future<void> startServer({
    String? rootStoragePath,
    int? customPort,
  }) async {
    if (_isRunning) return;

    _rootPath = rootStoragePath ?? '/storage/emulated/0';
    _port = customPort ?? defaultPort;
    _localIp = await _findLocalIp();

    // 1. Bind HTTP Streaming Server
    _httpServer = await HttpServer.bind(InternetAddress.anyIPv4, _port);
    _httpServer!.listen(_handleHttpRequest);

    // 2. Bind SSDP Multicast Socket for DLNA discovery
    _startSsdpBroadcast();

    _isRunning = true;
    notifyListeners();
  }

  /// Stops the server and discovery sockets.
  Future<void> stopServer() async {
    _ssdpTimer?.cancel();
    _ssdpTimer = null;
    _ssdpSocket?.close();
    _ssdpSocket = null;

    await _httpServer?.close(force: true);
    _httpServer = null;

    _isRunning = false;
    _activeClientsCount = 0;
    notifyListeners();
  }

  Future<String> _findLocalIp() async {
    try {
      final interfaces = await NetworkInterface.list();
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
            return addr.address;
          }
        }
      }
    } catch (_) {}
    return '127.0.0.1';
  }

  // ---------------------------------------------------------------------------
  // DLNA SSDP Discovery Broadcaster
  // ---------------------------------------------------------------------------

  void _startSsdpBroadcast() async {
    try {
      _ssdpSocket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        0,
        reuseAddress: true,
        reusePort: true,
      );
      _ssdpSocket!.broadcastEnabled = true;

      // Broadcast periodic UPnP NOTIFY alive message
      _ssdpTimer = Timer.periodic(const Duration(seconds: 3), (_) {
        _sendSsdpAlive();
      });
      _sendSsdpAlive();

      // Listen for TV M-SEARCH queries
      _ssdpSocket!.listen((event) {
        if (event == RawSocketEvent.read) {
          final datagram = _ssdpSocket?.receive();
          if (datagram != null) {
            final msg = utf8.decode(datagram.data, allowMalformed: true);
            if (msg.contains('M-SEARCH') &&
                (msg.contains('ssdp:all') ||
                    msg.contains('upnp:rootdevice') ||
                    msg.contains('MediaServer'))) {
              _respondToMSearch(datagram.address, datagram.port);
            }
          }
        }
      });
    } catch (_) {}
  }

  void _sendSsdpAlive() {
    if (_ssdpSocket == null) return;
    final notifyMsg =
        'NOTIFY * HTTP/1.1\r\n'
        'HOST: 239.255.255.250:1900\r\n'
        'NT: urn:schemas-upnp-org:device:MediaServer:1\r\n'
        'NTS: ssdp:alive\r\n'
        'LOCATION: http://$_localIp:$_port/dlna/device.xml\r\n'
        'USN: uuid:nfylo-media-server-01::urn:schemas-upnp-org:device:MediaServer:1\r\n'
        'CACHE-CONTROL: max-age=1800\r\n'
        'SERVER: NFylo/1.0 UPnP/1.0 DLNADOC/1.50\r\n\r\n';

    try {
      _ssdpSocket!.send(utf8.encode(notifyMsg), _ssdpAddress, _ssdpPort);
    } catch (_) {}
  }

  void _respondToMSearch(InternetAddress clientAddr, int clientPort) {
    if (_ssdpSocket == null) return;
    final responseMsg =
        'HTTP/1.1 200 OK\r\n'
        'CACHE-CONTROL: max-age=1800\r\n'
        'DATE: ${DateTime.now().toUtc().toIso8601String()}\r\n'
        'EXT:\r\n'
        'LOCATION: http://$_localIp:$_port/dlna/device.xml\r\n'
        'SERVER: NFylo/1.0 UPnP/1.0 DLNADOC/1.50\r\n'
        'ST: urn:schemas-upnp-org:device:MediaServer:1\r\n'
        'USN: uuid:nfylo-media-server-01::urn:schemas-upnp-org:device:MediaServer:1\r\n\r\n';

    try {
      _ssdpSocket!.send(utf8.encode(responseMsg), clientAddr, clientPort);
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  // HTTP Request Router & Video/Audio Partial Content Streaming
  // ---------------------------------------------------------------------------

  Future<void> _handleHttpRequest(HttpRequest request) async {
    final uriPath = Uri.decodeComponent(request.uri.path);

    // DLNA Device Description XML
    if (uriPath == '/dlna/device.xml') {
      final xml = '''<?xml version="1.0"?>
<root xmlns="urn:schemas-upnp-org:device-1-0">
  <specVersion><major>1</major><minor>0</minor></specVersion>
  <device>
    <deviceType>urn:schemas-upnp-org:device:MediaServer:1</deviceType>
    <friendlyName>NFylo Media Server ($_localIp)</friendlyName>
    <manufacturer>NFylo Pro</manufacturer>
    <modelName>NFylo DLNA 1.0</modelName>
    <UDN>uuid:nfylo-media-server-01</UDN>
  </device>
</root>''';
      request.response
        ..headers.contentType = ContentType('text', 'xml', charset: 'utf-8')
        ..write(xml);
      await request.response.close();
      return;
    }

    // API: Upload file from PC
    if (request.method == 'POST' && uriPath == '/api/upload') {
      await _handleWebUpload(request);
      return;
    }

    // API: Delete file from PC
    if (request.method == 'POST' && uriPath == '/api/delete') {
      await _handleWebDelete(request);
      return;
    }

    // API: List directory files as JSON
    if (uriPath == '/api/files') {
      final targetPath = request.uri.queryParameters['path'] ?? _rootPath;
      await _handleFileListJson(request, targetPath);
      return;
    }

    // Static Stream File Request
    if (uriPath.startsWith('/stream/')) {
      final subPath = uriPath.replaceFirst('/stream/', '');
      final fullPath = p.normalize(p.join(_rootPath, subPath));
      await _streamFileWithRange(request, fullPath);
      return;
    }

    // Web Portal UI (HTML5 App)
    if (uriPath == '/' || uriPath == '/index.html') {
      request.response
        ..headers.contentType = ContentType.html
        ..write(_buildWebPortalHtml());
      await request.response.close();
      return;
    }

    request.response
      ..statusCode = HttpStatus.notFound
      ..write('Not Found');
    await request.response.close();
  }

  /// Streams files with HTTP 206 Partial Content (Range header support for seeking video).
  Future<void> _streamFileWithRange(HttpRequest request, String filePath) async {
    final file = File(filePath);
    if (!file.existsSync()) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }

    final totalSize = file.lengthSync();
    final mimeType = lookupMimeType(filePath) ?? 'application/octet-stream';
    final rangeHeader = request.headers.value('range');

    _activeClientsCount++;
    notifyListeners();

    try {
      if (rangeHeader != null && rangeHeader.startsWith('bytes=')) {
        // Parse "bytes=start-end"
        final rangeParts = rangeHeader.substring(6).split('-');
        final start = int.tryParse(rangeParts[0]) ?? 0;
        final end = rangeParts.length > 1 && rangeParts[1].isNotEmpty
            ? int.tryParse(rangeParts[1]) ?? (totalSize - 1)
            : (totalSize - 1);

        final contentLength = (end - start) + 1;

        request.response
          ..statusCode = HttpStatus.partialContent
          ..headers.set(HttpHeaders.acceptRangesHeader, 'bytes')
          ..headers.set(HttpHeaders.contentRangeHeader, 'bytes $start-$end/$totalSize')
          ..headers.set(HttpHeaders.contentLengthHeader, contentLength)
          ..headers.set(HttpHeaders.contentTypeHeader, mimeType);

        final stream = file.openRead(start, end + 1);
        await request.response.addStream(stream);
        _totalStreamedBytes += contentLength;
      } else {
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.set(HttpHeaders.acceptRangesHeader, 'bytes')
          ..headers.set(HttpHeaders.contentLengthHeader, totalSize)
          ..headers.set(HttpHeaders.contentTypeHeader, mimeType);

        await request.response.addStream(file.openRead());
        _totalStreamedBytes += totalSize;
      }
    } catch (_) {
    } finally {
      try {
        await request.response.close();
      } catch (_) {}
      _activeClientsCount = (_activeClientsCount - 1).clamp(0, 999);
      notifyListeners();
    }
  }

  Future<void> _handleFileListJson(HttpRequest request, String dirPath) async {
    final dir = Directory(dirPath);
    if (!dir.existsSync()) {
      request.response
        ..statusCode = HttpStatus.notFound
        ..write(json.encode({'error': 'Directory not found'}));
      await request.response.close();
      return;
    }

    final items = <Map<String, dynamic>>[];
    try {
      final list = dir.listSync();
      for (final entity in list) {
        final stat = entity.statSync();
        final isDir = stat.type == FileSystemEntityType.directory;
        final relPath = p.relative(entity.path, from: _rootPath);

        items.add({
          'name': p.basename(entity.path),
          'path': entity.path,
          'relPath': relPath,
          'isDir': isDir,
          'size': stat.size,
          'modified': stat.modified.toIso8601String(),
          'mime': isDir ? 'folder' : (lookupMimeType(entity.path) ?? 'application/octet-stream'),
        });
      }
    } catch (_) {}

    request.response
      ..headers.contentType = ContentType.json
      ..write(json.encode({
        'currentPath': dirPath,
        'rootPath': _rootPath,
        'items': items,
      }));
    await request.response.close();
  }

  Future<void> _handleWebUpload(HttpRequest request) async {
    try {
      final query = request.uri.queryParameters;
      final rawName = query['name'] ?? 'upload_${DateTime.now().millisecondsSinceEpoch}';
      final fileName = p.basename(rawName);
      final destDir = query['dest'] ?? p.join(_rootPath, 'Download');

      final targetFile = File(p.join(destDir, fileName));
      final sink = targetFile.openWrite();
      await request.cast<List<int>>().pipe(sink);

      request.response
        ..statusCode = HttpStatus.ok
        ..write(json.encode({'status': 'uploaded', 'file': fileName}));
      await request.response.close();
    } catch (e) {
      request.response
        ..statusCode = HttpStatus.internalServerError
        ..write(json.encode({'error': '$e'}));
      await request.response.close();
    }
  }

  Future<void> _handleWebDelete(HttpRequest request) async {
    try {
      final bodyStr = await utf8.decodeStream(request);
      final body = json.decode(bodyStr);
      final targetPath = body['path'] as String;

      if (FileSystemEntity.typeSync(targetPath) == FileSystemEntityType.file) {
        File(targetPath).deleteSync();
      } else if (FileSystemEntity.typeSync(targetPath) == FileSystemEntityType.directory) {
        Directory(targetPath).deleteSync(recursive: true);
      }

      request.response
        ..statusCode = HttpStatus.ok
        ..write(json.encode({'status': 'deleted'}));
      await request.response.close();
    } catch (e) {
      request.response
        ..statusCode = HttpStatus.internalServerError
        ..write(json.encode({'error': '$e'}));
      await request.response.close();
    }
  }

  // ---------------------------------------------------------------------------
  // Modern HTML5 Web App Portal (Manage on PC / TV Browser)
  // ---------------------------------------------------------------------------

  String _buildWebPortalHtml() {
    return '''<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>NFylo Pro — Media & PC Hub</title>
    <style>
        :root {
            --bg: #121214;
            --surface: #1e1e24;
            --surface-hover: #292932;
            --primary: #4f46e5;
            --primary-hover: #4338ca;
            --text: #f3f4f6;
            --text-dim: #9ca3af;
            --border: #2d2d38;
        }
        * { box-sizing: border-box; margin: 0; padding: 0; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; }
        body { background: var(--bg); color: var(--text); padding-bottom: 60px; }
        header { background: var(--surface); border-bottom: 1px solid var(--border); padding: 16px 24px; display: flex; justify-content: space-between; align-items: center; position: sticky; top: 0; z-index: 100; }
        .logo { font-size: 20px; font-weight: 700; color: #fff; display: flex; align-items: center; gap: 10px; }
        .logo span { background: var(--primary); color: #fff; font-size: 11px; padding: 2px 8px; border-radius: 6px; }
        .container { max-width: 1100px; margin: 24px auto; padding: 0 16px; }
        .breadcrumbs { display: flex; gap: 8px; align-items: center; font-size: 14px; margin-bottom: 20px; overflow-x: auto; padding: 8px 0; }
        .breadcrumbs span { cursor: pointer; color: var(--primary); }
        .breadcrumbs span:hover { text-decoration: underline; }
        .grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(200px, 1fr)); gap: 16px; }
        .card { background: var(--surface); border: 1px solid var(--border); border-radius: 12px; padding: 14px; cursor: pointer; transition: all 0.2s; position: relative; }
        .card:hover { background: var(--surface-hover); transform: translateY(-2px); }
        .card-icon { font-size: 32px; margin-bottom: 10px; }
        .card-title { font-size: 13.5px; font-weight: 600; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; margin-bottom: 4px; }
        .card-meta { font-size: 11.5px; color: var(--text-dim); }
        .upload-zone { border: 2px dashed var(--border); border-radius: 14px; padding: 24px; text-align: center; margin-bottom: 24px; cursor: pointer; }
        .upload-zone:hover { border-color: var(--primary); }
        .player-modal { display: none; position: fixed; inset: 0; background: rgba(0,0,0,0.85); z-index: 200; align-items: center; justify-content: center; padding: 20px; }
        .player-modal.active { display: flex; }
        .player-box { max-width: 800px; width: 100%; background: var(--surface); border-radius: 16px; overflow: hidden; border: 1px solid var(--border); }
        video, audio { width: 100%; outline: none; }
    </style>
</head>
<body>
    <header>
        <div class="logo">⚡ NFylo Pro <span>Media &amp; PC Hub</span></div>
        <div id="statusBadge" style="font-size: 12px; color: var(--text-dim);">Connected to Mobile</div>
    </header>

    <div class="container">
        <div class="upload-zone" onclick="document.getElementById('fileInput').click()">
            <input type="file" id="fileInput" style="display: none;" onchange="uploadFile(this.files[0])">
            <div style="font-size: 16px; font-weight: 600; margin-bottom: 4px;">Drag &amp; Drop or Click to Upload File to Phone</div>
            <div style="font-size: 12px; color: var(--text-dim);">Files are saved directly to your phone's storage</div>
        </div>

        <div class="breadcrumbs" id="breadBox">Loading folder...</div>
        <div class="grid" id="fileGrid"></div>
    </div>

    <div class="player-modal" id="playerModal" onclick="closePlayer(event)">
        <div class="player-box" onclick="event.stopPropagation()">
            <div style="padding: 12px 16px; display: flex; justify-content: space-between; border-bottom: 1px solid var(--border);">
                <span id="playerTitle" style="font-weight: 600; font-size: 14px;">Streaming Media</span>
                <button onclick="closePlayer()" style="background: none; border: none; color: #fff; font-size: 18px; cursor: pointer;">&times;</button>
            </div>
            <div id="playerContainer" style="padding: 16px; text-align: center;"></div>
        </div>
    </div>

    <script>
        let currentPath = '';

        async function loadPath(path) {
            const res = await fetch('/api/files?path=' + encodeURIComponent(path || ''));
            const data = await res.json();
            currentPath = data.currentPath;

            // Render breadcrumbs
            const parts = currentPath.split('/');
            let html = '';
            let acc = '';
            parts.forEach((p, idx) => {
                if (!p && idx === 0) { acc = '/'; html += '<span onclick="loadPath(\\'/\\')">Home</span> / '; }
                else if (p) {
                    acc += (acc.endsWith('/') ? '' : '/') + p;
                    const pathTarget = acc;
                    html += '<span onclick="loadPath(\\'' + pathTarget + '\\')">' + p + '</span> / ';
                }
            });
            document.getElementById('breadBox').innerHTML = html;

            // Render Grid
            const grid = document.getElementById('fileGrid');
            grid.innerHTML = '';
            data.items.forEach(item => {
                const el = document.createElement('div');
                el.className = 'card';
                let icon = '📄';
                if (item.isDir) icon = '📁';
                else if (item.mime.includes('video')) icon = '🎬';
                else if (item.mime.includes('audio')) icon = '🎵';
                else if (item.mime.includes('image')) icon = '🖼️';

                el.innerHTML = '<div class="card-icon">' + icon + '</div>' +
                    '<div class="card-title">' + item.name + '</div>' +
                    '<div class="card-meta">' + (item.isDir ? 'Folder' : formatBytes(item.size)) + '</div>';

                el.onclick = () => {
                    if (item.isDir) {
                        loadPath(item.path);
                    } else if (item.mime.includes('video')) {
                        openVideo(item.name, '/stream/' + encodeURIComponent(item.relPath));
                    } else if (item.mime.includes('audio')) {
                        openAudio(item.name, '/stream/' + encodeURIComponent(item.relPath));
                    } else {
                        window.open('/stream/' + encodeURIComponent(item.relPath), '_blank');
                    }
                };
                grid.appendChild(el);
            });
        }

        function formatBytes(bytes) {
            if (bytes === 0) return '0 B';
            const k = 1024, dm = 1;
            const sizes = ['B', 'KB', 'MB', 'GB', 'TB'];
            const i = Math.floor(Math.log(bytes) / Math.log(k));
            return parseFloat((bytes / Math.pow(k, i)).toFixed(dm)) + ' ' + sizes[i];
        }

        function openVideo(title, src) {
            document.getElementById('playerTitle').innerText = title;
            document.getElementById('playerContainer').innerHTML = '<video controls autoplay src="' + src + '"></video>';
            document.getElementById('playerModal').classList.add('active');
        }

        function openAudio(title, src) {
            document.getElementById('playerTitle').innerText = title;
            document.getElementById('playerContainer').innerHTML = '<audio controls autoplay src="' + src + '"></audio>';
            document.getElementById('playerModal').classList.add('active');
        }

        function closePlayer() {
            document.getElementById('playerModal').classList.remove('active');
            document.getElementById('playerContainer').innerHTML = '';
        }

        async function uploadFile(file) {
            if (!file) return;
            const dest = currentPath;
            const res = await fetch('/api/upload?name=' + encodeURIComponent(file.name) + '&dest=' + encodeURIComponent(dest), {
                method: 'POST',
                body: file
            });
            if (res.ok) {
                alert('Uploaded successfully!');
                loadPath(currentPath);
            }
        }

        loadPath('');
    </script>
</body>
</html>''';
  }
}
