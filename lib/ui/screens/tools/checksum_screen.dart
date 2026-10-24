import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import '../../../core/icon_fonts/broken_icons.dart';
import '../../../core/utils.dart';
import '../../../providers/file_manager_provider.dart';
import '../internal_file_picker_screen.dart';

class ChecksumScreen extends StatefulWidget {
  final String? initialFilePath;
  const ChecksumScreen({super.key, this.initialFilePath});

  @override
  State<ChecksumScreen> createState() => _ChecksumScreenState();
}

class _ChecksumScreenState extends State<ChecksumScreen> {
  String? _selectedFilePath;
  bool _isCalculating = false;
  double _progress = 0.0;

  String? _md5Hash;
  String? _sha1Hash;
  String? _sha256Hash;

  final TextEditingController _verifyController = TextEditingController();
  String _verifyStatus = 'none'; // 'none', 'matched', 'mismatched'
  String _matchedAlgorithm = '';

  @override
  void initState() {
    super.initState();
    _verifyController.addListener(_onVerifyChanged);
    if (widget.initialFilePath != null) {
      _selectedFilePath = widget.initialFilePath;
      _calculateHashes(widget.initialFilePath!);
    }
  }

  @override
  void dispose() {
    _verifyController.dispose();
    super.dispose();
  }

  void _onVerifyChanged() {
    final input = _verifyController.text.trim().toLowerCase();
    if (input.isEmpty) {
      setState(() {
        _verifyStatus = 'none';
        _matchedAlgorithm = '';
      });
      return;
    }

    if (input == _md5Hash?.toLowerCase()) {
      setState(() {
        _verifyStatus = 'matched';
        _matchedAlgorithm = 'MD5';
      });
    } else if (input == _sha1Hash?.toLowerCase()) {
      setState(() {
        _verifyStatus = 'matched';
        _matchedAlgorithm = 'SHA-1';
      });
    } else if (input == _sha256Hash?.toLowerCase()) {
      setState(() {
        _verifyStatus = 'matched';
        _matchedAlgorithm = 'SHA-256';
      });
    } else {
      setState(() {
        _verifyStatus = 'mismatched';
        _matchedAlgorithm = '';
      });
    }
  }

  Future<void> _pickFile() async {
    final rootPath = context.read<FileManagerProvider>().rootPath;
    final picked = await InternalFilePickerScreen.show(
      context,
      rootPath: rootPath,
      pickDirectory: false,
    );
    if (picked != null && picked.isNotEmpty) {
      final path = picked.first;
      setState(() {
        _selectedFilePath = path;
      });
      _calculateHashes(path);
    }
  }

