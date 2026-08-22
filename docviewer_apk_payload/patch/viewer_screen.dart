import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:doc_viewer/doc_viewer.dart';
import 'package:docx_file_viewer/docx_file_viewer.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';
import 'package:two_dimensional_scrollables/two_dimensional_scrollables.dart';
import 'package:xml/xml.dart';

import '../models/document_item.dart';
import '../services/reading_progress_service.dart';

// Excel.decodeBytes is intentionally replaced by the internal XLSX parser below.

class ViewerScreen extends StatelessWidget {
  final DocumentItem item;
  const ViewerScreen({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    final typeColor = _kindColor(item.kind);
    final isDocx =
        item.kind == DocumentKind.word && item.extension.toLowerCase() == 'docx';
    return Scaffold(
      backgroundColor: isDocx
          ? const Color(0xFFE9EDF4)
          : Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            Text(
              item.extension.toUpperCase(),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: typeColor,
                    fontWeight: FontWeight.w800,
                  ),
            ),
          ],
        ),
      ),
      body: _buildViewer(context),
    );
  }

  Widget _buildViewer(BuildContext context) {
    if (item.kind == DocumentKind.pdf) {
      return _PdfReader(item: item);
    }
    if (item.kind == DocumentKind.word &&
        item.extension.toLowerCase() == 'docx') {
      return _DocxViewer(item: item);
    }
    if (item.kind == DocumentKind.excel) {
      return _ExcelViewer(item: item);
    }
    if (item.kind == DocumentKind.word ||
        item.kind == DocumentKind.powerpoint) {
      return _OfficeViewer(item: item);
    }
    if (item.kind == DocumentKind.text) {
      return _TextViewer(path: item.path);
    }
    return const _ViewerMessage(
      icon: Icons.error_outline_rounded,
      title: 'هذا النوع غير مدعوم',
      message: 'لا يمكن معاينة هذا المستند داخل التطبيق.',
    );
  }

  static Color _kindColor(DocumentKind kind) => switch (kind) {
        DocumentKind.pdf => const Color(0xFFE53935),
        DocumentKind.word => const Color(0xFF2472E8),
        DocumentKind.excel => const Color(0xFF168A4A),
        DocumentKind.powerpoint => const Color(0xFFF26522),
        DocumentKind.text => const Color(0xFF008C95),
        DocumentKind.other => const Color(0xFF667085),
      };
}

class _PdfReader extends StatefulWidget {
  final DocumentItem item;
  const _PdfReader({required this.item});

  @override
  State<_PdfReader> createState() => _PdfReaderState();
}

class _PdfReaderState extends State<_PdfReader> {
  late final Future<int> _initialPage =
      ReadingProgressService.instance.pdfPage(widget.item.path);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<int>(
      future: _initialPage,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        return PdfViewer.file(
          widget.item.path,
          initialPageNumber: snapshot.data!,
          params: PdfViewerParams(
            onPageChanged: (page) {
              if (page != null) {
                unawaited(
                  ReadingProgressService.instance
                      .savePdfPage(widget.item.path, page),
                );
              }
            },
          ),
        );
      },
    );
  }
}

class _DocxViewer extends StatefulWidget {
  final DocumentItem item;
  const _DocxViewer({required this.item});

  @override
  State<_DocxViewer> createState() => _DocxViewerState();
}

class _DocxViewerState extends State<_DocxViewer> {
  final DocxSearchController _searchController = DocxSearchController();
  final TextEditingController _searchText = TextEditingController();
  final ScrollController _documentScroll = ScrollController();
  bool _paged = true;
  bool _showSearch = false;
  bool _positionRestored = false;
  Timer? _saveTimer;

