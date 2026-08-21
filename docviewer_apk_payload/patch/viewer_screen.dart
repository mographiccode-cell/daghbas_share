import 'dart:convert';
import 'dart:io';

import 'package:doc_viewer/doc_viewer.dart';
import 'package:docx_file_viewer/docx_file_viewer.dart';
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import '../models/document_item.dart';

class ViewerScreen extends StatelessWidget {
  final DocumentItem item;
  const ViewerScreen({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    final typeColor = _kindColor(item.kind);
    final isDocx = item.kind == DocumentKind.word && item.extension.toLowerCase() == 'docx';
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
      return PdfViewer.file(item.path);
    }
    if (item.kind == DocumentKind.word && item.extension.toLowerCase() == 'docx') {
      return _DocxViewer(item: item);
    }
    if (item.kind == DocumentKind.word ||
        item.kind == DocumentKind.excel ||
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

class _DocxViewer extends StatefulWidget {
  final DocumentItem item;
  const _DocxViewer({required this.item});

  @override
  State<_DocxViewer> createState() => _DocxViewerState();
}

class _DocxViewerState extends State<_DocxViewer> {
  final DocxSearchController _searchController = DocxSearchController();
  final TextEditingController _searchText = TextEditingController();
  bool _paged = true;
  bool _showSearch = false;

  @override
  void dispose() {
    _searchText.dispose();
    _searchController.dispose();
    super.dispose();
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
                      onTap: () => setState(() => _paged = true),
                    ),
                    const SizedBox(width: 8),
                    _ModeChip(
                      icon: Icons.view_agenda_outlined,
                      label: 'قراءة',
                      selected: !_paged,
                      onTap: () => setState(() => _paged = false),
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: 'بحث داخل المستند',
                      onPressed: _toggleSearch,
                      icon: Icon(_showSearch ? Icons.close_rounded : Icons.search_rounded),
                    ),
                    PopupMenuButton<String>(
                      tooltip: 'خيارات العرض',
                      onSelected: (value) {
                        if (value == 'paged') setState(() => _paged = true);
                        if (value == 'reading') setState(() => _paged = false);
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'paged', child: Text('عرض الصفحات الأصلية')),
                        PopupMenuItem(value: 'reading', child: Text('وضع القراءة المستمر')),
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
                            fillColor: scheme.surfaceContainerHighest.withValues(alpha: .55),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide.none,
                            ),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          ),
                          onChanged: _searchController.search,
                        ),
                      ),
                      const SizedBox(width: 8),
                      AnimatedBuilder(
                        animation: _searchController,
                        builder: (context, _) {
                          final count = _searchController.matchCount;
                          final current = count == 0 ? 0 : _searchController.currentMatchIndex + 1;
                          return Row(
                            children: [
                              Text('$current/$count', style: Theme.of(context).textTheme.labelMedium),
                              IconButton(
                                tooltip: 'السابق',
                                onPressed: count == 0 ? null : _searchController.previousMatch,
                                icon: const Icon(Icons.keyboard_arrow_up_rounded),
                              ),
                              IconButton(
                                tooltip: 'التالي',
                                onPressed: count == 0 ? null : _searchController.nextMatch,
                                icon: const Icon(Icons.keyboard_arrow_down_rounded),
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
                config: DocxViewConfig(
                  pageMode: _paged ? DocxPageMode.paged : DocxPageMode.continuous,
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
                  backgroundColor: _paged ? const Color(0xFFE9EDF4) : Colors.white,
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
            color: selected ? scheme.primary.withValues(alpha: .28) : scheme.outlineVariant.withValues(alpha: .45),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: selected ? scheme.primary : scheme.onSurfaceVariant),
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
  const _ViewerMessage({required this.icon, required this.title, required this.message});

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