  Future<void> _calculateHashes(String path) async {
    final file = File(path);
    if (!file.existsSync()) return;

    setState(() {
      _isCalculating = true;
      _progress = 0.0;
      _md5Hash = null;
      _sha1Hash = null;
      _sha256Hash = null;
      _verifyStatus = 'none';
    });

    try {
      final totalBytes = await file.length();
      int processedBytes = 0;

      // Stream file to compute MD5, SHA-1, SHA-256 simultaneously in one pass
      final md5Sink = md5.startChunkedConversion(
        ChunkedConversionSink<Digest>.withCallback((d) => _md5Hash = d.first.toString()),
      );
      final sha1Sink = sha1.startChunkedConversion(
        ChunkedConversionSink<Digest>.withCallback((d) => _sha1Hash = d.first.toString()),
      );
      final sha256Sink = sha256.startChunkedConversion(
        ChunkedConversionSink<Digest>.withCallback((d) => _sha256Hash = d.first.toString()),
      );

      final stream = file.openRead();
      DateTime lastYield = DateTime.now();

      await for (final chunk in stream) {
        md5Sink.add(chunk);
        sha1Sink.add(chunk);
        sha256Sink.add(chunk);

        processedBytes += chunk.length;
        final now = DateTime.now();
        if (now.difference(lastYield).inMilliseconds > 90) {
          lastYield = now;
          if (mounted && totalBytes > 0) {
            setState(() {
              _progress = processedBytes / totalBytes;
            });
          }
        }
      }

      md5Sink.close();
      sha1Sink.close();
      sha256Sink.close();

      if (mounted) {
        setState(() {
          _isCalculating = false;
          _progress = 1.0;
        });
        _onVerifyChanged();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isCalculating = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to calculate checksum: $e')),
        );
      }
    }
  }

  void _copyToClipboard(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    HapticFeedback.lightImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label copied to clipboard'),
        duration: const Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasFile = _selectedFilePath != null && File(_selectedFilePath!).existsSync();
    final fileName = hasFile ? p.basename(_selectedFilePath!) : 'No file selected';
    final fileSize = hasFile ? FileUtils.formatBytes(File(_selectedFilePath!).lengthSync(), 2) : '';

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Checksum & Verify'),
        elevation: 0,
        backgroundColor: theme.colorScheme.surface,
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Selected File Card
            Container(
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
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      Broken.document_code_2,
                      color: theme.colorScheme.primary,
                      size: 26,
                    ),
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
                  FilledButton(
                    onPressed: _isCalculating ? null : _pickFile,
                    style: FilledButton.styleFrom(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    ),
                    child: Text(hasFile ? 'Change' : 'Select File'),
                  ),
                ],
              ),
            ),

            if (_isCalculating) ...[
              const SizedBox(height: 20),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: _progress > 0 ? _progress : null,
                  minHeight: 6,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Computing cryptographic hashes... ${(_progress * 100).toInt()}%',
                style: TextStyle(fontSize: 12, color: theme.colorScheme.primary),
              ),
            ],

            if (_sha256Hash != null) ...[
              const SizedBox(height: 24),

              // Verify Box
              Text(
                'Verify Checksum',
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _verifyController,
                decoration: InputDecoration(
                  hintText: 'Paste original hash to verify match...',
                  prefixIcon: const Icon(Broken.security_safe, size: 20),
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_verifyController.text.isNotEmpty)
                        IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () => _verifyController.clear(),
                        ),
                      IconButton(
                        icon: const Icon(Broken.document_copy, size: 18),
                        tooltip: 'Paste from clipboard',
                        onPressed: () async {
                          final data = await Clipboard.getData('text/plain');
                          if (data?.text != null) {
                            _verifyController.text = data!.text!;
                          }
                        },
                      ),
                    ],
                  ),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                  filled: true,
                  fillColor: theme.colorScheme.surfaceVariant.withOpacity(0.25),
                ),
              ),
              const SizedBox(height: 12),

              // Match / Mismatch banner
              if (_verifyStatus == 'matched')
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFF10B981).withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Checksum Matched! ($_matchedAlgorithm verified)',
                          style: const TextStyle(
                            color: Color(0xFF10B981),
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              else if (_verifyStatus == 'mismatched')
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEF4444).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFEF4444).withOpacity(0.3)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.error_outline_rounded, color: Color(0xFFEF4444), size: 20),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Checksum Mismatch! The file may be corrupt or modified.',
                          style: TextStyle(
                            color: Color(0xFFEF4444),
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              const SizedBox(height: 24),
              Text(
                'Calculated Hashes',
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),

              // MD5 Card
              _buildHashCard(
                theme: theme,
                title: 'MD5',
                hash: _md5Hash!,
                color: const Color(0xFF3B82F6),
              ),
              const SizedBox(height: 10),

              // SHA-1 Card
              _buildHashCard(
                theme: theme,
                title: 'SHA-1',
                hash: _sha1Hash!,
                color: const Color(0xFF8B5CF6),
              ),
              const SizedBox(height: 10),

              // SHA-256 Card
              _buildHashCard(
                theme: theme,
                title: 'SHA-256',
                hash: _sha256Hash!,
                color: const Color(0xFF10B981),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHashCard({
    required ThemeData theme,
    required String title,
    required String hash,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.dividerColor.withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Broken.document_copy, size: 18),
                onPressed: () => _copyToClipboard(hash, title),
                tooltip: 'Copy $title',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SelectableText(
            hash,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}
