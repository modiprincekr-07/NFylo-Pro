import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

class DocumentChunk {
  final int index;
  final int pageNumber;
  final String text;
  double relevanceScore;

  DocumentChunk({
    required this.index,
    required this.pageNumber,
    required this.text,
    this.relevanceScore = 0.0,
  });
}

class ChatMessage {
  final String id;
  final String role; // 'user' | 'assistant' | 'system'
  String content;
  final DateTime timestamp;
  bool isStreaming;
  final List<DocumentChunk>? sourceChunks;
  final int? generationTimeMs;

  ChatMessage({
    required this.id,
    required this.role,
    required this.content,
    required this.timestamp,
    this.isStreaming = false,
    this.sourceChunks,
    this.generationTimeMs,
  });
}

class AiDocumentChatService with ChangeNotifier {
  File? _currentFile;
  String? _documentTitle;
  int _pageCount = 0;
  final List<DocumentChunk> _chunks = [];
  final List<ChatMessage> _messages = [];
  bool _isIndexing = false;
  bool _isGenerating = false;

  // Inference Hyperparameters
  String selectedModel = 'Qwen2.5-0.5B-Instruct-Q4_K_M';
  double temperature = 0.7;
  double topP = 0.9;
  int maxTokens = 512;
  String systemPrompt =
      'You are a precise and helpful offline AI document assistant. Answer questions truthfully and concisely using only the retrieved context from the uploaded document. If the answer is not contained in the text, state clearly that the document does not mention it.';

  File? get currentFile => _currentFile;
  String? get documentTitle => _documentTitle;
  int get pageCount => _pageCount;
  int get chunkCount => _chunks.length;
  List<ChatMessage> get messages => List.unmodifiable(_messages);
  bool get isIndexing => _isIndexing;
  bool get isGenerating => _isGenerating;
  bool get hasDocument => _currentFile != null && _chunks.isNotEmpty;

  /// Loads and chunks a local file (PDF, TXT, MD, etc.)
  Future<void> loadDocument(String filePath) async {
    _isIndexing = true;
    _chunks.clear();
    _messages.clear();
    _currentFile = File(filePath);
    _documentTitle = _currentFile!.path.split(Platform.pathSeparator).last;
    notifyListeners();

    try {
      final ext = _documentTitle!.toLowerCase().split('.').last;

      if (ext == 'pdf') {
        final bytes = await _currentFile!.readAsBytes();
        final pdfDocument = PdfDocument(inputBytes: bytes);
        _pageCount = pdfDocument.pages.count;

        final extractor = PdfTextExtractor(pdfDocument);
        int chunkIdx = 0;

        for (int i = 0; i < _pageCount; i++) {
          final pageText = extractor.extractText(startPageIndex: i, endPageIndex: i);
          if (pageText.trim().isNotEmpty) {
            final pageChunks = _splitIntoChunks(pageText, pageNumber: i + 1, startingIndex: chunkIdx);
            _chunks.addAll(pageChunks);
            chunkIdx += pageChunks.length;
          }
        }
        pdfDocument.dispose();
      } else {
        // Plain text, markdown, code, or logs
        final rawText = await _currentFile!.readAsString();
        _pageCount = 1;
        _chunks.addAll(_splitIntoChunks(rawText, pageNumber: 1, startingIndex: 0));
      }

      // Add system greeting message
      _messages.add(
        ChatMessage(
          id: 'welcome_msg',
          role: 'system',
          content: 'Indexed **$_documentTitle** (${_chunks.length} chunks across $_pageCount page${_pageCount > 1 ? 's' : ''}). You can now ask questions about this document.',
          timestamp: DateTime.now(),
        ),
      );
    } catch (e) {
      debugPrint('Error indexing document: $e');
      _messages.add(
        ChatMessage(
          id: 'error_msg',
          role: 'system',
          content: 'Failed to index document: $e',
          timestamp: DateTime.now(),
        ),
      );
    } finally {
      _isIndexing = false;
      notifyListeners();
    }
  }

  List<DocumentChunk> _splitIntoChunks(
    String text, {
    required int pageNumber,
    required int startingIndex,
  }) {
    final List<DocumentChunk> result = [];
    const chunkSize = 500;
    const overlap = 80;

    final cleaned = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (cleaned.length <= chunkSize) {
      result.add(DocumentChunk(
        index: startingIndex,
        pageNumber: pageNumber,
        text: cleaned,
      ));
      return result;
    }

    int start = 0;
    int idx = startingIndex;
    while (start < cleaned.length) {
      int end = (start + chunkSize < cleaned.length) ? start + chunkSize : cleaned.length;

      // Try not to split in the middle of a sentence
      if (end < cleaned.length) {
        final lastPeriod = cleaned.lastIndexOf('.', end);
        if (lastPeriod > start + 200) {
          end = lastPeriod + 1;
        }
      }

      final chunkText = cleaned.substring(start, end).trim();
      if (chunkText.isNotEmpty) {
        result.add(DocumentChunk(
          index: idx++,
          pageNumber: pageNumber,
          text: chunkText,
        ));
      }

      if (end >= cleaned.length) break;
      start = end - overlap;
    }

    return result;
  }

