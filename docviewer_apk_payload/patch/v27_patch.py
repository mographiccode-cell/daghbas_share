from pathlib import Path
import re


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if old not in text:
        raise SystemExit(f'patch point not found: {label}')
    return text.replace(old, new, 1)


home = Path('lib/screens/home_screen.dart')
s = home.read_text()

s = replace_once(
    s,
    "import 'package:flutter/services.dart';\n",
    "import 'package:flutter/services.dart';\nimport 'package:path/path.dart' as p;\nimport 'package:shared_preferences/shared_preferences.dart';\n",
    'home imports',
)
s = replace_once(
    s,
    "import '../services/incoming_document_service.dart';\n",
    "import '../services/incoming_document_service.dart';\nimport '../services/reading_progress_service.dart';\n",
    'reading progress import',
)
s = replace_once(
    s,
    "  final search = TextEditingController();\n\n  List<DocumentItem> all = const [];\n",
    "  final search = TextEditingController();\n  final SharedPreferencesAsync _prefs = SharedPreferencesAsync();\n\n  List<DocumentItem> all = const [];\n  Set<String> _pinnedPaths = <String>{};\n  Set<String> _readLaterPaths = <String>{};\n  bool _gridMode = false;\n",
    'home fields',
)
s = replace_once(
    s,
    "  Future<void> _initialize() async {\n    await _load();\n",
    "  Future<void> _initialize() async {\n    await _loadUiPrefs();\n    await _load();\n",
    'initialize prefs',
)
load_block = """  Future<void> _load({bool pruneMissing = false}) async {
    if (pruneMissing) await db.removeMissing();
    final loaded = await db.getAll();
    if (mounted) setState(() => all = loaded);
  }
"""
extra_methods = load_block + r'''

  Future<void> _loadUiPrefs() async {
    final pinned = await _prefs.getStringList('ui.pinned_paths') ?? const <String>[];
    final readLater = await _prefs.getStringList('ui.read_later_paths') ?? const <String>[];
    final grid = await _prefs.getBool('ui.grid_mode') ?? false;
    if (!mounted) return;
    setState(() {
      _pinnedPaths = pinned.toSet();
      _readLaterPaths = readLater.toSet();
      _gridMode = grid;
    });
  }

  Future<void> _saveCollections() async {
    await _prefs.setStringList('ui.pinned_paths', _pinnedPaths.toList());
    await _prefs.setStringList('ui.read_later_paths', _readLaterPaths.toList());
  }

  Future<void> _setGridMode(bool value) async {
    setState(() => _gridMode = value);
    await _prefs.setBool('ui.grid_mode', value);
  }

  Future<void> _togglePinned(DocumentItem item) async {
    setState(() {
      if (!_pinnedPaths.add(item.path)) _pinnedPaths.remove(item.path);
    });
    await _saveCollections();
  }

  Future<void> _toggleReadLater(DocumentItem item) async {
    setState(() {
      if (!_readLaterPaths.add(item.path)) _readLaterPaths.remove(item.path);
    });
    await _saveCollections();
  }

  String _safeBaseName(String value) {
    final cleaned = value.trim().replaceAll(RegExp(r'[\\/:*?"<>|]'), ' ');
    return cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  Future<void> _renameItem(DocumentItem item) async {
    final controller = TextEditingController(text: p.basenameWithoutExtension(item.name));
    final requested = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('إعادة تسمية الملف'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 120,
          decoration: InputDecoration(
            labelText: 'اسم الملف',
            helperText: 'سيتم الاحتفاظ بالامتداد .${item.extension}',
          ),
          onSubmitted: (value) => Navigator.pop(dialogContext, value),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, controller.text), child: const Text('حفظ')),
        ],
      ),
    );
    controller.dispose();
    if (requested == null) return;
    final base = _safeBaseName(requested);
    if (base.isEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('اكتب اسمًا صالحًا للملف.')));
      return;
    }
    final extension = p.extension(item.path);
    final target = p.join(p.dirname(item.path), '$base$extension');
    if (target == item.path) return;
    try {
      if (await File(target).exists()) {
        throw StateError('يوجد ملف آخر بنفس الاسم في هذا المجلد.');
      }
      await File(item.path).rename(target);
      final fresh = await DocumentItem.fromPath(target);
      if (fresh == null) throw StateError('تم تغيير الاسم لكن تعذر تحديث فهرس المستند.');
      final updated = DocumentItem(
        path: fresh.path,
        name: fresh.name,
        extension: fresh.extension,
        size: fresh.size,
        modifiedAt: fresh.modifiedAt,
        lastOpenedAt: item.lastOpenedAt,
        isFavorite: item.isFavorite,
      );
      await db.removePath(item.path);
      await db.upsert(updated);
      await ReadingProgressService.instance.migratePath(item.path, target);
      if (_pinnedPaths.remove(item.path)) _pinnedPaths.add(target);
      if (_readLaterPaths.remove(item.path)) _readLaterPaths.add(target);
      await _saveCollections();
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تم تغيير الاسم إلى ${updated.name}')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر تغيير الاسم: ${e.toString().replaceFirst('Bad state: ', '')}')));
      }
    }
  }

  Future<void> _duplicateItem(DocumentItem item) async {
    try {
      final directory = p.dirname(item.path);
      final extension = p.extension(item.path);
      final base = p.basenameWithoutExtension(item.path);
      var candidate = p.join(directory, '$base - نسخة$extension');
      var number = 2;
      while (await File(candidate).exists()) {
        candidate = p.join(directory, '$base - نسخة $number$extension');
        number++;
      }
      await File(item.path).copy(candidate);
      final copy = await DocumentItem.fromPath(candidate);
      if (copy == null) throw StateError('تعذر فهرسة النسخة الجديدة.');
      await db.upsert(copy);
      await _load();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تم إنشاء ${copy.name}')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر نسخ الملف: $e')));
    }
  }

  Future<void> _deleteItem(DocumentItem item) async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('حذف الملف؟'),
            content: Text('سيتم حذف «${item.name}» من الهاتف. لا يمكن التراجع عن هذه العملية.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('إلغاء')),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('حذف'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;
    try {
      final file = File(item.path);
      if (await file.exists()) await file.delete();
      await db.removePath(item.path);
      await ReadingProgressService.instance.clear(item.path);
      _pinnedPaths.remove(item.path);
      _readLaterPaths.remove(item.path);
      await _saveCollections();
      await _load();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حذف الملف.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر حذف الملف: $e')));
    }
  }
'''
s = replace_once(s, load_block, extra_methods, 'file actions')

