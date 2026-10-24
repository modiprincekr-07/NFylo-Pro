import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/icon_fonts/broken_icons.dart';
import '../../../core/utils.dart';
import '../../../providers/file_manager_provider.dart';
import '../internal_file_picker_screen.dart';

class TableColumnInfo {
  final int cid;
  final String name;
  final String type;
  final bool notNull;
  final String? defaultValue;
  final bool isPrimaryKey;

  TableColumnInfo({
    required this.cid,
    required this.name,
    required this.type,
    required this.notNull,
    this.defaultValue,
    required this.isPrimaryKey,
  });

  factory TableColumnInfo.fromMap(Map<String, dynamic> map) {
    return TableColumnInfo(
      cid: (map['cid'] as int?) ?? 0,
      name: (map['name'] as String?) ?? '',
      type: ((map['type'] as String?) ?? 'TEXT').toUpperCase(),
      notNull: ((map['notnull'] as int?) ?? 0) == 1,
      defaultValue: map['dflt_value']?.toString(),
      isPrimaryKey: ((map['pk'] as int?) ?? 0) > 0,
    );
  }
}

class TableMeta {
  final String name;
  final int rowCount;
  final List<TableColumnInfo> columns;

  TableMeta({
    required this.name,
    required this.rowCount,
    required this.columns,
  });
}

class SqliteViewerScreen extends StatefulWidget {
  final String? initialDbPath;

  const SqliteViewerScreen({super.key, this.initialDbPath});

  @override
  State<SqliteViewerScreen> createState() => _SqliteViewerScreenState();
}

