import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/document_filter.dart';
import '../models/document_item.dart';
import '../services/database_service.dart';
import '../services/document_validation_service.dart';
import '../services/file_service.dart';
import '../services/incoming_document_service.dart';
import '../widgets/document_tile.dart';
import 'viewer_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final db = DatabaseService.instance;
  final files = FileService();
  final search = TextEditingController();

  List<DocumentItem> all = const [];
  DocumentKind? filter;
  SortMode sort = SortMode.modified;
  bool favoritesOnly = false;
  bool recentOnly = false;
  bool busy = false;
  String? openingPath;
  int tabIndex = 0;
  StreamSubscription<IncomingDocumentRef>? _incomingSubscription;

  @override
  void initState() {
    super.initState();
    search.addListener(_onSearchChanged);
    unawaited(_initialize());
  }

  void _onSearchChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _initialize() async {
    await _load();
    try {
      final initial = await IncomingDocumentService.instance.initialize();
      _incomingSubscription = IncomingDocumentService.instance.documents.listen((ref) {
        unawaited(_handleIncoming(ref));
      });
      if (initial != null) await _handleIncoming(initial);
    } catch (_) {}
  }

  @override
  void dispose() {
    search.removeListener(_onSearchChanged);
    search.dispose();
    unawaited(_incomingSubscription?.cancel());
    super.dispose();
  }

  Future<void> _load({bool pruneMissing = false}) async {
    if (pruneMissing) await db.removeMissing();
    final loaded = await db.getAll();
    if (mounted) setState(() => all = loaded);
  }

  Future<void> _scan() async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final result = await files.scanDevice();
      if (!result.fullAccess) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('لم يتم منح إذن إدارة الملفات. يمكنك اختيار المستندات يدويًا من زر «إضافة». '),
            ),
          );
        }
        return;
      }
      await db.upsertAll(result.items);
      await _load(pruneMissing: true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تم العثور على ${result.items.length} مستندًا.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل فحص الملفات: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _pick() async {
    try {
      final picked = await files.pickFiles();
      await db.upsertAll(picked);
      await _load();
      if (mounted && picked.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تمت إضافة ${picked.length} مستندًا.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر استيراد الملف: $e')),
        );
      }
    }
  }

  Future<void> _handleIncoming(IncomingDocumentRef ref) async {
    final item = await files.importIncoming(ref);
    if (item == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('نوع الملف غير مدعوم أو تعذر الوصول إليه.')),
        );
      }
      return;
    }
    await db.upsert(item);
    await _load();
    await _open(item);
  }

  Future<void> _open(DocumentItem item) async {
    if (openingPath != null) return;
    if (mounted) setState(() => openingPath = item.path);
    try {
      final file = File(item.path);
      if (!await file.exists()) {
        await db.removePath(item.path);
        await _load();
        throw StateError('الملف لم يعد موجودًا في هذا المسار.');
      }
      final size = await file.length();
      if (size > FileService.maxDocumentBytes) {
        throw StateError('حجم المستند أكبر من 512 MB. تم إيقاف فتحه لحماية ذاكرة الهاتف.');
      }
      final validation = await DocumentValidationService.instance.validate(item);
      if (!validation.isValid) {
        throw StateError(validation.message ?? 'فشل التحقق من المستند.');
      }
      await db.markOpened(item.path);
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute<void>(builder: (_) => ViewerScreen(item: item)),
      );
      await _load();
    } catch (e) {
      if (mounted) await _showOpenError(e);
    } finally {
      if (mounted) setState(() => openingPath = null);
    }
  }

  Future<void> _showOpenError(Object error) async {
    final raw = error.toString().replaceFirst('Bad state: ', '');
    final message = raw.contains('PlatformException')
        ? 'تعذر تشغيل عارض المستند على هذا الجهاز. حاول إعادة فتح الملف.'
        : raw;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline_rounded,
                size: 44,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: 12),
              Text('تعذر فتح المستند', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('حسنًا'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showAddSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const _SheetIcon(icon: Icons.note_add_rounded),
                title: const Text('اختيار مستندات'),
                subtitle: const Text('اختر PDF أو Word أو Excel أو PowerPoint من الهاتف'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  unawaited(_pick());
                },
              ),
              ListTile(
                leading: const _SheetIcon(icon: Icons.manage_search_rounded),
                title: const Text('فحص الهاتف'),
                subtitle: const Text('البحث عن المستندات في المجلدات المعروفة'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  unawaited(_scan());
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showDetails(DocumentItem item) async {
    final scheme = Theme.of(context).colorScheme;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            0,
            20,
            20 + MediaQuery.viewInsetsOf(sheetContext).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      color: DocumentTile.kindColor(item.kind).withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(17),
                    ),
                    child: Icon(
                      DocumentTile.kindIcon(item.kind),
                      color: DocumentTile.kindColor(item.kind),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          DocumentTile.cleanName(item.name),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${item.extension.toUpperCase()} • ${DocumentTile.sizeText(item.size)}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _InfoRow(label: 'آخر تعديل', value: _dateTime(item.modifiedAt)),
              if (item.lastOpenedAt != null)
                _InfoRow(label: 'آخر فتح', value: _dateTime(item.lastOpenedAt!)),
              _InfoRow(label: 'المسار', value: item.path, selectable: true),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () {
                        Navigator.pop(sheetContext);
                        unawaited(_open(item));
                      },
                      icon: const Icon(Icons.open_in_new_rounded),
                      label: const Text('فتح'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  IconButton.filledTonal(
                    tooltip: item.isFavorite ? 'إزالة من المفضلة' : 'إضافة للمفضلة',
                    onPressed: () async {
                      await db.setFavorite(item.path, !item.isFavorite);
                      if (sheetContext.mounted) Navigator.pop(sheetContext);
                      await _load();
                    },
                    icon: Icon(item.isFavorite ? Icons.star_rounded : Icons.star_border_rounded),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    tooltip: 'نسخ المسار',
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: item.path));
                      if (sheetContext.mounted) {
                        Navigator.pop(sheetContext);
                      }
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('تم نسخ مسار المستند.')),
                        );
                      }
                    },
                    icon: const Icon(Icons.copy_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'اضغط مطولًا على أي مستند لفتح هذه المعلومات بسرعة.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<DocumentItem> get visible {
    final result = DocumentFilter.apply(
      all,
      query: search.text,
      kind: filter,
      favoritesOnly: favoritesOnly,
      sort: sort,
    );
    if (recentOnly) {
      result.removeWhere((item) => item.lastOpenedAt == null);
      result.sort((a, b) => b.lastOpenedAt!.compareTo(a.lastOpenedAt!));
    }
    return result;
  }

  List<DocumentItem> get recentDocuments {
    final result = all.where((item) => item.lastOpenedAt != null).toList()
      ..sort((a, b) => b.lastOpenedAt!.compareTo(a.lastOpenedAt!));
    return result;
  }

  int count(DocumentKind kind) => all.where((e) => e.kind == kind).length;

  void _openCategory(DocumentKind kind) {
    setState(() {
      tabIndex = 1;
      filter = kind;
      favoritesOnly = false;
      recentOnly = false;
      search.clear();
    });
  }

  void _showAllFiles() {
    setState(() {
      tabIndex = 1;
      filter = null;
      favoritesOnly = false;
      recentOnly = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF1F63E9), Color(0xFF4A8BFF)],
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                ),
                borderRadius: BorderRadius.circular(13),
              ),
              child: const Icon(Icons.description_rounded, color: Colors.white, size: 23),
            ),
            const SizedBox(width: 11),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('مستنداتي'),
                Text(
                  '${all.length} مستندًا',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'إضافة مستندات',
            onPressed: busy ? null : _showAddSheet,
            icon: const Icon(Icons.add_rounded),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: IndexedStack(
        index: tabIndex,
        children: [
          _buildDashboard(),
          _buildFilesView(),
          _buildFavoritesView(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tabIndex,
        onDestinationSelected: (value) {
          setState(() {
            tabIndex = value;
            if (value == 2) {
              favoritesOnly = true;
              recentOnly = false;
              filter = null;
            } else if (value == 0) {
              favoritesOnly = false;
              recentOnly = false;
            } else if (value == 1 && favoritesOnly) {
              favoritesOnly = false;
            }
          });
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home_rounded), label: 'الرئيسية'),
          NavigationDestination(icon: Icon(Icons.folder_outlined), selectedIcon: Icon(Icons.folder_rounded), label: 'الملفات'),
          NavigationDestination(icon: Icon(Icons.star_outline_rounded), selectedIcon: Icon(Icons.star_rounded), label: 'المفضلة'),
        ],
      ),
      floatingActionButton: tabIndex == 0
          ? FloatingActionButton.extended(
              onPressed: busy ? null : _showAddSheet,
              icon: busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.add_rounded),
              label: Text(busy ? 'جارٍ الفحص' : 'إضافة'),
            )
          : null,
    );
  }

  Widget _buildDashboard() {
    final recent = recentDocuments;
    final continueItem = recent.isEmpty ? null : recent.first;
    return RefreshIndicator(
      onRefresh: () => _load(pruneMissing: true),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 110),
        children: [
          _HeroCard(
            total: all.length,
            onAdd: _showAddSheet,
          ),
          const SizedBox(height: 14),
          SearchBar(
            controller: search,
            hintText: 'ابحث في مستنداتك…',
            leading: const Icon(Icons.search_rounded),
            trailing: search.text.isEmpty
                ? null
                : [IconButton(onPressed: search.clear, icon: const Icon(Icons.close_rounded))],
            onSubmitted: (_) => setState(() => tabIndex = 1),
          ),
          const SizedBox(height: 22),
          _SectionHeader(title: 'أنواع المستندات', actionText: 'كل الملفات', onAction: _showAllFiles),
          const SizedBox(height: 10),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 1.72,
            children: [
              _CategoryCard(
                title: 'PDF',
                subtitle: '${count(DocumentKind.pdf)} ملف',
                icon: Icons.picture_as_pdf_rounded,
                color: DocumentTile.kindColor(DocumentKind.pdf),
                onTap: () => _openCategory(DocumentKind.pdf),
              ),
              _CategoryCard(
                title: 'Word',
                subtitle: '${count(DocumentKind.word)} ملف',
                icon: Icons.description_rounded,
                color: DocumentTile.kindColor(DocumentKind.word),
                onTap: () => _openCategory(DocumentKind.word),
              ),
              _CategoryCard(
                title: 'Excel',
                subtitle: '${count(DocumentKind.excel)} ملف',
                icon: Icons.table_chart_rounded,
                color: DocumentTile.kindColor(DocumentKind.excel),
                onTap: () => _openCategory(DocumentKind.excel),
              ),
              _CategoryCard(
                title: 'PowerPoint',
                subtitle: '${count(DocumentKind.powerpoint)} ملف',
                icon: Icons.slideshow_rounded,
                color: DocumentTile.kindColor(DocumentKind.powerpoint),
                onTap: () => _openCategory(DocumentKind.powerpoint),
              ),
            ],
          ),
          if (continueItem != null) ...[
            const SizedBox(height: 24),
            const _SectionHeader(title: 'متابعة القراءة'),
            const SizedBox(height: 10),
            _ContinueCard(
              item: continueItem,
              onOpen: () => _open(continueItem),
            ),
          ],
          if (recent.isNotEmpty) ...[
            const SizedBox(height: 24),
            _SectionHeader(
              title: 'المستخدمة مؤخرًا',
              actionText: 'عرض الكل',
              onAction: () {
                setState(() {
                  tabIndex = 1;
                  recentOnly = true;
                  favoritesOnly = false;
                  filter = null;
                });
              },
            ),
            const SizedBox(height: 6),
            ...recent.take(4).map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: DocumentTile(
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
                ),
          ],
          if (all.isEmpty) ...[
            const SizedBox(height: 28),
            _EmptyState(hasAny: false, onScan: _scan, onPick: _pick),
          ],
        ],
      ),
    );
  }

  Widget _buildFilesView() {
    final docs = visible;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: SearchBar(
            controller: search,
            hintText: 'ابحث بالاسم أو الامتداد…',
            leading: const Icon(Icons.search_rounded),
            trailing: search.text.isEmpty
                ? null
                : [IconButton(onPressed: search.clear, icon: const Icon(Icons.close_rounded))],
          ),
        ),
        SizedBox(
          height: 48,
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            scrollDirection: Axis.horizontal,
            children: [
              FilterChip(
                label: Text('الكل ${all.length}'),
                selected: filter == null && !recentOnly && !favoritesOnly,
                onSelected: (_) => setState(() {
                  filter = null;
                  recentOnly = false;
                  favoritesOnly = false;
                }),
              ),
              const SizedBox(width: 8),
              FilterChip(
                label: const Text('الأخيرة'),
                avatar: const Icon(Icons.history_rounded, size: 17),
                selected: recentOnly,
                onSelected: (value) => setState(() {
                  recentOnly = value;
                  favoritesOnly = false;
                  filter = null;
                }),
              ),
              ...[
                DocumentKind.pdf,
                DocumentKind.word,
                DocumentKind.excel,
                DocumentKind.powerpoint,
                DocumentKind.text,
              ].map(
                (kind) => Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text('${_kindName(kind)} ${count(kind)}'),
                    selected: filter == kind,
                    onSelected: (_) => setState(() {
                      filter = filter == kind ? null : kind;
                      recentOnly = false;
                      favoritesOnly = false;
                    }),
                  ),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 6, 12, 2),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${docs.length} ملف ظاهر',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              PopupMenuButton<SortMode>(
                tooltip: 'ترتيب',
                initialValue: sort,
                onSelected: (value) => setState(() => sort = value),
                icon: const Icon(Icons.swap_vert_rounded),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: SortMode.modified, child: Text('الأحدث أولًا')),
                  PopupMenuItem(value: SortMode.name, child: Text('حسب الاسم')),
                  PopupMenuItem(value: SortMode.size, child: Text('حسب الحجم')),
                ],
              ),
              IconButton(
                tooltip: 'إضافة مستندات',
                onPressed: busy ? null : _showAddSheet,
                icon: const Icon(Icons.add_circle_outline_rounded),
              ),
            ],
          ),
        ),
        Expanded(
          child: docs.isEmpty
              ? _EmptyState(hasAny: all.isNotEmpty, onScan: _scan, onPick: _pick)
              : RefreshIndicator(
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
                ),
        ),
      ],
    );
  }

  Widget _buildFavoritesView() {
    final favorites = DocumentFilter.apply(
      all,
      query: search.text,
      favoritesOnly: true,
      sort: sort,
    );
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: SearchBar(
            controller: search,
            hintText: 'ابحث في المفضلة…',
            leading: const Icon(Icons.search_rounded),
            trailing: search.text.isEmpty
                ? null
                : [IconButton(onPressed: search.clear, icon: const Icon(Icons.close_rounded))],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 6),
          child: Row(
            children: [
              Icon(Icons.star_rounded, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                '${favorites.length} في المفضلة',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
        Expanded(
          child: favorites.isEmpty
              ? const _FavoritesEmptyState()
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 24),
                  itemCount: favorites.length,
                  itemBuilder: (_, index) {
                    final item = favorites[index];
                    return DocumentTile(
                      item: item,
                      onOpen: () => _open(item),
                      onDetails: () => _showDetails(item),
                      isOpening: openingPath == item.path,
                      onFavorite: () async {
                        await db.setFavorite(item.path, false);
                        await _load();
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }

  String _kindName(DocumentKind kind) => switch (kind) {
        DocumentKind.pdf => 'PDF',
        DocumentKind.word => 'Word',
        DocumentKind.excel => 'Excel',
        DocumentKind.powerpoint => 'PowerPoint',
        DocumentKind.text => 'نصوص',
        DocumentKind.other => 'أخرى',
      };

  String _dateTime(DateTime value) {
    final date = DocumentTile.dateText(value);
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '$date  $hour:$minute';
  }
}

class _HeroCard extends StatelessWidget {
  final int total;
  final VoidCallback onAdd;

  const _HeroCard({required this.total, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF164FC5), Color(0xFF2F7AF4)],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1F63E9).withValues(alpha: .18),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'كل مستنداتك في مكان واحد',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 19),
                ),
                const SizedBox(height: 6),
                Text(
                  '$total ملف • يعمل محليًا على الهاتف',
                  style: TextStyle(color: Colors.white.withValues(alpha: .82), fontSize: 13),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFF164FC5),
                  ),
                  onPressed: onAdd,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('إضافة مستند'),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Container(
            width: 74,
            height: 74,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .14),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white.withValues(alpha: .20)),
            ),
            child: const Icon(Icons.folder_copy_rounded, color: Colors.white, size: 38),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final String? actionText;
  final VoidCallback? onAction;

  const _SectionHeader({required this.title, this.actionText, this.onAction});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
        ),
        if (actionText != null)
          TextButton(onPressed: onAction, child: Text(actionText!)),
      ],
    );
  }
}