settings_method = r'''
  Future<void> _showSettings() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const _SheetIcon(icon: Icons.light_mode_rounded),
                title: const Text('المظهر الفاتح'),
                subtitle: const Text('التطبيق يعمل بالثيم الفاتح فقط'),
                trailing: const Icon(Icons.check_circle_rounded, color: Color(0xFF1F63E9)),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.grid_view_rounded),
                title: const Text('عرض الملفات كشبكة'),
                subtitle: const Text('يمكنك التبديل أيضًا من شاشة الملفات'),
                value: _gridMode,
                onChanged: (value) async {
                  await _setGridMode(value);
                  if (sheetContext.mounted) Navigator.pop(sheetContext);
                },
              ),
              ListTile(
                leading: const Icon(Icons.bookmark_added_outlined),
                title: const Text('متابعة القراءة مفعلة'),
                subtitle: const Text('PDF وWord يعودان تلقائيًا إلى آخر موضع تمت قراءته'),
              ),
              ListTile(
                leading: const Icon(Icons.privacy_tip_outlined),
                title: const Text('خصوصية محلية'),
                subtitle: const Text('لا يتم رفع مستنداتك إلى الإنترنت'),
              ),
              const Divider(),
              const ListTile(
                leading: Icon(Icons.info_outline_rounded),
                title: Text('مستنداتي 2.7.0'),
                subtitle: Text('PDF • Word • Excel • PowerPoint • Text'),
              ),
            ],
          ),
        ),
      ),
    );
  }

'''
s = replace_once(s, "  List<DocumentItem> get visible {\n", settings_method + "  List<DocumentItem> get visible {\n", 'settings method')