  @override
  void initState() {
    super.initState();
    _documentScroll.addListener(_scheduleProgressSave);
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _saveCurrentPosition();
    _documentScroll
      ..removeListener(_scheduleProgressSave)
      ..dispose();
    _searchText.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _scheduleProgressSave() {
    if (!_positionRestored) return;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 350), _saveCurrentPosition);
  }

  void _saveCurrentPosition() {
    if (!_documentScroll.hasClients || !_positionRestored) return;
    unawaited(
      ReadingProgressService.instance.saveDocxOffset(
        widget.item.path,
        _documentScroll.offset,
      ),
    );
  }

  Future<void> _restorePosition() async {
    if (_positionRestored) return;
    final saved =
        await ReadingProgressService.instance.docxOffset(widget.item.path);
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_documentScroll.hasClients) return;
      final max = _documentScroll.position.maxScrollExtent;
      _documentScroll.jumpTo(saved.clamp(0.0, max));
      _positionRestored = true;
    });
  }

  void _toggleSearch() {
    setState(() {
      _showSearch = !_showSearch;
      if (!_showSearch) {
        _searchText.clear();
        _searchController.clear();
      }
    });
  }

  void _setPageMode(bool paged) {
    if (_paged == paged) return;
    _saveCurrentPosition();
    setState(() {
      _paged = paged;
      _positionRestored = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Material(
          color: scheme.surface,
          child: Column(
            children: [
              SizedBox(
                height: 52,
                child: Row(
                  children: [
                    const SizedBox(width: 12),
                    _ModeChip(
                      icon: Icons.auto_stories_rounded,
                      label: 'صفحات',
                      selected: _paged,
                      onTap: () => _setPageMode(true),
                    ),
                    const SizedBox(width: 8),
                    _ModeChip(
                      icon: Icons.view_agenda_outlined,
                      label: 'قراءة',
                      selected: !_paged,
                      onTap: () => _setPageMode(false),
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: 'بحث داخل المستند',
                      onPressed: _toggleSearch,
                      icon: Icon(
                        _showSearch ? Icons.close_rounded : Icons.search_rounded,
                      ),
                    ),
                    PopupMenuButton<String>(
                      tooltip: 'خيارات العرض',
                      onSelected: (value) {
                        if (value == 'paged') _setPageMode(true);
                        if (value == 'reading') _setPageMode(false);
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                          value: 'paged',
                          child: Text('عرض الصفحات الأصلية'),
                        ),
                        PopupMenuItem(
                          value: 'reading',
                          child: Text('وضع القراءة المستمر'),
                        ),
                      ],
                    ),
                    const SizedBox(width: 4),
                  ],
                ),
              ),
              if (_showSearch)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _searchText,
                          autofocus: true,
                          textInputAction: TextInputAction.search,
                          decoration: InputDecoration(
                            hintText: 'ابحث داخل ملف Word…',
                            prefixIcon: const Icon(Icons.search_rounded),
                            filled: true,
                            fillColor: scheme.surfaceContainerHighest
                                .withValues(alpha: .55),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide.none,
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                          ),
                          onChanged: _searchController.search,
                        ),
                      ),
                      const SizedBox(width: 8),
                      AnimatedBuilder(
                        animation: _searchController,
                        builder: (context, _) {
                          final count = _searchController.matchCount;
                          final current = count == 0
                              ? 0
                              : _searchController.currentMatchIndex + 1;
                          return Row(
                            children: [
                              Text(
                                '$current/$count',
                                style: Theme.of(context).textTheme.labelMedium,
                              ),
                              IconButton(
                                tooltip: 'السابق',
                                onPressed: count == 0
                                    ? null
                                    : _searchController.previousMatch,
                                icon: const Icon(Icons.keyboard_arrow_up_rounded),
                              ),
                              IconButton(
                                tooltip: 'التالي',
                                onPressed: count == 0
                                    ? null
                                    : _searchController.nextMatch,
                                icon:
                                    const Icon(Icons.keyboard_arrow_down_rounded),
                              ),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: ColoredBox(
            color: _paged ? const Color(0xFFE9EDF4) : Colors.white,
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: DocxView(
                key: ValueKey<bool>(_paged),
                file: File(widget.item.path),
                searchController: _searchController,
                scrollController: _documentScroll,
                onLoaded: _restorePosition,
                config: DocxViewConfig(
                  pageMode:
                      _paged ? DocxPageMode.paged : DocxPageMode.continuous,
                  enableZoom: true,
                  enableSearch: true,
                  enableSelection: true,
                  minScale: 0.45,
                  maxScale: 4.0,
                  showPageBreaks: _paged,
                  showDebugInfo: false,
                  padding: EdgeInsets.symmetric(
                    horizontal: _paged ? 10 : 18,
                    vertical: _paged ? 14 : 20,
                  ),
                  backgroundColor:
                      _paged ? const Color(0xFFE9EDF4) : Colors.white,
                  searchHighlightColor: const Color(0xFFFFEB75),
                  currentSearchHighlightColor: const Color(0xFFFFB74D),
                  theme: DocxViewTheme.light(),
                  customFontFallbacks: const [
                    'Calibri',
                    'Carlito',
                    'Arial',
                    'Liberation Sans',
                    'Times New Roman',
                    'Noto Sans',
                    'Roboto',
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ExcelViewer extends StatefulWidget {
  final DocumentItem item;
  const _ExcelViewer({required this.item});

  @override
  State<_ExcelViewer> createState() => _ExcelViewerState();
}

class _ExcelViewerState extends State<_ExcelViewer> {
  static const int _maxSafeBytes = 96 * 1024 * 1024;
  late final Future<_XlsxWorkbook> _workbook = _loadWorkbook();

  Future<_XlsxWorkbook> _loadWorkbook() async {
    if (widget.item.extension.toLowerCase() == 'xls') {
      throw UnsupportedError(
        'ملفات XLS القديمة تستخدم تنسيقًا ثنائيًا مختلفًا. افتح أو احفظ الملف بصيغة XLSX لعرضه داخل التطبيق.',
      );
    }
    final file = File(widget.item.path);
    if (!await file.exists()) {
      throw StateError('الملف لم يعد موجودًا في موقعه الحالي.');
    }
    final size = await file.length();
    if (size > _maxSafeBytes) {
      throw StateError(
        'ملف Excel أكبر من 96 MB. تم إيقاف المعاينة لحماية ذاكرة الهاتف.',
      );
    }
    final bytes = await file.readAsBytes();
    return Isolate.run(() => _decodeXlsx(bytes));
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_XlsxWorkbook>(
      future: _workbook,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const _LoadingDocument(
            icon: Icons.table_chart_rounded,
            title: 'جارٍ تجهيز ملف Excel',
            message: 'يتم تحليل أوراق العمل بأمان في الخلفية…',
          );
        }
        if (snapshot.hasError) {
          return _ViewerMessage(
            icon: Icons.table_chart_outlined,
            title: 'تعذر فتح ملف Excel',
            message:
                'بقي التطبيق يعمل ولم يحدث Crash. قد يكون الملف تالفًا أو محميًا أو بصيغة XLS قديمة.\n\n${_friendlyError(snapshot.error)}',
          );
        }
        final workbook = snapshot.data!;
        return _ExcelWorkbook(workbook: workbook);
      },
    );
  }

  String _friendlyError(Object? error) {
    if (error == null) return '';
    final value = error.toString()
        .replaceFirst('Bad state: ', '')
        .replaceFirst('Unsupported operation: ', '');
    if (value.length <= 220) return value;
    return '${value.substring(0, 220)}…';
  }
}

class _ExcelWorkbook extends StatefulWidget {
  final _XlsxWorkbook workbook;
  const _ExcelWorkbook({required this.workbook});

  @override
  State<_ExcelWorkbook> createState() => _ExcelWorkbookState();
}

class _ExcelWorkbookState extends State<_ExcelWorkbook> {
  late int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final sheet = widget.workbook.sheets[_selectedIndex];
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Material(
          color: scheme.surface,
          child: SizedBox(
            height: 50,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              scrollDirection: Axis.horizontal,
              itemCount: widget.workbook.sheets.length,
              separatorBuilder: (_, __) => const SizedBox(width: 7),
              itemBuilder: (_, index) {
                final current = widget.workbook.sheets[index];
                final selected = index == _selectedIndex;
                return ChoiceChip(
                  selected: selected,
                  avatar: Icon(
                    Icons.grid_on_rounded,
                    size: 16,
                    color: selected ? scheme.primary : scheme.onSurfaceVariant,
                  ),
                  label: Text(current.name),
                  onSelected: (_) => setState(() => _selectedIndex = index),
                );
              },
            ),
          ),
        ),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          color: scheme.surfaceContainerLow,
          child: Row(
            children: [
              const Icon(Icons.table_rows_rounded, size: 17),
              const SizedBox(width: 7),
              Text(
                '${sheet.maxRows} صف × ${sheet.maxColumns} عمود',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
              const Spacer(),
              Text(
                'XLSX • عرض آمن',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: const Color(0xFF168A4A),
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ],
          ),
        ),
        Expanded(child: _ExcelGrid(sheet: sheet)),
      ],
    );
  }
}

class _ExcelGrid extends StatelessWidget {
  final _XlsxSheet sheet;
  const _ExcelGrid({required this.sheet});

  @override
  Widget build(BuildContext context) {
    final rowCount = sheet.maxRows + 1;
    final columnCount = sheet.maxColumns + 1;
    return Directionality(
      textDirection: sheet.isRtl ? TextDirection.rtl : TextDirection.ltr,
      child: TableView(
        diagonalDragBehavior: DiagonalDragBehavior.free,
        delegate: TableCellBuilderDelegate(
          rowCount: rowCount,
          columnCount: columnCount,
          pinnedRowCount: 1,
          pinnedColumnCount: 1,
          addAutomaticKeepAlives: false,
          columnBuilder: (index) => TableSpan(
            extent: FixedTableSpanExtent(_columnWidth(index)),
          ),
          rowBuilder: (index) => TableSpan(
            extent: FixedTableSpanExtent(_rowHeight(index)),
          ),
          cellBuilder: (context, vicinity) {
            return TableViewCell(
              child: _buildCell(context, vicinity.row, vicinity.column),
            );
          },
        ),
      ),
    );
  }

  double _columnWidth(int displayColumn) {
    if (displayColumn == 0) return 50;
    final raw = sheet.columnWidths[displayColumn - 1] ?? 12.0;
    return (raw * 7.0 + 18).clamp(80.0, 280.0);
  }

  double _rowHeight(int displayRow) {
    if (displayRow == 0) return 38;
    final raw = sheet.rowHeights[displayRow - 1] ?? 20.0;
    return (raw * 1.34).clamp(34.0, 120.0);
  }

  Widget _buildCell(BuildContext context, int row, int column) {
    final scheme = Theme.of(context).colorScheme;
    if (row == 0 && column == 0) {
      return _ExcelHeaderCell(
        color: scheme.surfaceContainerHighest,
        child: const Icon(Icons.grid_4x4_rounded, size: 17),
      );
    }
    if (row == 0) {
      return _ExcelHeaderCell(
        color: scheme.surfaceContainerHighest,
        child: Text(
          _columnLabel(column - 1),
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      );
    }
    if (column == 0) {
      return _ExcelHeaderCell(
        color: scheme.surfaceContainerHighest,
        child: Text(
          '$row',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      );
    }

    final value = sheet.cells[row - 1]?[column - 1] ?? '';
    return Container(
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(
          right: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: .55),
          ),
          bottom: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: .55),
          ),
        ),
      ),
      child: SelectableText(
        value,
        maxLines: 4,
        style: const TextStyle(fontSize: 12.5),
      ),
    );
  }

  String _columnLabel(int index) {
    var value = index + 1;
    final chars = <int>[];
    while (value > 0) {
      value--;
      chars.add(65 + value % 26);
      value ~/= 26;
    }
    return String.fromCharCodes(chars.reversed);
  }
}

class _ExcelHeaderCell extends StatelessWidget {
  final Color color;
  final Widget child;
  const _ExcelHeaderCell({required this.color, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color,
        border: Border(
          right: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
          bottom: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
        ),
      ),
      child: child,
    );
  }
}

class _LoadingDocument extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  const _LoadingDocument({
    required this.icon,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 50, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 18),
            const CircularProgressIndicator(),
            const SizedBox(height: 18),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 7),
            Text(message, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class _ModeChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ModeChip({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? scheme.primaryContainer : scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? scheme.primary.withValues(alpha: .28)
                : scheme.outlineVariant.withValues(alpha: .45),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 18,
              color: selected ? scheme.primary : scheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: selected ? scheme.primary : scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OfficeViewer extends StatelessWidget {
  final DocumentItem item;
  const _OfficeViewer({required this.item});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Theme.of(context).colorScheme.surface,
      child: DocViewerView(
        filePath: item.path,
        darkMode: Theme.of(context).brightness == Brightness.dark,
        missingFileBuilder: (_) => const _ViewerMessage(
          icon: Icons.file_present_outlined,
          title: 'الملف غير موجود',
          message: 'تعذر العثور على المستند في موقعه الحالي.',
        ),
        unsupportedBuilder: (_) => const _ViewerMessage(
          icon: Icons.description_outlined,
          title: 'تعذرت المعاينة',
          message: 'هذا الملف غير مدعوم بواسطة عارض Office على هذا الجهاز.',
        ),
      ),
    );
  }
}

class _TextViewer extends StatefulWidget {
  final String path;
  const _TextViewer({required this.path});

  @override
  State<_TextViewer> createState() => _TextViewerState();
}

class _TextViewerState extends State<_TextViewer> {
  late final Future<String> _content = _load();

  Future<String> _load() async {
    final file = File(widget.path);
    final length = await file.length();
    if (length > 8 * 1024 * 1024) {
      return 'الملف النصي أكبر من 8 MB، لذلك تم إيقاف المعاينة لحماية ذاكرة الهاتف.';
    }
    final bytes = await file.readAsBytes();
    return utf8.decode(bytes, allowMalformed: true);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<String>(
        future: _content,
        builder: (context, snap) {
          if (snap.hasError) {
            return _ViewerMessage(
              icon: Icons.error_outline_rounded,
              title: 'تعذرت قراءة الملف',
              message: '${snap.error}',
            );
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          return SelectionArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: SizedBox(width: double.infinity, child: Text(snap.data!)),
            ),
          );
        },
      );
}

class _ViewerMessage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  const _ViewerMessage({
    required this.icon,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 54, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 14),
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      );
}

class _XlsxWorkbook {
  final List<_XlsxSheet> sheets;
  const _XlsxWorkbook(this.sheets);
}

class _XlsxSheet {
  final String name;
  final int maxRows;
  final int maxColumns;
  final bool isRtl;
  final Map<int, Map<int, String>> cells;
  final Map<int, double> columnWidths;
  final Map<int, double> rowHeights;

  const _XlsxSheet({
    required this.name,
    required this.maxRows,
    required this.maxColumns,
    required this.isRtl,
    required this.cells,
    required this.columnWidths,
    required this.rowHeights,
  });
}

_XlsxWorkbook _decodeXlsx(Uint8List bytes) {
  if (bytes.length < 4 ||
      bytes[0] != 0x50 ||
      bytes[1] != 0x4B ||
      bytes[2] != 0x03 ||
      bytes[3] != 0x04) {
    throw const FormatException(
      'هذه ليست حزمة XLSX حديثة. ملفات XLS القديمة لا تُعرض في العارض الآمن الحالي.',
    );
  }

  final archive = ZipDecoder().decodeBytes(bytes, verify: true);
  final workbook = _xlsxXml(archive, 'xl/workbook.xml');
  final relationships = _xlsxXml(archive, 'xl/_rels/workbook.xml.rels');
  final sharedStrings = _xlsxSharedStrings(archive);

  final relationTargets = <String, String>{};
  for (final rel in relationships.descendants.whereType<XmlElement>()) {
    if (rel.name.local != 'Relationship') continue;
    final id = _xlsxAttr(rel, 'Id');
    final target = _xlsxAttr(rel, 'Target');
    if (id == null || target == null) continue;
    relationTargets[id] = _xlsxResolveTarget(target);
  }

  final sheets = <_XlsxSheet>[];
  for (final node in workbook.descendants.whereType<XmlElement>()) {
    if (node.name.local != 'sheet') continue;
    final name = _xlsxAttr(node, 'name') ?? 'Sheet ${sheets.length + 1}';
    final relationId = _xlsxAttr(node, 'id');
    if (relationId == null) continue;
    final target = relationTargets[relationId];
    if (target == null) continue;
    final sheetXml = _xlsxXml(archive, target);
    sheets.add(_xlsxParseSheet(name, sheetXml, sharedStrings));
  }

  if (sheets.isEmpty) {
    throw const FormatException('لم يتم العثور على أوراق عمل قابلة للقراءة داخل الملف.');
  }
  return _XlsxWorkbook(List.unmodifiable(sheets));
}

_XlsxSheet _xlsxParseSheet(
  String name,
  XmlDocument document,
  List<String> sharedStrings,
) {
  final cells = <int, Map<int, String>>{};
  final widths = <int, double>{};
  final heights = <int, double>{};
  var maxRow = 0;
  var maxColumn = 0;
  var isRtl = false;

  for (final node in document.descendants.whereType<XmlElement>()) {
    if (node.name.local == 'sheetView') {
      final rtl = _xlsxAttr(node, 'rightToLeft');
      if (rtl == '1' || rtl?.toLowerCase() == 'true') isRtl = true;
      continue;
    }
    if (node.name.local == 'col') {
      final min = int.tryParse(_xlsxAttr(node, 'min') ?? '');
      final max = int.tryParse(_xlsxAttr(node, 'max') ?? '');
      final width = double.tryParse(_xlsxAttr(node, 'width') ?? '');
      if (min != null && max != null && width != null) {
        for (var col = min - 1; col <= max - 1 && col < 16384; col++) {
          widths[col] = width;
        }
      }
      continue;
    }
    if (node.name.local == 'row') {
      final rowNumber = int.tryParse(_xlsxAttr(node, 'r') ?? '');
      final height = double.tryParse(_xlsxAttr(node, 'ht') ?? '');
      if (rowNumber != null && height != null) {
        heights[rowNumber - 1] = height;
      }
      continue;
    }
    if (node.name.local != 'c') continue;

    final reference = _xlsxAttr(node, 'r');
    if (reference == null) continue;
    final coordinate = _xlsxCoordinate(reference);
    if (coordinate == null) continue;
    final row = coordinate.$1;
    final column = coordinate.$2;
    final value = _xlsxCellValue(node, sharedStrings);
    if (value.isNotEmpty) {
      (cells[row] ??= <int, String>{})[column] = value;
    }
    if (row + 1 > maxRow) maxRow = row + 1;
    if (column + 1 > maxColumn) maxColumn = column + 1;
  }

  for (final dimension in document.descendants.whereType<XmlElement>()) {
    if (dimension.name.local != 'dimension') continue;
    final ref = _xlsxAttr(dimension, 'ref');
    if (ref == null) break;
    final last = ref.contains(':') ? ref.split(':').last : ref;
    final coordinate = _xlsxCoordinate(last);
    if (coordinate != null) {
      if (coordinate.$1 + 1 > maxRow) maxRow = coordinate.$1 + 1;
      if (coordinate.$2 + 1 > maxColumn) maxColumn = coordinate.$2 + 1;
    }
    break;
  }

  maxRow = maxRow.clamp(1, 1048576);
  maxColumn = maxColumn.clamp(1, 16384);

  return _XlsxSheet(
    name: name,
    maxRows: maxRow,
    maxColumns: maxColumn,
    isRtl: isRtl,
    cells: cells,
    columnWidths: widths,
    rowHeights: heights,
  );
}

String _xlsxCellValue(XmlElement cell, List<String> sharedStrings) {
  final type = _xlsxAttr(cell, 't');
  if (type == 'inlineStr') {
    return cell.descendants
        .whereType<XmlElement>()
        .where((e) => e.name.local == 't')
        .map((e) => e.innerText)
        .join();
  }

  String raw = '';
  for (final child in cell.children.whereType<XmlElement>()) {
    if (child.name.local == 'v') {
      raw = child.innerText;
      break;
    }
  }

  if (type == 's') {
    final index = int.tryParse(raw);
    if (index != null && index >= 0 && index < sharedStrings.length) {
      return sharedStrings[index];
    }
  }
  if (type == 'b') return raw == '1' ? 'TRUE' : 'FALSE';
  return raw;
}

List<String> _xlsxSharedStrings(Archive archive) {
  final file = _xlsxFind(archive, 'xl/sharedStrings.xml');
  if (file == null) return const [];
  final bytes = file.readBytes();
  if (bytes == null) return const [];
  final document = XmlDocument.parse(utf8.decode(bytes, allowMalformed: true));
  return document.descendants
      .whereType<XmlElement>()
      .where((e) => e.name.local == 'si')
      .map(
        (si) => si.descendants
            .whereType<XmlElement>()
            .where((e) => e.name.local == 't')
            .map((t) => t.innerText)
            .join(),
      )
      .toList(growable: false);
}

XmlDocument _xlsxXml(Archive archive, String name) {
  final file = _xlsxFind(archive, name);
  if (file == null) throw FormatException('جزء XLSX مفقود: $name');
  final bytes = file.readBytes();
  if (bytes == null) throw FormatException('تعذر قراءة جزء XLSX: $name');
  return XmlDocument.parse(utf8.decode(bytes, allowMalformed: true));
}

ArchiveFile? _xlsxFind(Archive archive, String name) {
  final normalized = p.posix.normalize(name).replaceFirst(RegExp(r'^/'), '');
  for (final file in archive.files) {
    if (p.posix.normalize(file.name).replaceFirst(RegExp(r'^/'), '') ==
        normalized) {
      return file;
    }
  }
  return null;
}

String _xlsxResolveTarget(String target) {
  var value = target.replaceAll('\\', '/');
  if (value.startsWith('/')) value = value.substring(1);
  if (value.startsWith('xl/')) return p.posix.normalize(value);
  return p.posix.normalize(p.posix.join('xl', value));
}

String? _xlsxAttr(XmlElement element, String localName) {
  for (final attribute in element.attributes) {
    if (attribute.name.local == localName) return attribute.value;
  }
  return null;
}

(int, int)? _xlsxCoordinate(String reference) {
  final match = RegExp(r'^([A-Za-z]+)([0-9]+)').firstMatch(reference);
  if (match == null) return null;
  final letters = match.group(1)!.toUpperCase();
  final rowNumber = int.tryParse(match.group(2)!);
  if (rowNumber == null || rowNumber < 1) return null;
  var column = 0;
  for (final unit in letters.codeUnits) {
    column = column * 26 + (unit - 64);
  }
  if (column < 1) return null;
  return (rowNumber - 1, column - 1);
}
