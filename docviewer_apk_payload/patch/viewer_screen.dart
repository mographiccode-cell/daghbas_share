import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:doc_viewer/doc_viewer.dart';
import 'package:docx_file_viewer/docx_file_viewer.dart';
import 'package:excel_plus/excel_plus.dart';
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:two_dimensional_scrollables/two_dimensional_scrollables.dart';

import '../models/document_item.dart';
import '../services/reading_progress_service.dart';

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
  late final Future<Excel> _workbook = _loadWorkbook();

  Future<Excel> _loadWorkbook() async {
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
    return Excel.decodeBytesAsync(bytes);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Excel>(
      future: _workbook,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const _LoadingDocument(
            icon: Icons.table_chart_rounded,
            title: 'جارٍ تجهيز ملف Excel',
            message: 'يتم تحليل أوراق العمل في الخلفية…',
          );
        }
        if (snapshot.hasError) {
          return _ViewerMessage(
            icon: Icons.table_chart_outlined,
            title: 'تعذر فتح ملف Excel',
            message:
                'لم يتم إغلاق التطبيق. قد يكون الملف تالفًا أو محميًا بكلمة مرور أو بصيغة Excel قديمة غير مدعومة بالكامل.\n\n${_friendlyError(snapshot.error)}',
          );
        }
        final workbook = snapshot.data!;
        if (workbook.tables.isEmpty) {
          return const _ViewerMessage(
            icon: Icons.grid_off_rounded,
            title: 'مصنف فارغ',
            message: 'لم يتم العثور على أي أوراق عمل داخل الملف.',
          );
        }
        return _ExcelWorkbook(workbook: workbook);
      },
    );
  }

  String _friendlyError(Object? error) {
    if (error == null) return '';
    final value = error.toString();
    if (value.length <= 180) return value;
    return '${value.substring(0, 180)}…';
  }
}

class _ExcelWorkbook extends StatefulWidget {
  final Excel workbook;
  const _ExcelWorkbook({required this.workbook});

  @override
  State<_ExcelWorkbook> createState() => _ExcelWorkbookState();
}

class _ExcelWorkbookState extends State<_ExcelWorkbook> {
  late final List<String> _sheetNames = widget.workbook.tables.keys.toList();
  late String _selected = _sheetNames.first;

  @override
  Widget build(BuildContext context) {
    final sheet = widget.workbook.tables[_selected]!;
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
              itemCount: _sheetNames.length,
              separatorBuilder: (_, __) => const SizedBox(width: 7),
              itemBuilder: (_, index) {
                final name = _sheetNames[index];
                final selected = name == _selected;
                return ChoiceChip(
                  selected: selected,
                  avatar: Icon(
                    Icons.grid_on_rounded,
                    size: 16,
                    color: selected ? scheme.primary : scheme.onSurfaceVariant,
                  ),
                  label: Text(name),
                  onSelected: (_) => setState(() => _selected = name),
                );
              },
            ),
          ),
        ),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          color: scheme.surfaceContainerLow,
          child: Text(
            '${sheet.maxRows} صف × ${sheet.maxColumns} عمود',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
        ),
        Expanded(child: _ExcelGrid(sheet: sheet)),
      ],
    );
  }
}

class _ExcelGrid extends StatelessWidget {
  final Sheet sheet;
  const _ExcelGrid({required this.sheet});

  @override
  Widget build(BuildContext context) {
    final rowCount = sheet.maxRows + 1;
    final columnCount = sheet.maxColumns + 1;
    return Directionality(
      textDirection: sheet.isRTL ? TextDirection.rtl : TextDirection.ltr,
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
    final raw = sheet.getColumnWidth(displayColumn - 1);
    return (raw * 7.0 + 18).clamp(80.0, 280.0);
  }

  double _rowHeight(int displayRow) {
    if (displayRow == 0) return 38;
    final raw = sheet.getRowHeight(displayRow - 1);
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

    final dataRow = sheet.row(row - 1);
    final Data? cell = column - 1 < dataRow.length ? dataRow[column - 1] : null;
    final style = cell?.cellStyle;
    final background = _excelColor(style?.backgroundColor) ?? scheme.surface;
    final foreground = _excelColor(style?.fontColor) ?? scheme.onSurface;
    final alignment = switch (style?.horizontalAlignment) {
      HorizontalAlign.Center => TextAlign.center,
      HorizontalAlign.Right => TextAlign.right,
      _ => TextAlign.left,
    };

    return Container(
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: background,
        border: Border(
          right: BorderSide(color: scheme.outlineVariant.withValues(alpha: .55)),
          bottom: BorderSide(color: scheme.outlineVariant.withValues(alpha: .55)),
        ),
      ),
      child: Text(
        cell?.value?.toString() ?? '',
        maxLines: 4,
        overflow: TextOverflow.ellipsis,
        textAlign: alignment,
        style: TextStyle(
          color: foreground,
          fontSize: (style?.fontSize ?? 12).toDouble().clamp(9, 22),
          fontWeight: style?.isBold == true ? FontWeight.w700 : FontWeight.w400,
          fontStyle: style?.isItalic == true ? FontStyle.italic : FontStyle.normal,
        ),
      ),
    );
  }

  Color? _excelColor(ExcelColor? value) {
    if (value == null) return null;
    var hex = value.colorHex.replaceAll('#', '').trim();
    if (hex.isEmpty || hex.toLowerCase() == 'none') return null;
    try {
      if (hex.length == 6) hex = 'FF$hex';
      if (hex.length != 8) return null;
      return Color(int.parse(hex, radix: 16));
    } catch (_) {
      return null;
    }
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