# Document actions in details sheet.
details_marker = """              const SizedBox(height: 4),
              Text(
                'اضغط مطولًا على أي مستند لفتح هذه المعلومات بسرعة.',
"""
details_actions = r'''              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(sheetContext);
                      unawaited(_renameItem(item));
                    },
                    icon: const Icon(Icons.drive_file_rename_outline_rounded),
                    label: const Text('إعادة تسمية'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(sheetContext);
                      unawaited(_duplicateItem(item));
                    },
                    icon: const Icon(Icons.content_copy_rounded),
                    label: const Text('إنشاء نسخة'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () async {
                      await _togglePinned(item);
                      if (sheetContext.mounted) Navigator.pop(sheetContext);
                    },
                    icon: Icon(_pinnedPaths.contains(item.path) ? Icons.push_pin_rounded : Icons.push_pin_outlined),
                    label: Text(_pinnedPaths.contains(item.path) ? 'إلغاء التثبيت' : 'تثبيت'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () async {
                      await _toggleReadLater(item);
                      if (sheetContext.mounted) Navigator.pop(sheetContext);
                    },
                    icon: Icon(_readLaterPaths.contains(item.path) ? Icons.bookmark_rounded : Icons.bookmark_border_rounded),
                    label: Text(_readLaterPaths.contains(item.path) ? 'إزالة من لاحقًا' : 'قراءة لاحقًا'),
                  ),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
                    onPressed: () {
                      Navigator.pop(sheetContext);
                      unawaited(_deleteItem(item));
                    },
                    icon: const Icon(Icons.delete_outline_rounded),
                    label: const Text('حذف'),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'اضغط مطولًا على أي مستند لفتح هذه المعلومات بسرعة.',
'''
s = replace_once(s, details_marker, details_actions, 'detail actions')

# Settings action in app bar.
s = replace_once(
    s,
    """          IconButton(
            tooltip: 'إضافة مستندات',
            onPressed: busy ? null : _showAddSheet,
            icon: const Icon(Icons.add_rounded),
          ),
          const SizedBox(width: 6),
""",
    """          IconButton(
            tooltip: 'إضافة مستندات',
            onPressed: busy ? null : _showAddSheet,
            icon: const Icon(Icons.add_rounded),
          ),
          IconButton(
            tooltip: 'الإعدادات',
            onPressed: _showSettings,
            icon: const Icon(Icons.tune_rounded),
          ),
          const SizedBox(width: 6),
""",
    'settings appbar',
)

# Dashboard collections.
s = replace_once(
    s,
    """  Widget _buildDashboard() {
    final recent = recentDocuments;
    final continueItem = recent.isEmpty ? null : recent.first;
""",
    """  Widget _buildDashboard() {
    final recent = recentDocuments;
    final pinned = all.where((item) => _pinnedPaths.contains(item.path)).toList();
    final readLater = all.where((item) => _readLaterPaths.contains(item.path)).toList();
    final continueItem = recent.isEmpty ? null : recent.first;
""",
    'dashboard collections',
)
collections_ui = r'''          if (pinned.isNotEmpty) ...[
            const SizedBox(height: 24),
            const _SectionHeader(title: 'المثبتة'),
            const SizedBox(height: 6),
            ...pinned.take(3).map(
                  (item) => DocumentTile(
                    item: item,
                    compact: true,
                    isOpening: openingPath == item.path,
                    onOpen: () => _open(item),
                    onDetails: () => _showDetails(item),
                    onFavorite: () async {
                      await db.setFavorite(item.path, !item.isFavorite);
                      await _load();
                    },
                  ),
                ),
          ],
          if (readLater.isNotEmpty) ...[
            const SizedBox(height: 24),
            const _SectionHeader(title: 'قراءة لاحقًا'),
            const SizedBox(height: 6),
            ...readLater.take(3).map(
                  (item) => DocumentTile(
                    item: item,
                    compact: true,
                    isOpening: openingPath == item.path,
                    onOpen: () => _open(item),
                    onDetails: () => _showDetails(item),
                    onFavorite: () async {
                      await db.setFavorite(item.path, !item.isFavorite);
                      await _load();
                    },
                  ),
                ),
          ],
'''
s = replace_once(s, "          if (continueItem != null) ...[\n", collections_ui + "          if (continueItem != null) ...[\n", 'dashboard collection UI')

# Grid/list toggle in files toolbar.
s = replace_once(
    s,
    """              IconButton(
                tooltip: 'إضافة مستندات',
                onPressed: busy ? null : _showAddSheet,
                icon: const Icon(Icons.add_circle_outline_rounded),
              ),
""",
    """              IconButton(
                tooltip: _gridMode ? 'عرض قائمة' : 'عرض شبكة',
                onPressed: () => _setGridMode(!_gridMode),
                icon: Icon(_gridMode ? Icons.view_list_rounded : Icons.grid_view_rounded),
              ),
              IconButton(
                tooltip: 'إضافة مستندات',
                onPressed: busy ? null : _showAddSheet,
                icon: const Icon(Icons.add_circle_outline_rounded),
              ),
""",
    'view mode toggle',
)

