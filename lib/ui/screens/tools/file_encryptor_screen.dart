import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import '../../../core/icon_fonts/broken_icons.dart';
import '../../../core/utils.dart';
import '../../../providers/file_manager_provider.dart';
import '../../../services/encryption/aes_256_service.dart';
import '../../../services/folder_share_service.dart';
import '../internal_file_picker_screen.dart';

class FileEncryptorScreen extends StatefulWidget {
  final String? initialFilePath;
  const FileEncryptorScreen({super.key, this.initialFilePath});

  @override
  State<FileEncryptorScreen> createState() => _FileEncryptorScreenState();
}

class _FileEncryptorScreenState extends State<FileEncryptorScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Encrypt state
  String? _encryptFilePath;
  final TextEditingController _encryptPasswordController = TextEditingController();
  bool _obscureEncryptPassword = true;
  bool _deleteOriginal = false;
  bool _isEncrypting = false;
  double _encryptProgress = 0.0;
  String? _encryptedResultPath;

  // Decrypt state
  String? _decryptFilePath;
  final TextEditingController _decryptPasswordController = TextEditingController();
  bool _obscureDecryptPassword = true;
  bool _isDecrypting = false;
  double _decryptProgress = 0.0;
  String? _decryptedResultPath;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);

    if (widget.initialFilePath != null) {
      if (widget.initialFilePath!.endsWith('.nenc') ||
          widget.initialFilePath!.endsWith('.enc')) {
        _decryptFilePath = widget.initialFilePath;
        _tabController.index = 1;
      } else {
        _encryptFilePath = widget.initialFilePath;
      }
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _encryptPasswordController.dispose();
    _decryptPasswordController.dispose();
    super.dispose();
  }

  Future<void> _pickEncryptFile() async {
    final rootPath = context.read<FileManagerProvider>().rootPath;
    final picked = await InternalFilePickerScreen.show(
      context,
      rootPath: rootPath,
      pickDirectory: false,
    );
    if (picked != null && picked.isNotEmpty) {
      setState(() {
        _encryptFilePath = picked.first;
        _encryptedResultPath = null;
      });
    }
  }

  Future<void> _pickDecryptFile() async {
    final rootPath = context.read<FileManagerProvider>().rootPath;
    final picked = await InternalFilePickerScreen.show(
      context,
      rootPath: rootPath,
      pickDirectory: false,
    );
    if (picked != null && picked.isNotEmpty) {
      setState(() {
        _decryptFilePath = picked.first;
        _decryptedResultPath = null;
      });
    }
  }

  Future<void> _startEncryption() async {
    if (_encryptFilePath == null) {
      _showToast('Please select a file to encrypt');
      return;
    }
    final password = _encryptPasswordController.text;
    if (password.length < 4) {
      _showToast('Password must be at least 4 characters long');
      return;
    }

    final inputFile = File(_encryptFilePath!);
    if (!inputFile.existsSync()) {
      _showToast('Selected file no longer exists');
      return;
    }

    final outPath = '${_encryptFilePath!}.nenc';
    final outputFile = File(outPath);

    setState(() {
      _isEncrypting = true;
      _encryptProgress = 0.0;
      _encryptedResultPath = null;
    });

    try {
      await Aes256FileEncryptor.encryptFile(
        inputFile: inputFile,
        outputFile: outputFile,
        password: password,
        onProgress: (p) {
          if (mounted) setState(() => _encryptProgress = p);
        },
      );

      if (_deleteOriginal) {
        await inputFile.delete();
      }

      context.read<FileManagerProvider>().updateStorageSpace();

      if (mounted) {
        setState(() {
          _isEncrypting = false;
          _encryptedResultPath = outPath;
        });
        _showToast('File encrypted with AES-256 successfully!');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isEncrypting = false);
        _showToast('Encryption failed: $e');
      }
    }
  }

  Future<void> _startDecryption() async {
    if (_decryptFilePath == null) {
      _showToast('Please select an encrypted file (.nenc / .enc)');
      return;
    }
    final password = _decryptPasswordController.text;
    if (password.isEmpty) {
      _showToast('Please enter the decryption password');
      return;
    }

    final inputFile = File(_decryptFilePath!);
    if (!inputFile.existsSync()) {
      _showToast('Selected file no longer exists');
      return;
    }

    final outDir = p.dirname(_decryptFilePath!);

    setState(() {
      _isDecrypting = true;
      _decryptProgress = 0.0;
      _decryptedResultPath = null;
    });

    try {
      final decryptedFile = await Aes256FileEncryptor.decryptFile(
        inputFile: inputFile,
        outputDirectory: outDir,
        password: password,
        onProgress: (p) {
          if (mounted) setState(() => _decryptProgress = p);
        },
      );

      context.read<FileManagerProvider>().updateStorageSpace();

      if (mounted) {
        setState(() {
          _isDecrypting = false;
          _decryptedResultPath = decryptedFile.path;
        });
        _showToast('File decrypted successfully!');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isDecrypting = false);
        _showToast('Decryption failed: Check password or file integrity');
      }
    }
  }

  void _showToast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('File Encryptor (AES-256)'),
        elevation: 0,
        backgroundColor: theme.colorScheme.surface,
        bottom: TabBar(
          controller: _tabController,
          labelColor: theme.colorScheme.primary,
          unselectedLabelColor: theme.textTheme.bodySmall?.color?.withOpacity(0.6),
          indicatorColor: theme.colorScheme.primary,
          tabs: const [
            Tab(icon: Icon(Broken.lock), text: 'Encrypt File'),
            Tab(icon: Icon(Broken.unlock), text: 'Decrypt File'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildEncryptTab(theme),
          _buildDecryptTab(theme),
        ],
      ),
    );
  }

  Widget _buildEncryptTab(ThemeData theme) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // File Picker Header Card
          _buildFileSelectCard(
            theme: theme,
            title: 'File to Encrypt',
            filePath: _encryptFilePath,
            onPick: _pickEncryptFile,
            accentColor: theme.colorScheme.primary,
            icon: Broken.document_upload,
          ),
          const SizedBox(height: 20),

          // Password Field
          Text(
            'Encryption Password',
            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _encryptPasswordController,
            obscureText: _obscureEncryptPassword,
            decoration: InputDecoration(
              hintText: 'Enter secret password...',
              prefixIcon: const Icon(Broken.key, size: 20),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureEncryptPassword ? Icons.visibility_off : Icons.visibility,
                  size: 20,
                ),
                onPressed: () {
                  setState(() => _obscureEncryptPassword = !_obscureEncryptPassword);
                },
              ),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
              filled: true,
              fillColor: theme.colorScheme.surfaceVariant.withOpacity(0.3),
            ),
          ),
          const SizedBox(height: 14),

          // Delete Original Switch
          SwitchListTile(
            value: _deleteOriginal,
            onChanged: (val) => setState(() => _deleteOriginal = val),
            title: const Text('Delete original unencrypted file', style: TextStyle(fontSize: 13.5)),
            subtitle: const Text('Remove plaintext file after AES-256 encryption', style: TextStyle(fontSize: 11)),
            contentPadding: EdgeInsets.zero,
          ),
          const SizedBox(height: 16),

          // Encryption Progress
          if (_isEncrypting) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: _encryptProgress > 0 ? _encryptProgress : null,
                minHeight: 8,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Encrypting... ${(_encryptProgress * 100).toInt()}%',
              style: TextStyle(fontSize: 12, color: theme.colorScheme.primary),
            ),
            const SizedBox(height: 16),
          ],

          // Action Button
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton.icon(
              onPressed: _isEncrypting ? null : _startEncryption,
              icon: const Icon(Broken.lock, size: 20),
              label: const Text('Encrypt with AES-256', style: TextStyle(fontWeight: FontWeight.bold)),
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
            ),
          ),

          // Success result card
          if (_encryptedResultPath != null) ...[
            const SizedBox(height: 24),
            _buildResultCard(
              theme: theme,
              title: 'File Encrypted Successfully!',
              filePath: _encryptedResultPath!,
              onShare: () => FolderShareService.sharePaths(context, [_encryptedResultPath!]),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDecryptTab(ThemeData theme) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // File Picker Header Card
          _buildFileSelectCard(
            theme: theme,
            title: 'Encrypted File (.nenc / .enc)',
            filePath: _decryptFilePath,
            onPick: _pickDecryptFile,
            accentColor: const Color(0xFF10B981),
            icon: Broken.lock,
          ),
          const SizedBox(height: 20),

          // Password Field
          Text(
            'Decryption Password',
            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _decryptPasswordController,
            obscureText: _obscureDecryptPassword,
            decoration: InputDecoration(
              hintText: 'Enter file password...',
              prefixIcon: const Icon(Broken.key, size: 20),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureDecryptPassword ? Icons.visibility_off : Icons.visibility,
                  size: 20,
                ),
                onPressed: () {
                  setState(() => _obscureDecryptPassword = !_obscureDecryptPassword);
                },
              ),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
              filled: true,
              fillColor: theme.colorScheme.surfaceVariant.withOpacity(0.3),
            ),
          ),
          const SizedBox(height: 24),

          // Decryption Progress
          if (_isDecrypting) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: _decryptProgress > 0 ? _decryptProgress : null,
                minHeight: 8,
                color: const Color(0xFF10B981),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Decrypting... ${(_decryptProgress * 100).toInt()}%',
              style: const TextStyle(fontSize: 12, color: Color(0xFF10B981)),
            ),
            const SizedBox(height: 16),
          ],

          // Action Button
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton.icon(
              onPressed: _isDecrypting ? null : _startDecryption,
              icon: const Icon(Broken.unlock, size: 20),
              label: const Text('Decrypt File', style: TextStyle(fontWeight: FontWeight.bold)),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF10B981),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
            ),
          ),

          // Success result card
          if (_decryptedResultPath != null) ...[
            const SizedBox(height: 24),
            _buildResultCard(
              theme: theme,
              title: 'File Decrypted Successfully!',
              filePath: _decryptedResultPath!,
              onOpen: () => context.read<FileManagerProvider>().openFile(context, _decryptedResultPath!),
              onShare: () => FolderShareService.sharePaths(context, [_decryptedResultPath!]),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFileSelectCard({
    required ThemeData theme,
    required String title,
    required String? filePath,
    required VoidCallback onPick,
    required Color accentColor,
    required IconData icon,
  }) {
    final hasFile = filePath != null && File(filePath).existsSync();
    final fileName = hasFile ? p.basename(filePath) : 'No file chosen';
    final fileSize = hasFile ? FileUtils.formatBytes(File(filePath).lengthSync(), 1) : '';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.dividerColor.withOpacity(0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: theme.textTheme.bodySmall?.color?.withOpacity(0.6),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: accentColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: accentColor, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      fileName,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (hasFile) ...[
                      const SizedBox(height: 2),
                      Text(
                        fileSize,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: theme.textTheme.bodySmall?.color?.withOpacity(0.6),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: onPick,
                style: OutlinedButton.styleFrom(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                ),
                child: Text(hasFile ? 'Change' : 'Select'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildResultCard({
    required ThemeData theme,
    required String title,
    required String filePath,
    VoidCallback? onOpen,
    VoidCallback? onShare,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF10B981).withOpacity(0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF10B981).withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 20),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            filePath,
            style: const TextStyle(fontSize: 11.5, fontFamily: 'monospace'),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              if (onOpen != null) ...[
                OutlinedButton.icon(
                  onPressed: onOpen,
                  icon: const Icon(Broken.eye, size: 16),
                  label: const Text('Open'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    minimumSize: Size.zero,
                  ),
                ),
                const SizedBox(width: 8),
              ],
              if (onShare != null)
                FilledButton.icon(
                  onPressed: onShare,
                  icon: const Icon(Broken.share, size: 16),
                  label: const Text('Share File'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    minimumSize: Size.zero,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
