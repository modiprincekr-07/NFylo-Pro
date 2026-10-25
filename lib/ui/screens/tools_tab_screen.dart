import 'package:flutter/material.dart';
import '../../core/icon_fonts/broken_icons.dart';
import '../widgets/nfile_icon.dart';
import 'storage_analyzer/storage_analyzer_screen.dart';
import 'storage_analyzer/app_manager_screen.dart';
import 'storage_cleanup/storage_cleanup_screen.dart';
import 'tools/file_encryptor_screen.dart';
import 'tools/checksum_screen.dart';
import 'tools/file_splitter_screen.dart';
import 'tools/apk_inspector_screen.dart';
import 'tools/sqlite_viewer_screen.dart';
import 'tools/device_info_screen.dart';
import 'tools/image_converter_screen.dart';
import 'tools/exif_remover_screen.dart';
import 'tools/image_upscaler_screen.dart';
import 'tools/pdf_toolkit_screen.dart';
import 'tools/document_scanner_screen.dart';
import 'tools/media_studio_screen.dart';
import 'tools/voice_recorder_screen.dart';
import 'tools/smb_ftp_client_screen.dart';
import 'tools/nearby_transfer_screen.dart';
import 'tools/media_server_screen.dart';
import 'tools/cloud_storage_screen.dart';
import 'tools/network_speed_test_screen.dart';
import 'tools/ai_lab_screen.dart';
import 'tools/ai_doc_chat_screen.dart';
import 'tools/ai_whisper_screen.dart';
import 'tools/ai_tts_screen.dart';
import 'tools/ai_image_cutout_screen.dart';
import 'tools/ai_image_restoration_screen.dart';
import 'tools/malware_scanner_screen.dart';
import 'tools/smart_cleanup_screen.dart';
import 'ftp_server_screen.dart';
import 'vault_lock_screen.dart';
import 'recycle_bin_screen.dart';
import 'web_sharing_screen.dart';
import 'more_settings_screen.dart';
import 'about_screen.dart';