pattern = re.compile(r"        Expanded\(\n          child: docs\.isEmpty.*?\n        \),\n      \],\n    \);\n  \}\n\n  Widget _buildFavoritesView\(\)", re.S)
replacement = r'''        Expanded(
          child: docs.isEmpty
              ? _EmptyState(hasAny: all.isNotEmpty, onScan: _scan, onPick: _pick)
              : _documentsView(docs),
        ),
      ],
    );
  }

  Widget _documentsView(List<DocumentItem> docs) {
    if (_gridMode) {
      return RefreshIndicator(
        onRefresh: () => _load(pruneMissing: true),
        child: GridView.builder(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 230,
            mainAxisExtent: 190,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
          ),
          itemCount: docs.length,
          itemBuilder: (_, index) {
            final item = docs[index];
            return _GridDocumentCard(
              item: item,
              isOpening: openingPath == item.path,
              onOpen: () => _open(item),
              onDetails: () => _showDetails(item),
              onFavorite: () async {
                await db.setFavorite(item.path, !item.isFavorite);
                await _load();
              },
            );
          },
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: () => _load(pruneMissing: true),
      child: ListView.builder(
        padding: const EdgeInsets.only(bottom: 24),
        itemCount: docs.length,
        itemBuilder: (_, index) {
          final item = docs[index];
          return DocumentTile(
            item: item,
            onOpen: () => _open(item),
            onDetails: () => _showDetails(item),
            isOpening: openingPath == item.path,
            onFavorite: () async {
              await db.setFavorite(item.path, !item.isFavorite);
              await _load();
            },
          );
        },
      ),
    );
  }

  Widget _buildFavoritesView()'''
s, count = pattern.subn(replacement, s, count=1)
if count != 1:
    raise SystemExit('patch point not found: files collection view')

# Grid card component.
grid_card = r'''
class _GridDocumentCard extends StatelessWidget {
  final DocumentItem item;
  final bool isOpening;
  final VoidCallback onOpen;
  final VoidCallback onDetails;
  final VoidCallback onFavorite;

  const _GridDocumentCard({
    required this.item,
    required this.isOpening,
    required this.onOpen,
    required this.onDetails,
    required this.onFavorite,
  });

  @override
  Widget build(BuildContext context) {
    final color = DocumentTile.kindColor(item.kind);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: isOpening ? null : onOpen,
        onLongPress: onDetails,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: .11),
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: isOpening
                        ? const Padding(
                            padding: EdgeInsets.all(13),
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(DocumentTile.kindIcon(item.kind), color: color, size: 26),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: item.isFavorite ? 'إزالة من المفضلة' : 'إضافة للمفضلة',
                    onPressed: onFavorite,
                    icon: Icon(item.isFavorite ? Icons.star_rounded : Icons.star_border_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                DocumentTile.cleanName(item.name),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
              ),
              const Spacer(),
              Row(
                children: [
                  Text(item.extension.toUpperCase(), style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 11)),
                  const SizedBox(width: 7),
                  Expanded(child: Text(DocumentTile.sizeText(item.size), style: Theme.of(context).textTheme.bodySmall)),
                  IconButton(onPressed: onDetails, icon: const Icon(Icons.more_horiz_rounded), tooltip: 'خيارات'),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

'''
s = replace_once(s, "class _InfoRow extends StatelessWidget {\n", grid_card + "class _InfoRow extends StatelessWidget {\n", 'grid card')

home.write_text(s)

# Viewer enhancements: PDF page badge, Excel search highlight, always-light Office rendering.
viewer = Path('lib/screens/viewer_screen.dart')
v = viewer.read_text()
old_pdf = r'''class _PdfReaderState extends State<_PdfReader> {
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
'''
new_pdf = r'''class _PdfReaderState extends State<_PdfReader> {
  late final Future<int> _initialPage =
      ReadingProgressService.instance.pdfPage(widget.item.path);
  int _currentPage = 1;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<int>(
      future: _initialPage,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final initial = snapshot.data!;
        final visiblePage = _currentPage == 1 && initial > 1 ? initial : _currentPage;
        return Stack(
          children: [
            Positioned.fill(
              child: PdfViewer.file(
                widget.item.path,
                initialPageNumber: initial,
                params: PdfViewerParams(
                  onPageChanged: (page) {
                    if (page != null) {
                      if (mounted) setState(() => _currentPage = page);
                      unawaited(
                        ReadingProgressService.instance
                            .savePdfPage(widget.item.path, page),
                      );
                    }
                  },
                ),
              ),
            ),
            Positioned(
              bottom: 18,
              left: 0,
              right: 0,
              child: Center(
                child: IgnorePointer(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                    decoration: BoxDecoration(
                      color: const Color(0xDD1B2430),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'صفحة $visiblePage',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
'''
v = replace_once(v, old_pdf, new_pdf, 'pdf page badge')