class _SqliteViewerScreenState extends State<SqliteViewerScreen>
    with SingleTickerProviderStateMixin {
  String? _dbPath;
  Database? _db;
  bool _isLoading = false;
  String? _errorMessage;

  // DB Metadata
  int _fileSizeBytes = 0;
  List<TableMeta> _tables = [];
  TableMeta? _selectedTable;

  // Browser state
  int _currentPage = 0;
  int _pageSize = 50;
  bool _isLoadingRows = false;
  List<String> _currentColumns = [];
  List<List<dynamic>> _currentRows = [];

  // SQL Console state
  final TextEditingController _sqlController = TextEditingController();
  bool _isExecutingQuery = false;
  String? _queryError;
  int? _queryTimeMs;
  int? _queryRowCount;
  List<String> _queryColumns = [];
  List<List<dynamic>> _queryRows = [];

  TabController? _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    if (widget.initialDbPath != null) {
      _openDatabaseFile(widget.initialDbPath!);
    }
  }

  @override
  void dispose() {
    _tabController?.dispose();
    _sqlController.dispose();
    _closeDatabase();
    super.dispose();
  }

  Future<void> _closeDatabase() async {
    try {
      if (_db != null && _db!.isOpen) {
        await _db!.close();
      }
    } catch (_) {}
    _db = null;
  }

  Future<void> _pickDatabaseFile() async {
    final rootPath = context.read<FileManagerProvider>().rootPath;
    final picked = await InternalFilePickerScreen.show(
      context,
      rootPath: rootPath,
      pickDirectory: false,
    );

    if (picked != null && picked.isNotEmpty) {
      final path = picked.first;
      final ext = p.extension(path).toLowerCase();
      if (!{'.db', '.sqlite', '.sqlite3', '.db3', ''}.contains(ext)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please select a SQLite database file (.db, .sqlite).'),
          ),
        );
        return;
      }
      _openDatabaseFile(path);
    }
  }

  Future<void> _openDatabaseFile(String path) async {
    await _closeDatabase();

    setState(() {
      _dbPath = path;
      _isLoading = true;
      _errorMessage = null;
      _tables = [];
      _selectedTable = null;
      _currentRows = [];
      _currentColumns = [];
      _currentPage = 0;
      _queryError = null;
      _queryRows = [];
      _queryColumns = [];
    });

    try {
      final file = File(path);
      if (!file.existsSync()) {
        throw Exception('File does not exist: $path');
      }
      _fileSizeBytes = file.lengthSync();

      // Open in strict read-only mode to prevent accidental modifications
      _db = await openReadOnlyDatabase(path);

      // Verify sqlite header / connectivity
      final tablesQuery = await _db!.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name;",
      );

      final loadedTables = <TableMeta>[];
      for (final row in tablesQuery) {
        final name = row['name'] as String;

        // Row count
        int rowCount = 0;
        try {
          final countRes =
              await _db!.rawQuery('SELECT count(*) as cnt FROM "$name";');
          if (countRes.isNotEmpty) {
            rowCount = (countRes.first['cnt'] as int?) ?? 0;
          }
        } catch (_) {}

        // Columns schema
        final columns = <TableColumnInfo>[];
        try {
          final schemaRes =
              await _db!.rawQuery('PRAGMA table_info("$name");');
          for (final colMap in schemaRes) {
            columns.add(TableColumnInfo.fromMap(colMap));
          }
        } catch (_) {}

        loadedTables.add(TableMeta(
          name: name,
          rowCount: rowCount,
          columns: columns,
        ));
      }

      if (mounted) {
        setState(() {
          _tables = loadedTables;
          _isLoading = false;
          if (_tables.isNotEmpty) {
            _selectedTable = _tables.first;
          }
        });

        if (_selectedTable != null) {
          _loadTableRows(_selectedTable!, 0);
          _sqlController.text = 'SELECT * FROM "${_selectedTable!.name}" LIMIT 25;';
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage =
              'Could not open database:\n$e\n\nEnsure this is an unencrypted, valid SQLite file.';
        });
      }
    }
  }

  Future<void> _loadTableRows(TableMeta table, int page) async {
    if (_db == null || !_db!.isOpen) return;

    setState(() {
      _isLoadingRows = true;
      _currentPage = page;
    });

    try {
      final offset = page * _pageSize;
      final query =
          'SELECT * FROM "${table.name}" LIMIT $_pageSize OFFSET $offset;';
      final results = await _db!.rawQuery(query);

      final cols = table.columns.map((c) => c.name).toList();
      final rows = <List<dynamic>>[];

      for (final rowMap in results) {
        final row = <dynamic>[];
        for (final col in cols) {
          row.add(rowMap[col]);
        }
        rows.add(row);
      }

      if (mounted) {
        setState(() {
          _currentColumns = cols;
          _currentRows = rows;
          _isLoadingRows = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingRows = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading table rows: $e')),
        );
      }
    }
  }

  bool _isReadOnlyQuery(String sql) {
    final clean = sql.trim().toLowerCase();
    // Allow SELECT, PRAGMA, EXPLAIN, WITH (common table expressions)
    if (clean.startsWith('select') ||
        clean.startsWith('pragma') ||
        clean.startsWith('explain') ||
        clean.startsWith('with')) {
      // Disallow mutation keywords inside CTE or multi-statements
      final forbidden = [
        'insert ',
        'update ',
        'delete ',
        'drop ',
        'alter ',
        'create ',
        'truncate ',
        'vacuum ',
        'replace ',
        'attach ',
        'detach ',
      ];
      for (final word in forbidden) {
        if (clean.contains(word)) return false;
      }
      return true;
    }
    return false;
  }

  Future<void> _executeCustomSql() async {
    final sql = _sqlController.text.trim();
    if (sql.isEmpty) return;

    if (_db == null || !_db!.isOpen) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No database currently open.')),
      );
      return;
    }

    if (!_isReadOnlyQuery(sql)) {
      setState(() {
        _queryError =
            'Execution Blocked: Only read-only queries (SELECT, PRAGMA, EXPLAIN) are permitted in this viewer.';
      });
      return;
    }

    setState(() {
      _isExecutingQuery = true;
      _queryError = null;
      _queryRows = [];
      _queryColumns = [];
      _queryTimeMs = null;
      _queryRowCount = null;
    });

    final stopwatch = Stopwatch()..start();

    try {
      final results = await _db!.rawQuery(sql);
      stopwatch.stop();

      List<String> cols = [];
      final rows = <List<dynamic>>[];

      if (results.isNotEmpty) {
        cols = results.first.keys.toList();
        for (final rowMap in results) {
          final row = <dynamic>[];
          for (final col in cols) {
            row.add(rowMap[col]);
          }
          rows.add(row);
        }
      }

      if (mounted) {
        setState(() {
          _isExecutingQuery = false;
          _queryColumns = cols;
          _queryRows = rows;
          _queryRowCount = results.length;
          _queryTimeMs = stopwatch.elapsedMilliseconds;
        });
      }
    } catch (e) {
      stopwatch.stop();
      if (mounted) {
        setState(() {
          _isExecutingQuery = false;
          _queryError = 'SQL Error: $e';
        });
      }
    }
  }

  Future<void> _exportToCsv({
    required String title,
    required List<String> columns,
    required List<List<dynamic>> rows,
  }) async {
    if (columns.isEmpty || rows.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No data to export.')),
      );
      return;
    }

    try {
      final downloadsDir = Directory('/storage/emulated/0/Download');
      if (!downloadsDir.existsSync()) {
        downloadsDir.createSync(recursive: true);
      }

      final safeTitle = title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final outPath = p.join(downloadsDir.path, '${safeTitle}_$timestamp.csv');

      final buffer = StringBuffer();
      // Write Header
      buffer.writeln(columns.map((c) {
        final escaped = c.replaceAll('"', '""');
        return '"$escaped"';
      }).join(','));

      // Write Rows
      for (final row in rows) {
        buffer.writeln(row.map((cell) {
          if (cell == null) return '""';
          final s = cell.toString().replaceAll('"', '""');
          return '"$s"';
        }).join(','));
      }

      final file = File(outPath);
      await file.writeAsString(buffer.toString());

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('CSV exported: ${p.basename(outPath)}'),
            backgroundColor: Colors.green.shade700,
            action: SnackBarAction(
              label: 'Share',
              textColor: Colors.white,
              onPressed: () => Share.shareXFiles([XFile(outPath)]),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to export CSV: $e')),
        );
      }
    }
  }

  void _showCellDetails(String column, dynamic value) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(column, style: const TextStyle(fontSize: 16)),
        content: SingleChildScrollView(
          child: SelectableText(
            value == null ? 'NULL' : value.toString(),
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 13,
              color: value == null ? Colors.grey : null,
              fontStyle: value == null ? FontStyle.italic : FontStyle.normal,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              if (value != null) {
                Clipboard.setData(ClipboardData(text: value.toString()));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Copied to clipboard')),
                );
              }
              Navigator.pop(ctx);
            },
            child: const Text('Copy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasDatabase = _db != null && _db!.isOpen;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          hasDatabase ? p.basename(_dbPath!) : 'SQLite Database Viewer',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          overflow: TextOverflow.ellipsis,
        ),
        elevation: 0,
        backgroundColor: theme.colorScheme.surface,
        actions: [
          IconButton(
            icon: const Icon(Icons.folder_open_outlined),
            tooltip: 'Open Database',
            onPressed: _pickDatabaseFile,
          ),
          if (hasDatabase)
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: 'Close Database',
              onPressed: () {
                _closeDatabase();
                setState(() {
                  _dbPath = null;
                  _tables = [];
                  _selectedTable = null;
                });
              },
            ),
        ],
        bottom: hasDatabase
            ? TabBar(
                controller: _tabController,
                indicatorColor: theme.colorScheme.primary,
                labelColor: theme.colorScheme.primary,
                unselectedLabelColor:
                    theme.textTheme.bodyMedium?.color?.withOpacity(0.6),
                tabs: [
                  Tab(text: 'Data (${_selectedTable?.rowCount ?? 0})'),
                  Tab(text: 'Schema (${_selectedTable?.columns.length ?? 0})'),
                  const Tab(text: 'SQL Console'),
                ],
              )
            : null,
      ),
      body: _isLoading
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Reading SQLite database structure...'),
                ],
              ),
            )
          : _errorMessage != null
              ? _buildErrorView(theme)
              : hasDatabase
                  ? _buildDatabaseActiveView(theme)
                  : _buildEmptyPickerView(theme),
    );
  }

  // --------------------------------------------------------------------------
  // Empty State: Select a database
  // --------------------------------------------------------------------------

  Widget _buildEmptyPickerView(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Broken.data,
                size: 64,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'SQLite Database Viewer',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Open and browse any .db, .sqlite, or .sqlite3 file.\nInspect table schemas, explore rows, and execute safe read-only SQL queries.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: theme.textTheme.bodySmall?.color?.withOpacity(0.7),
                height: 1.4,
              ),
            ),
            const SizedBox(height: 28),
            FilledButton.icon(
              onPressed: _pickDatabaseFile,
              icon: const Icon(Icons.folder_open, size: 20),
              label: const Text('Open SQLite File'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorView(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 54, color: Colors.redAccent),
            const SizedBox(height: 16),
            Text(
              'Database Error',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: Colors.redAccent,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, height: 1.4),
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _pickDatabaseFile,
              icon: const Icon(Icons.folder_open),
              label: const Text('Choose Another File'),
            ),
          ],
        ),
      ),
    );
  }

  // --------------------------------------------------------------------------
  // Active DB View (Table dropdown + TabBarView)
  // --------------------------------------------------------------------------

  Widget _buildDatabaseActiveView(ThemeData theme) {
    return Column(
      children: [
        // Table Selector Header Strip
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            border: Border(
              bottom: BorderSide(
                color: theme.dividerColor.withOpacity(0.08),
              ),
            ),
          ),
          child: Row(
            children: [
              const Icon(Icons.table_chart_outlined, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: _tables.isEmpty
                    ? const Text('No user tables in database', style: TextStyle(fontSize: 13))
                    : DropdownButtonHideUnderline(
                        child: DropdownButton<TableMeta>(
                          value: _selectedTable,
                          isExpanded: true,
                          items: _tables.map((t) {
                            return DropdownMenuItem<TableMeta>(
                              value: t,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    t.name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13.5,
                                    ),
                                  ),
                                  Text(
                                    '${t.rowCount} rows',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: theme.textTheme.bodySmall?.color?.withOpacity(0.6),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                          onChanged: (newTable) {
                            if (newTable != null && newTable != _selectedTable) {
                              setState(() {
                                _selectedTable = newTable;
                                _currentPage = 0;
                              });
                              _loadTableRows(newTable, 0);
                              _sqlController.text =
                                  'SELECT * FROM "${newTable.name}" LIMIT 25;';
                            }
                          },
                        ),
                      ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  FileUtils.formatBytes(_fileSizeBytes, 1),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
            ],
          ),
        ),

        // Tabs Content
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildDataBrowserTab(theme),
              _buildSchemaTab(theme),
              _buildSqlConsoleTab(theme),
            ],
          ),
        ),
      ],
    );
  }

  // --------------------------------------------------------------------------
  // Tab 1: Data Browser (Paginated Data Table)
  // --------------------------------------------------------------------------

  Widget _buildDataBrowserTab(ThemeData theme) {
    if (_selectedTable == null) {
      return const Center(child: Text('No table selected.'));
    }

    final totalRows = _selectedTable!.rowCount;
    final totalPages = (totalRows / _pageSize).ceil();
    final isFirstPage = _currentPage == 0;
    final isLastPage = totalPages <= 1 || _currentPage >= totalPages - 1;

    return Column(
      children: [
        // Pagination & Actions bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          color: theme.colorScheme.surfaceVariant.withOpacity(0.2),
          child: Row(
            children: [
              Text(
                'Page ${_currentPage + 1} of ${totalPages == 0 ? 1 : totalPages}',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.chevron_left, size: 20),
                onPressed: isFirstPage || _isLoadingRows
                    ? null
                    : () => _loadTableRows(_selectedTable!, _currentPage - 1),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right, size: 20),
                onPressed: isLastPage || _isLoadingRows
                    ? null
                    : () => _loadTableRows(_selectedTable!, _currentPage + 1),
              ),
              IconButton(
                icon: const Icon(Icons.file_download_outlined, size: 20),
                tooltip: 'Export table to CSV',
                onPressed: () => _exportToCsv(
                  title: _selectedTable!.name,
                  columns: _currentColumns,
                  rows: _currentRows,
                ),
              ),
            ],
          ),
        ),

        // Table Rows Content
        Expanded(
          child: _isLoadingRows
              ? const Center(child: CircularProgressIndicator())
              : _currentRows.isEmpty
                  ? Center(
                      child: Text(
                        totalRows == 0
                            ? 'Table "${_selectedTable!.name}" is empty.'
                            : 'No rows found on this page.',
                        style: const TextStyle(color: Colors.grey),
                      ),
                    )
                  : SingleChildScrollView(
                      scrollDirection: Axis.vertical,
                      physics: const BouncingScrollPhysics(),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        physics: const BouncingScrollPhysics(),
                        child: DataTable(
                          columnSpacing: 20,
                          horizontalMargin: 16,
                          headingRowHeight: 40,
                          dataRowMinHeight: 38,
                          dataRowMaxHeight: 44,
                          columns: _currentColumns.map((colName) {
                            final colInfo = _selectedTable!.columns.firstWhere(
                              (c) => c.name == colName,
                              orElse: () => TableColumnInfo(
                                cid: 0,
                                name: colName,
                                type: '',
                                notNull: false,
                                isPrimaryKey: false,
                              ),
                            );

                            return DataColumn(
                              label: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (colInfo.isPrimaryKey) ...[
                                    const Icon(Icons.key, size: 13, color: Colors.amber),
                                    const SizedBox(width: 4),
                                  ],
                                  Text(
                                    colName,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12.5,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                          rows: _currentRows.map((row) {
                            return DataRow(
                              cells: List.generate(row.length, (i) {
                                final val = row[i];
                                final colName = _currentColumns[i];
                                String displayText;

                                if (val == null) {
                                  displayText = 'NULL';
                                } else if (val is Uint8List) {
                                  displayText = '[BLOB ${val.length} bytes]';
                                } else {
                                  displayText = val.toString();
                                }

                                return DataCell(
                                  InkWell(
                                    onTap: () => _showCellDetails(colName, val),
                                    child: Container(
                                      constraints: const BoxConstraints(maxWidth: 220),
                                      child: Text(
                                        displayText,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontStyle: val == null ? FontStyle.italic : FontStyle.normal,
                                          color: val == null ? Colors.grey : null,
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              }),
                            );
                          }).toList(),
                        ),
                      ),
                    ),
        ),
      ],
    );
  }

  // --------------------------------------------------------------------------
  // Tab 2: Table Schema Inspector
  // --------------------------------------------------------------------------

  Widget _buildSchemaTab(ThemeData theme) {
    if (_selectedTable == null) {
      return const Center(child: Text('No table selected.'));
    }

    final cols = _selectedTable!.columns;

    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Columns in "${_selectedTable!.name}"',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            Text(
              '${cols.length} Columns',
              style: TextStyle(
                fontSize: 12,
                color: theme.textTheme.bodySmall?.color?.withOpacity(0.6),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ...cols.map((col) {
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: col.isPrimaryKey
                    ? Colors.amber.withOpacity(0.4)
                    : theme.dividerColor.withOpacity(0.06),
              ),
            ),
            child: Row(
              children: [
                if (col.isPrimaryKey)
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.amber.withOpacity(0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.key, size: 16, color: Colors.amber),
                  )
                else
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withOpacity(0.08),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.tag, size: 16, color: theme.colorScheme.primary),
                  ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            col.name,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13.5,
                            ),
                          ),
                          if (col.isPrimaryKey) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: Colors.amber.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'PRIMARY KEY',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.amber,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Text(
                            col.type,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                          if (col.notNull) ...[
                            const SizedBox(width: 8),
                            const Text(
                              'NOT NULL',
                              style: TextStyle(fontSize: 10, color: Colors.redAccent),
                            ),
                          ],
                          if (col.defaultValue != null) ...[
                            const SizedBox(width: 8),
                            Text(
                              'Default: ${col.defaultValue}',
                              style: TextStyle(
                                fontSize: 10,
                                color: theme.textTheme.bodySmall?.color?.withOpacity(0.5),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  // --------------------------------------------------------------------------
  // Tab 3: Safe Read-Only SQL Console
  // --------------------------------------------------------------------------

  Widget _buildSqlConsoleTab(ThemeData theme) {
    return Column(
      children: [
        // SQL Input Box
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _sqlController,
                maxLines: 4,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5),
                decoration: InputDecoration(
                  hintText: 'Enter read-only SQL query (e.g. SELECT * FROM ...)',
                  filled: true,
                  fillColor: theme.colorScheme.surfaceVariant.withOpacity(0.25),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: theme.dividerColor.withOpacity(0.1)),
                  ),
                  contentPadding: const EdgeInsets.all(12),
                ),
              ),
              const SizedBox(height: 8),

              // Run button & query stats
              Row(
                children: [
                  FilledButton.icon(
                    onPressed: _isExecutingQuery ? null : _executeCustomSql,
                    icon: _isExecutingQuery
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.play_arrow, size: 18),
                    label: const Text('Run Query'),
                    style: FilledButton.styleFrom(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    ),
                  ),
                  const SizedBox(width: 12),
                  if (_queryTimeMs != null && _queryRowCount != null)
                    Expanded(
                      child: Text(
                        '$_queryRowCount rows in ${_queryTimeMs}ms',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: Colors.green.shade700,
                        ),
                      ),
                    ),
                  if (_queryRows.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.file_download_outlined, size: 20),
                      tooltip: 'Export Query Result to CSV',
                      onPressed: () => _exportToCsv(
                        title: 'sql_query_result',
                        columns: _queryColumns,
                        rows: _queryRows,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),

        // Quick snippets chips
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            children: [
              _buildSqlSnippetChip('SELECT * LIMIT 25', () {
                if (_selectedTable != null) {
                  _sqlController.text = 'SELECT * FROM "${_selectedTable!.name}" LIMIT 25;';
                  _executeCustomSql();
                }
              }),
              _buildSqlSnippetChip('COUNT(*)', () {
                if (_selectedTable != null) {
                  _sqlController.text = 'SELECT count(*) as total_rows FROM "${_selectedTable!.name}";';
                  _executeCustomSql();
                }
              }),
              _buildSqlSnippetChip('PRAGMA table_info', () {
                if (_selectedTable != null) {
                  _sqlController.text = 'PRAGMA table_info("${_selectedTable!.name}");';
                  _executeCustomSql();
                }
              }),
              _buildSqlSnippetChip('All Tables', () {
                _sqlController.text = "SELECT name, type FROM sqlite_master WHERE type='table' ORDER BY name;";
                _executeCustomSql();
              }),
            ],
          ),
        ),

        const Divider(height: 16),

        // Query Output area
        Expanded(
          child: _queryError != null
              ? Padding(
                  padding: const EdgeInsets.all(16),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.redAccent.withOpacity(0.3)),
                    ),
                    child: Text(
                      _queryError!,
                      style: const TextStyle(
                        color: Colors.redAccent,
                        fontSize: 12,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                )
              : _queryRows.isEmpty
                  ? Center(
                      child: Text(
                        _isExecutingQuery
                            ? 'Executing query...'
                            : 'Execute a SELECT or PRAGMA query to view results.',
                        style: const TextStyle(fontSize: 12.5, color: Colors.grey),
                      ),
                    )
                  : SingleChildScrollView(
                      scrollDirection: Axis.vertical,
                      physics: const BouncingScrollPhysics(),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        physics: const BouncingScrollPhysics(),
                        child: DataTable(
                          columnSpacing: 20,
                          headingRowHeight: 38,
                          dataRowMinHeight: 36,
                          dataRowMaxHeight: 40,
                          columns: _queryColumns
                              .map((c) => DataColumn(
                                    label: Text(
                                      c,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ))
                              .toList(),
                          rows: _queryRows.map((r) {
                            return DataRow(
                              cells: List.generate(r.length, (idx) {
                                final val = r[idx];
                                return DataCell(
                                  InkWell(
                                    onTap: () => _showCellDetails(_queryColumns[idx], val),
                                    child: Container(
                                      constraints: const BoxConstraints(maxWidth: 200),
                                      child: Text(
                                        val == null ? 'NULL' : val.toString(),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          fontStyle: val == null ? FontStyle.italic : null,
                                          color: val == null ? Colors.grey : null,
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              }),
                            );
                          }).toList(),
                        ),
                      ),
                    ),
        ),
      ],
    );
  }

  Widget _buildSqlSnippetChip(String label, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ActionChip(
        label: Text(label, style: const TextStyle(fontSize: 11)),
        onPressed: onTap,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      ),
    );
  }
}