class ToolsTabScreen extends StatelessWidget {
  const ToolsTabScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return SafeArea(
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Tools & Utilities',
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.5,
                    ),
                  ),
                  IconButton(
                    icon: const NfileIcon(Broken.info_circle, size: 22),
                    tooltip: 'About',
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => AboutScreen()),
                    ),
                  ),
                ],
              ),
            ),

            // AI Lab & Downloadable Plugins Banner (Stage 10)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: isDark
                        ? [const Color(0xFF1E2640), const Color(0xFF281E40)]
                        : [const Color(0xFFE8F0FE), const Color(0xFFF3E5F5)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: theme.colorScheme.primary.withOpacity(0.2),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: theme.colorScheme.primary.withOpacity(0.08),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(22),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const AiLabScreen()),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [theme.colorScheme.primary, Colors.deepPurpleAccent],
                              ),
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: const Icon(Broken.cpu, size: 30, color: Colors.white),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      'On-Device AI Lab',
                                      style: theme.textTheme.titleMedium?.copyWith(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.green.withOpacity(0.18),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: const Text(
                                        '6 Plugins',
                                        style: TextStyle(
                                          color: Colors.green,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Offline GGUF, Whisper, FastSAM, GFPGAN & Malware models',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.hintColor,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(Broken.arrow_right_3, size: 20, color: theme.colorScheme.primary),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // AI Lab & Modular Plugins Quick Suite
            _buildSectionHeader(theme, 'On-Device AI Lab & Plugins'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: _ToolCard(
                      icon: Broken.document_text,
                      label: 'Local Doc\nChat (GGUF)',
                      subtitle: 'Qwen2.5 offline PDF Q&A',
                      color: isDark ? Colors.purpleAccent : const Color(0xFF7B1FA2),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const AiDocChatScreen(),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _ToolCard(
                      icon: Broken.microphone_2,
                      label: 'Whisper\nTranscriber',
                      subtitle: 'Speech-to-text & SRT export',
                      color: isDark ? Colors.cyanAccent : const Color(0xFF0097A7),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const AiWhisperScreen(),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: _ToolCard(
                      icon: Broken.music_filter,
                      label: 'Voice Generator\n(Neural TTS)',
                      subtitle: '5 personas & modulation',
                      color: isDark ? Colors.amberAccent : const Color(0xFFE65100),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const AiTtsScreen(),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _ToolCard(
                      icon: Broken.scissor,
                      label: 'AI Image Cutout\n(FastSAM)',
                      subtitle: 'Auto remove background',
                      color: isDark ? Colors.pinkAccent : const Color(0xFFC2185B),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const AiImageCutoutScreen(),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: _ToolCard(
                      icon: Broken.magicpen,
                      label: 'AI Photo\nRestoration',
                      subtitle: 'Real-ESRGAN & GFPGAN',
                      color: isDark ? Colors.tealAccent : const Color(0xFF00796B),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const AiImageRestorationScreen(),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _ToolCard(
                      icon: Broken.shield_tick,
                      label: 'Offline Malware\nScanner',
                      subtitle: 'YARA & APK heuristics',
                      color: isDark ? Colors.redAccent : const Color(0xFFD32F2F),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const MalwareScannerScreen(),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // 1. Storage Management
            _buildSectionHeader(theme, 'Storage Management'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: _ToolCard(
                      icon: Broken.chart,
                      label: 'Storage\nAnalyzer',
                      subtitle: 'Visual Space Map & stats',
                      color: isDark ? Colors.blueAccent : const Color(0xFF1976D2),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const StorageAnalyzerScreen(),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _ToolCard(
                      icon: Broken.brush_2,
                      label: 'Storage\nCleanup',
                      subtitle: 'Duplicates & large files',
                      color: isDark ? Colors.greenAccent : const Color(0xFF2E7D32),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const StorageCleanupScreen(),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: isDark
                        ? [const Color(0xFF1E293B), const Color(0xFF0F172A)]
                        : [const Color(0xFFFFF7ED), const Color(0xFFFFEDD5)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: (isDark ? Colors.amberAccent : const Color(0xFFEA580C)).withOpacity(0.25),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.04),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Material(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(20),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const SmartCleanupScreen(),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: (isDark ? Colors.amberAccent : const Color(0xFFEA580C)).withOpacity(0.15),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Icon(
                              Broken.broom,
                              color: isDark ? Colors.amberAccent : const Color(0xFFEA580C),
                              size: 26,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Text(
                                      'Smart Cleanup',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15,
                                        letterSpacing: -0.2,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.deepOrangeAccent.withOpacity(0.2),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: const Text(
                                        'SWIPE',
                                        style: TextStyle(
                                          fontSize: 9.5,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.deepOrangeAccent,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  'Tinder-style swipe to keep or delete screenshots & media',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color: theme.textTheme.bodySmall?.color?.withOpacity(0.65),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            Icons.arrow_forward_ios_rounded,
                            size: 15,
                            color: theme.colorScheme.onSurface.withOpacity(0.35),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // 2. Built-in Image Suite & Privacy (Stage 7)
            _buildSectionHeader(theme, 'Built-in Image Suite & Privacy'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: _ToolCard(
                      icon: Broken.gallery_edit,
                      label: 'Format &\nCompressor',
                      subtitle: 'JPG, PNG, WEBP, ICO resize',
                      color: isDark ? Colors.pinkAccent : const Color(0xFFC2185B),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const ImageConverterScreen(),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _ToolCard(
                      icon: Broken.shield_slash,
                      label: 'EXIF Remover\n(Privacy)',
                      subtitle: 'Strip GPS & camera metadata',
                      color: isDark ? Colors.redAccent : const Color(0xFFD32F2F),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const ExifRemoverScreen(),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _ToolCard(
                icon: Broken.maximize_4,
                label: 'Image Upscaler (2x / 4x)',
                subtitle: 'High-res bicubic & cubic interpolation without blur',
                color: isDark ? Colors.tealAccent : const Color(0xFF00796B),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const ImageUpscalerScreen(),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // 3. PDF, Document Scanner & Media Studio (Stage 8)
            _buildSectionHeader(theme, 'PDF, Document Scanner & Media Studio'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: _ToolCard(
                      icon: Broken.document_text,
                      label: 'PDF Toolkit\n& EPUB',
                      subtitle: 'Merge, split, watermark, EPUB',
                      color: isDark ? Colors.redAccent : const Color(0xFFD32F2F),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const PdfToolkitScreen(),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _ToolCard(
                      icon: Broken.scanner,
                      label: 'Document\nScanner',
                      subtitle: 'Camera scan to clean PDF',
                      color: isDark ? Colors.blueAccent : const Color(0xFF1565C0),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const DocumentScannerScreen(),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: _ToolCard(
                      icon: Broken.video_play,
                      label: 'Media Studio\n(FFmpeg)',
                      subtitle: 'Compress, trim, extract MP3',
                      color: isDark ? Colors.deepPurpleAccent : const Color(0xFF512DA8),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const MediaStudioScreen(),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _ToolCard(
                      icon: Broken.microphone_2,
                      label: 'Voice\nRecorder',
                      subtitle: 'Record & share voice notes',
                      color: isDark ? Colors.amberAccent : const Color(0xFFF57C00),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const VoiceRecorderScreen(),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // 4. Security & Encryption
            _buildSectionHeader(theme, 'Security & Encryption'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: _ToolCard(
                      icon: Broken.shield_tick,
                      label: 'Private\nVault',
                      subtitle: 'AES-256 + Biometrics',
                      color: isDark ? Colors.purpleAccent : Colors.purple,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const VaultLockScreen(),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _ToolCard(
                      icon: Broken.lock,
                      label: 'File\nEncryptor',
                      subtitle: 'AES-256 with password',
                      color: isDark ? Colors.indigoAccent : const Color(0xFF3F51B5),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const FileEncryptorScreen(),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // 4. File Utilities
            _buildSectionHeader(theme, 'File Utilities'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: _ToolCard(
                      icon: Broken.security_safe,
                      label: 'Checksum\n& Verify',
                      subtitle: 'MD5, SHA-1, SHA-256',
                      color: isDark ? Colors.amberAccent : const Color(0xFFE65100),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const ChecksumScreen(),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _ToolCard(
                      icon: Broken.scissor,
                      label: 'Split &\nJoin Chunks',
                      subtitle: 'Divide & merge files',
                      color: isDark ? Colors.tealAccent : const Color(0xFF00796B),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const FileSplitterScreen(),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // 5. Developer & System Utilities
            _buildSectionHeader(theme, 'Developer & System Utilities'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: _ToolCard(
                      icon: Broken.code,
                      label: 'APK Inspector\n& Extractor',
                      subtitle: 'Manifest, permissions, splits',
                      color: isDark ? Colors.orangeAccent : const Color(0xFFEF6C00),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const ApkInspectorScreen(),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _ToolCard(
                      icon: Broken.data,
                      label: 'SQLite\nViewer',
                      subtitle: 'Browse tables & run queries',
                      color: isDark ? Colors.cyanAccent : const Color(0xFF00838F),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const SqliteViewerScreen(),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: _ToolCard(
                      icon: Broken.cpu,
                      label: 'Device\nInfo',
                      subtitle: 'CPU, screen, RAM & codecs',
                      color: isDark ? Colors.deepPurpleAccent : const Color(0xFF5E35B1),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const DeviceInfoScreen(),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _ToolCard(
                      icon: Broken.mobile,
                      label: 'App\nManager',
                      subtitle: 'Installed apps & backups',
                      color: isDark ? Colors.amberAccent : const Color(0xFFF57F17),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const AppManagerScreen(),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // 6. Network, Cloud & Local Transfer (Stage 9)
            _buildSectionHeader(theme, 'Network, Cloud & Local Transfer'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: _ToolCard(
                      icon: Broken.routing_2,
                      label: 'SMB & FTP\nClient',
                      subtitle: 'Samba, FTP, SFTP & LAN',
                      color: isDark ? Colors.blueAccent : const Color(0xFF1976D2),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const SmbFtpClientScreen(),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _ToolCard(
                      icon: Broken.radar_1,
                      label: 'Nearby\nTransfer',
                      subtitle: 'Direct Wi-Fi P2P offline',
                      color: isDark ? Colors.cyanAccent : const Color(0xFF0097A7),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const NearbyTransferScreen(),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: _ToolCard(
                      icon: Broken.screenmirroring,
                      label: 'Media Server\n& PC Web',
                      subtitle: 'DLNA stream & PC browser',
                      color: isDark ? Colors.deepPurpleAccent : const Color(0xFF673AB7),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const MediaServerScreen(),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _ToolCard(
                      icon: Broken.folder_cloud,
                      label: 'Google\nDrive',
                      subtitle: 'Cloud files & downloads',
                      color: isDark ? Colors.amberAccent : const Color(0xFFF57F17),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const CloudStorageScreen(),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _ToolCard(
                icon: Broken.speedometer,
                label: 'Network Speed Test',
                subtitle: 'Ping, jitter, download & upload bandwidth',
                color: isDark ? Colors.tealAccent : const Color(0xFF00897B),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const NetworkSpeedTestScreen(),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // 7. Quick System Tools
            _buildSectionHeader(theme, 'Quick System Tools'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: _ToolGridCard(
                      icon: Broken.cloud_connection,
                      label: 'FTP\nServer',
                      color: isDark ? Colors.tealAccent : const Color(0xFF00796B),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => FtpServerScreen(),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _ToolGridCard(
                      icon: Broken.global,
                      label: 'Web\nSharing',
                      color: isDark ? Colors.cyanAccent : Colors.cyan,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const WebSharingScreen(),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _ToolGridCard(
                      icon: Broken.trash,
                      label: 'Recycle\nBin',
                      color: isDark ? Colors.redAccent : const Color(0xFFC62828),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const RecycleBinScreen(),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _ToolGridCard(
                      icon: Broken.setting_2,
                      label: 'More\nSettings',
                      color: isDark ? Colors.blueGrey.shade300 : Colors.blueGrey,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const MoreSettingsScreen(),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 36),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(ThemeData theme, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 16, 10),
      child: Text(
        title,
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.bold,
          color: theme.colorScheme.primary,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

class _ToolCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _ToolCard({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? theme.colorScheme.surface : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.dividerColor.withOpacity(0.08)),
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
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, color: color, size: 24),
                ),
                const SizedBox(height: 14),
                Text(
                  label,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14.5,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 11,
                    color: theme.textTheme.bodySmall?.color?.withOpacity(0.6),
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ToolGridCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ToolGridCard({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? theme.colorScheme.surface : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: theme.dividerColor.withOpacity(0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: color, size: 22),
                ),
                const SizedBox(height: 10),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 11.5,
                    height: 1.15,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