excel_pattern = re.compile(r"class _ExcelWorkbookState extends State<_ExcelWorkbook> \{.*?\n\}\n\nclass _ExcelGrid extends StatelessWidget \{", re.S)
excel_state = r'''class _ExcelWorkbookState extends State<_ExcelWorkbook> {
  int _selectedIndex = 0;
  final TextEditingController _search = TextEditingController();
  bool _showSearch = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  int _matchCount(_XlsxSheet sheet) {
    final query = _search.text.trim().toLowerCase();
    if (query.isEmpty) return 0;
    var count = 0;
    for (final row in sheet.cells.values) {
      for (final value in row.values) {
        if (value.toLowerCase().contains(query)) count++;
      }
    }
    return count;
  }

  @override
  Widget build(BuildContext context) {
    final sheet = widget.workbook.sheets[_selectedIndex];
    final scheme = Theme.of(context).colorScheme;
    final matches = _matchCount(sheet);
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
                    const Icon(Icons.table_chart_rounded, color: Color(0xFF168A4A)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        sheet.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    if (_search.text.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Text('$matches نتيجة', style: Theme.of(context).textTheme.labelSmall),
                      ),
                    IconButton(
                      tooltip: 'بحث داخل الورقة',
                      onPressed: () => setState(() {
                        _showSearch = !_showSearch;
                        if (!_showSearch) _search.clear();
                      }),
                      icon: Icon(_showSearch ? Icons.close_rounded : Icons.search_rounded),
                    ),
                  ],
                ),
              ),
              if (_showSearch)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                  child: TextField(
                    controller: _search,
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: 'ابحث في الخلايا…',
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixText: _search.text.isEmpty ? null : '$matches',
                      filled: true,
                      fillColor: scheme.surfaceContainerLow,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              SizedBox(
                height: 50,
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  scrollDirection: Axis.horizontal,
                  itemCount: widget.workbook.sheets.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 7),
                  itemBuilder: (_, index) {
                    final current = widget.workbook.sheets[index];
                    final selected = index == _selectedIndex;
                    return ChoiceChip(
                      selected: selected,
                      avatar: Icon(Icons.grid_on_rounded, size: 16, color: selected ? scheme.primary : scheme.onSurfaceVariant),
                      label: Text(current.name),
                      onSelected: (_) => setState(() {
                        _selectedIndex = index;
                        _search.clear();
                      }),
                    );
                  },
                ),
              ),
            ],
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
              Text('${sheet.maxRows} صف × ${sheet.maxColumns} عمود', style: Theme.of(context).textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant)),
              const Spacer(),
              Text('XLSX • عرض آمن', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: const Color(0xFF168A4A), fontWeight: FontWeight.w800)),
            ],
          ),
        ),
        Expanded(child: _ExcelGrid(sheet: sheet, query: _search.text)),
      ],
    );
  }
}

class _ExcelGrid extends StatelessWidget {'''
v, count = excel_pattern.subn(excel_state, v, count=1)
if count != 1:
    raise SystemExit('patch point not found: excel workbook state')

v = replace_once(
    v,
    """class _ExcelGrid extends StatelessWidget {
  final _XlsxSheet sheet;
  const _ExcelGrid({required this.sheet});
""",
    """class _ExcelGrid extends StatelessWidget {
  final _XlsxSheet sheet;
  final String query;
  const _ExcelGrid({required this.sheet, this.query = ''});
""",
    'excel grid query',
)
v = replace_once(
    v,
    """    final value = sheet.cells[row - 1]?[column - 1] ?? '';
    return Container(
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: scheme.surface,
""",
    """    final value = sheet.cells[row - 1]?[column - 1] ?? '';
    final normalizedQuery = query.trim().toLowerCase();
    final matched = normalizedQuery.isNotEmpty && value.toLowerCase().contains(normalizedQuery);
    return Container(
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: matched ? const Color(0xFFFFF3A3) : scheme.surface,
""",
    'excel highlight',
)
v = v.replace("darkMode: Theme.of(context).brightness == Brightness.dark,", "darkMode: false,")
viewer.write_text(v)

print('v2.7 patch applied successfully')
