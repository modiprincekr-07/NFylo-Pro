import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:path_provider/path_provider.dart';
import '../../core/icon_fonts/broken_icons.dart';
import '../../services/ai_document_chat_service.dart';

class AiDocChatScreen extends StatefulWidget {
  final String? initialFilePath;

  const AiDocChatScreen({super.key, this.initialFilePath});

  @override
  State<AiDocChatScreen> createState() => _AiDocChatScreenState();
}

class _AiDocChatScreenState extends State<AiDocChatScreen> {
  final AiDocumentChatService _chatService = AiDocumentChatService();
  final TextEditingController _queryCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    _chatService.addListener(_onServiceUpdate);
    if (widget.initialFilePath != null) {
      _chatService.loadDocument(widget.initialFilePath!);
    }
  }

  void _onServiceUpdate() {
    if (mounted) {
      setState(() {});
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _chatService.removeListener(_onServiceUpdate);
    _queryCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _handleSend() {
    final query = _queryCtrl.text.trim();
    if (query.isEmpty || _chatService.isGenerating) return;
    _queryCtrl.clear();
    _chatService.sendQuery(query);
  }

  Future<void> _loadSampleDoc() async {
    final tempDir = await getTemporaryDirectory();
    final sampleFile = File('${tempDir.path}/Sample_AI_Architecture_Doc.txt');
    await sampleFile.writeAsString('''NFylo-Pro AI Architecture & Offline LLM Engine Specification
Document Version: 2.4.0
Release Date: October 2026

Overview:
NFylo-Pro introduces a modular on-device artificial intelligence lab designed to execute small language models (SLMs) such as Qwen2.5 0.5B and 1.5B entirely in local memory without transmitting telemetry or tokens to cloud servers.

Key Specifications:
1. Model Quantization: Models are quantized into 4-bit GGUF formats (Q4_K_M) maintaining 98.2% perplexity of full 16-bit precision while reducing memory footprint to under 800 MB RAM.
2. RAG Chunking: Documents uploaded by the user are segmented into 500-character semantic chunks with an 80-character overlap.
3. TF-IDF & Vector Retrieval: Chunks are indexed using local keyword and BM25/TF-IDF scoring to supply relevant context windows to the prompt.
4. Privacy Boundary: All weights and embeddings reside in application support storage and are never uploaded to remote servers.
5. Supported Media: Text extraction covers PDF, TXT, Markdown, and DOCX files.''');

    _chatService.loadDocument(sampleFile.path);
  }

  void _showSettingsDialog() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E1E24) : Colors.white,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
              ),
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 44,
                      height: 4,
                      decoration: BoxDecoration(
                        color: theme.dividerColor.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'LLM Inference Parameters',
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Temperature: ${_chatService.temperature.toStringAsFixed(2)}'),
                      Text('Top-P: ${_chatService.topP.toStringAsFixed(2)}'),
                    ],
                  ),
                  Slider(
                    value: _chatService.temperature,
                    min: 0.1,
                    max: 1.0,
                    divisions: 9,
                    label: _chatService.temperature.toStringAsFixed(2),
                    onChanged: (v) {
                      setModalState(() => _chatService.temperature = v);
                      setState(() {});
                    },
                  ),
                  const SizedBox(height: 10),
                  Text('Active Model Engine', style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor)),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    value: _chatService.selectedModel,
                    decoration: InputDecoration(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'Qwen2.5-0.5B-Instruct-Q4_K_M',
                        child: Text('Qwen2.5 0.5B (Fast, ~400MB)'),
                      ),
                      DropdownMenuItem(
                        value: 'Qwen2.5-1.5B-Instruct-Q4_K_M',
                        child: Text('Qwen2.5 1.5B (Deep Reasoning, ~950MB)'),
                      ),
                      DropdownMenuItem(
                        value: 'Llama-3.2-1B-Instruct-Q4_K_M',
                        child: Text('Llama 3.2 1B (~750MB)'),
                      ),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        setModalState(() => _chatService.selectedModel = val);
                        setState(() {});
                      }
                    },
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Apply Settings'),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Local Document Chat'),
            Text(
              _chatService.hasDocument ? _chatService.documentTitle! : 'Qwen2.5 GGUF Offline',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor, fontSize: 11),
            ),
          ],
        ),
        elevation: 0,
        backgroundColor: Colors.transparent,
        actions: [
          IconButton(
            icon: const Icon(Broken.setting_2),
            tooltip: 'Model Parameters',
            onPressed: _showSettingsDialog,
          ),
          if (_chatService.hasDocument)
            IconButton(
              icon: const Icon(Broken.trash),
              tooltip: 'Clear Chat',
              onPressed: () => _chatService.clearConversation(),
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (!_chatService.hasDocument) ...[
              Expanded(child: _buildEmptyDocumentView(theme, isDark)),
            ] else ...[
              _buildDocumentHeader(theme, isDark),
              Expanded(child: _buildChatListView(theme, isDark)),
              _buildQuickPromptBar(theme),
              _buildInputBar(theme, isDark),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyDocumentView(ThemeData theme, bool isDark) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(Broken.document_text, size: 64, color: theme.colorScheme.primary),
            ),
            const SizedBox(height: 24),
            Text(
              'No Document Selected',
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Select a PDF, TXT, or Markdown document to chat with it offline using local on-device LLM inference.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              icon: const Icon(Broken.document_upload),
              label: const Text('Try Sample AI Specification Doc'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              onPressed: _loadSampleDoc,
            ),
            const SizedBox(height: 28),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E1E24) : Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: theme.dividerColor.withOpacity(0.1)),
              ),
              child: Column(
                children: [
                  _featureBullet(theme, Broken.shield_slash, '100% On-Device: No data sent to third-party APIs'),
                  const SizedBox(height: 10),
                  _featureBullet(theme, Broken.cpu, 'Qwen2.5 GGUF quantized weights for fast local generation'),
                  const SizedBox(height: 10),
                  _featureBullet(theme, Broken.search_normal_1, 'Automatic semantic chunking & context retrieval'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _featureBullet(ThemeData theme, IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 18, color: theme.colorScheme.primary),
        const SizedBox(width: 12),
        Expanded(
          child: Text(text, style: theme.textTheme.bodySmall),
        ),
      ],
    );
  }

  Widget _buildDocumentHeader(ThemeData theme, bool isDark) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 6, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E24) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.dividerColor.withOpacity(0.1)),
      ),
      child: Row(
        children: [
          Icon(Broken.document_text, size: 20, color: theme.colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _chatService.documentTitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
                Text(
                  '${_chatService.chunkCount} semantic chunks • ${_chatService.pageCount} page(s)',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor, fontSize: 11),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () => _chatService.resetAll(),
            child: const Text('Change', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _buildChatListView(ThemeData theme, bool isDark) {
    return ListView.builder(
      controller: _scrollCtrl,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: _chatService.messages.length,
      itemBuilder: (ctx, i) {
        final msg = _chatService.messages[i];
        return _buildMessageBubble(theme, isDark, msg);
      },
    );
  }

  Widget _buildMessageBubble(ThemeData theme, bool isDark, ChatMessage msg) {
    if (msg.role == 'system') {
      return Center(
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withOpacity(0.08),
            borderRadius: BorderRadius.circular(12),
          ),
          child: MarkdownBody(
            data: msg.content,
            styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
              p: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
            ),
          ),
        ),
      );
    }

    final isUser = msg.role == 'user';

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.82),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isUser
              ? theme.colorScheme.primary
              : (isDark ? const Color(0xFF1E1E24) : Colors.white),
          borderRadius: BorderRadius.circular(18).copyWith(
            bottomRight: isUser ? const Radius.circular(2) : null,
            bottomLeft: !isUser ? const Radius.circular(2) : null,
          ),
          border: isUser ? null : Border.all(color: theme.dividerColor.withOpacity(0.1)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isUser) ...[
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Broken.cpu, size: 14, color: theme.colorScheme.primary),
                  const SizedBox(width: 6),
                  Text(
                    'Qwen2.5 GGUF',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
            ],
            isUser
                ? Text(
                    msg.content,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                  )
                : MarkdownBody(
                    data: msg.content.isEmpty && msg.isStreaming ? 'Thinking...' : msg.content,
                    styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
                      p: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
                    ),
                  ),
            if (msg.isStreaming) ...[
              const SizedBox(height: 8),
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ],
            if (!isUser && !msg.isStreaming && msg.content.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  InkWell(
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: msg.content));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Copied to clipboard')),
                      );
                    },
                    child: Icon(Broken.copy, size: 16, color: theme.hintColor),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildQuickPromptBar(ThemeData theme) {
    final prompts = [
      'Summarize this document',
      'What are the key takeaways?',
      'Extract all numbers and dates',
      'Explain like I\'m five'
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: prompts.map((p) {
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ActionChip(
              label: Text(p, style: const TextStyle(fontSize: 11)),
              backgroundColor: theme.colorScheme.surfaceContainerHighest.withOpacity(0.5),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              onPressed: () {
                _queryCtrl.text = p;
                _handleSend();
              },
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildInputBar(ThemeData theme, bool isDark) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E24) : Colors.white,
        border: Border(top: BorderSide(color: theme.dividerColor.withOpacity(0.1))),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _queryCtrl,
              enabled: !_chatService.isGenerating,
              decoration: InputDecoration(
                hintText: 'Ask questions about this file...',
                hintStyle: TextStyle(fontSize: 13, color: theme.hintColor),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: theme.colorScheme.surfaceContainerHighest.withOpacity(0.4),
              ),
              onSubmitted: (_) => _handleSend(),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            icon: _chatService.isGenerating
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Broken.send_2, size: 20),
            onPressed: _chatService.isGenerating ? null : _handleSend,
          ),
        ],
      ),
    );
  }
}
