import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

class DriveItem {
  final String id;
  final String name;
  final String mimeType;
  final int size;
  final DateTime? modifiedTime;
  final bool isFolder;
  final String? thumbnailLink;
  final String? webViewLink;

  DriveItem({
    required this.id,
    required this.name,
    required this.mimeType,
    required this.size,
    this.modifiedTime,
    required this.isFolder,
    this.thumbnailLink,
    this.webViewLink,
  });
}

class GoogleAuthClient extends http.BaseClient {
  final Map<String, String> _headers;
  final http.Client _client = http.Client();

  GoogleAuthClient(this._headers);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    return _client.send(request..headers.addAll(_headers));
  }
}

class CloudDriveService extends ChangeNotifier {
  static final CloudDriveService instance = CloudDriveService._();
  CloudDriveService._();

  static const String _defaultCloudDir =
      '/storage/emulated/0/Download/NFylo_Cloud';

  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: [
      drive.DriveApi.driveReadonlyScope,
    ],
  );

  GoogleSignInAccount? _currentUser;
  drive.DriveApi? _driveApi;

  GoogleSignInAccount? get currentUser => _currentUser;
  bool get isSignedIn => _currentUser != null;

  static Directory _getOutputDir() {
    final dir = Directory(_defaultCloudDir);
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return dir;
  }

  /// Attempts silent sign in or checks active account.
  Future<void> init() async {
    _googleSignIn.onCurrentUserChanged.listen((account) async {
      _currentUser = account;
      if (account != null) {
        final authHeaders = await account.authHeaders;
        final authClient = GoogleAuthClient(authHeaders);
        _driveApi = drive.DriveApi(authClient);
      } else {
        _driveApi = null;
      }
      notifyListeners();
    });

    try {
      await _googleSignIn.signInSilently();
    } catch (_) {}
  }

  /// Triggers Google Account OAuth Sign In dialog.
  Future<bool> signIn() async {
    try {
      final account = await _googleSignIn.signIn();
      if (account != null) {
        final authHeaders = await account.authHeaders;
        final authClient = GoogleAuthClient(authHeaders);
        _driveApi = drive.DriveApi(authClient);
        _currentUser = account;
        notifyListeners();
        return true;
      }
    } catch (e) {
      debugPrint('Google Sign In error: $e');
      rethrow;
    }
    return false;
  }

  /// Signs out of Google Drive.
  Future<void> signOut() async {
    await _googleSignIn.signOut();
    _currentUser = null;
    _driveApi = null;
    notifyListeners();
  }

  /// Lists files inside a specific Google Drive folder or root.
  Future<List<DriveItem>> listFiles({
    String folderId = 'root',
    String? searchFilter,
  }) async {
    if (_driveApi == null) {
      throw Exception('Not signed in to Google Drive.');
    }

    String query = "'$folderId' in parents and trashed = false";
    if (searchFilter != null && searchFilter.trim().isNotEmpty) {
      final escaped = searchFilter.replaceAll("'", "\\'");
      query += " and name contains '$escaped'";
    }

    final fileList = await _driveApi!.files.list(
      q: query,
      $fields: 'files(id, name, mimeType, size, modifiedTime, thumbnailLink, webViewLink)',
      orderBy: 'folder, name',
      pageSize: 100,
    );

    final items = <DriveItem>[];
    for (final f in fileList.files ?? []) {
      if (f.id == null || f.name == null) continue;

      final isFolder = f.mimeType == 'application/vnd.google-apps.folder';
      final size = int.tryParse(f.size ?? '0') ?? 0;

      items.add(DriveItem(
        id: f.id!,
        name: f.name!,
        mimeType: f.mimeType ?? 'application/octet-stream',
        size: size,
        modifiedTime: f.modifiedTime,
        isFolder: isFolder,
        thumbnailLink: f.thumbnailLink,
        webViewLink: f.webViewLink,
      ));
    }

    return items;
  }

  /// Downloads a file from Google Drive to local storage.
  Future<String> downloadFile({
    required String fileId,
    required String fileName,
    required void Function(double progress) onProgress,
  }) async {
    if (_driveApi == null) {
      throw Exception('Not signed in to Google Drive.');
    }

    final outDir = _getOutputDir();
    final outPath = p.join(outDir.path, fileName);
    final targetFile = File(outPath);

    final media = await _driveApi!.files.get(
      fileId,
      downloadOptions: drive.DownloadOptions.fullMedia,
    ) as drive.Media;

    final sink = targetFile.openWrite();
    int received = 0;
    final total = media.length ?? 0;

    await for (final chunk in media.stream) {
      sink.add(chunk);
      received += chunk.length;
      if (total > 0) {
        onProgress((received / total).clamp(0.0, 1.0));
      }
    }

    await sink.flush();
    await sink.close();

    return outPath;
  }
}