class _CategoryCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _CategoryCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          child: Row(
            children: [
              Container(
                width: 45,
                height: 45,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .11),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 2),
                    Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
              Icon(Icons.chevron_left_rounded, color: Theme.of(context).colorScheme.outline),
            ],
          ),
        ),
      ),
    );
  }
}

class _ContinueCard extends StatelessWidget {
  final DocumentItem item;
  final VoidCallback onOpen;

  const _ContinueCard({required this.item, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final color = DocumentTile.kindColor(item.kind);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .11),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(DocumentTile.kindIcon(item.kind), color: color, size: 29),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      DocumentTile.cleanName(item.name),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      'آخر فتح ${item.lastOpenedAt == null ? '' : _relative(item.lastOpenedAt!)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(onPressed: onOpen, icon: const Icon(Icons.play_arrow_rounded)),
            ],
          ),
        ),
      ),
    );
  }

  static String _relative(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) return 'الآن';
    if (diff.inHours < 1) return 'قبل ${diff.inMinutes} د';
    if (diff.inDays < 1) return 'قبل ${diff.inHours} س';
    return 'قبل ${diff.inDays} يوم';
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final bool selectable;

  const _InfoRow({required this.label, required this.value, this.selectable = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 78,
            child: Text(label, style: Theme.of(context).textTheme.bodySmall),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: selectable
                ? SelectableText(value, style: Theme.of(context).textTheme.bodyMedium)
                : Text(value, style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}

class _SheetIcon extends StatelessWidget {
  final IconData icon;
  const _SheetIcon({required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(13),
      ),
      child: Icon(icon, color: Theme.of(context).colorScheme.onPrimaryContainer),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final bool hasAny;
  final VoidCallback onScan;
  final VoidCallback onPick;

  const _EmptyState({required this.hasAny, required this.onScan, required this.onPick});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 84,
                height: 84,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: .55),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.folder_copy_outlined, size: 42),
              ),
              const SizedBox(height: 18),
              Text(
                hasAny ? 'لا توجد نتائج مطابقة' : 'أضف مستنداتك للبدء',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                hasAny ? 'غيّر البحث أو الفلتر الحالي.' : 'يمكنك فحص الهاتف أو اختيار الملفات يدويًا.',
                textAlign: TextAlign.center,
              ),
              if (!hasAny) ...[
                const SizedBox(height: 20),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  alignment: WrapAlignment.center,
                  children: [
                    FilledButton.icon(
                      onPressed: onPick,
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('اختيار ملفات'),
                    ),
                    OutlinedButton.icon(
                      onPressed: onScan,
                      icon: const Icon(Icons.manage_search_rounded),
                      label: const Text('فحص الهاتف'),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      );
}

class _FavoritesEmptyState extends StatelessWidget {
  const _FavoritesEmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.star_border_rounded, size: 70, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 14),
            Text(
              'لا توجد مستندات مفضلة',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 7),
            const Text('أضف المستندات المهمة إلى المفضلة لتصل إليها بسرعة.', textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