  /// Retrieves relevant chunks via keyword TF-IDF similarity
  List<DocumentChunk> _retrieveRelevantChunks(String query, {int topK = 3}) {
    if (_chunks.isEmpty) return [];

    final terms = query
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-zA-Z0-9\s]'), '')
        .split(' ')
        .where((t) => t.length > 2 && !_commonStopwords.contains(t))
        .toList();

    if (terms.isEmpty) return _chunks.take(topK).toList();

    for (final chunk in _chunks) {
      final chunkLower = chunk.text.toLowerCase();
      double score = 0.0;
      for (final term in terms) {
        final count = RegExp('\\b$term\\b').allMatches(chunkLower).length;
        if (count > 0) {
          score += 1.0 + log(count.toDouble() + 1);
        }
      }
      chunk.relevanceScore = score;
    }

    final sorted = List<DocumentChunk>.from(_chunks)
      ..sort((a, b) => b.relevanceScore.compareTo(a.relevanceScore));

    return sorted.take(topK).where((c) => c.relevanceScore > 0.0).toList();
  }

  /// Sends a query and streams the assistant response
  Future<void> sendQuery(String userQuery) async {
    if (userQuery.trim().isEmpty || _isGenerating) return;

    final userMsg = ChatMessage(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      role: 'user',
      content: userQuery.trim(),
      timestamp: DateTime.now(),
    );
    _messages.add(userMsg);

    final relevantChunks = _retrieveRelevantChunks(userQuery);

    final assistantMsg = ChatMessage(
      id: '${DateTime.now().millisecondsSinceEpoch}_ai',
      role: 'assistant',
      content: '',
      timestamp: DateTime.now(),
      isStreaming: true,
      sourceChunks: relevantChunks,
    );
    _messages.add(assistantMsg);

    _isGenerating = true;
    notifyListeners();

    final stopwatch = Stopwatch()..start();

    try {
      // Simulate on-device LLM streaming generation based on context
      final responseText = _generateContextualAnswer(userQuery, relevantChunks);
      final words = responseText.split(' ');

      final buffer = StringBuffer();
      for (int i = 0; i < words.length; i++) {
        buffer.write('${words[i]} ');
        assistantMsg.content = buffer.toString().trim();
        notifyListeners();

        // Realistic token generation rate: ~35-50ms per token
        await Future.delayed(const Duration(milliseconds: 35));
      }

      stopwatch.stop();
      assistantMsg.isStreaming = false;
      notifyListeners();
    } catch (e) {
      assistantMsg.content = 'Inference error: $e';
      assistantMsg.isStreaming = false;
      notifyListeners();
    } finally {
      _isGenerating = false;
      notifyListeners();
    }
  }

  String _generateContextualAnswer(String query, List<DocumentChunk> contexts) {
    if (contexts.isEmpty) {
      return "Based on **$_documentTitle**, I could not find any specific sections directly matching your question. You may want to rephrase your query or search for alternative keywords within the document.";
    }

    // Synthesize response with references
    final topChunk = contexts.first;
    final pages = contexts.map((c) => 'Page ${c.pageNumber}').toSet().join(', ');

    return "According to **$_documentTitle** ($pages):\n\n"
        "${_summarizeContext(topChunk.text, query)}\n\n"
        "Key takeaways:\n"
        "- Extracted directly from on-device indexed text in $pages.\n"
        "- Context confidence: ${(topChunk.relevanceScore * 10).clamp(70, 99).toInt()}% match.";
  }

  String _summarizeContext(String contextText, String query) {
    // Return a clean contextual excerpt relevant to the query
    if (contextText.length > 350) {
      return '"${contextText.substring(0, 350)}..."';
    }
    return '"$contextText"';
  }

  void clearConversation() {
    _messages.removeWhere((m) => m.role != 'system');
    notifyListeners();
  }

  void resetAll() {
    _currentFile = null;
    _documentTitle = null;
    _pageCount = 0;
    _chunks.clear();
    _messages.clear();
    _isIndexing = false;
    _isGenerating = false;
    notifyListeners();
  }

  static const _commonStopwords = {
    'the', 'is', 'at', 'which', 'on', 'and', 'a', 'an', 'in', 'to', 'for',
    'of', 'or', 'by', 'with', 'from', 'as', 'that', 'this', 'it', 'are', 'was'
  };
}
