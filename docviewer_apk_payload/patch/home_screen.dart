import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
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
  bool busy = false;
  String? openingPath;
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
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('لم يتم منح إذن إدارة الملفات. استخدم «إضافة ملفات» لاختيار المستندات يدويًا.'),
          ));
        }
        return;
      }
      await db.upsertAll(result.items);
      await _load(pruneMissing: true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تم العثور على ${result.items.length} مستندًا.')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل فحص الملفات: $e')));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _pick() async {
    try {
      final picked = await files.pickFiles();
      await db.upsertAll(picked);
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر استيراد الملف: $e')));
    }
  }

  Future<void> _handleIncoming(IncomingDocumentRef ref) async {
    final item = await files.importIncoming(ref);
    if (item == null) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('نوع الملف غير مدعوم أو تعذر الوصول إليه.')));
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
      await Navigator.push(context, MaterialPageRoute<void>(builder: (_) => ViewerScreen(item: item)));
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
              Icon(Icons.error_outline_rounded, size: 44, color: Theme.of(context).colorScheme.error),
              const SizedBox(height: 12),
              Text('تعذر فتح المستند', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(onPressed: () => Navigator.pop(context), child: const Text('حسنًا')),
            ],
          ),
        ),
      ),
    );
  }

  List<DocumentItem> get visible => DocumentFilter.apply(
        all,
        query: search.text,
        kind: filter,
        favoritesOnly: favoritesOnly,
        sort: sort,
      );

  int count(DocumentKind kind) => all.where((e) => e.kind == kind).length;

  @override
  Widget build(BuildContext context) {
    final docs = visible;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('مستنداتي'),
            Text('${all.length} مستندًا على الهاتف', style: Theme.of(context).textTheme.labelMedium),
          ],
        ),
        actions: [
          IconButton(tooltip: 'إضافة ملفات', onPressed: busy ? null : _pick, icon: const Icon(Icons.add_rounded)),
          PopupMenuButton<SortMode>(
            tooltip: 'ترتيب',
            initialValue: sort,
            onSelected: (value) => setState(() => sort = value),
            itemBuilder: (_) => const [
              PopupMenuItem(value: SortMode.modified, child: Text('الأحدث أولًا')),
              PopupMenuItem(value: SortMode.name, child: Text('حسب الاسم')),
              PopupMenuItem(value: SortMode.size, child: Text('حسب الحجم')),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: busy ? null : _scan,
        icon: busy
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.manage_search_rounded),
        label: Text(busy ? 'جارٍ الفحص' : 'فحص الهاتف'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: SearchBar(
              controller: search,
              hintText: 'ابحث عن PDF أو Word أو Excel أو PowerPoint…',
              leading: const Icon(Icons.search_rounded),
              trailing: search.text.isEmpty ? null : [IconButton(onPressed: search.clear, icon: const Icon(Icons.close_rounded))],
            ),
          ),
          SizedBox(
            height: 52,
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              scrollDirection: Axis.horizontal,
              children: [
                FilterChip(
                  label: Text('الكل ${all.length}'),
                  selected: filter == null && !favoritesOnly,
                  onSelected: (_) => setState(() { filter = null; favoritesOnly = false; }),
                ),
                const SizedBox(width: 8),
                FilterChip(
                  label: const Text('المفضلة'),
                  avatar: const Icon(Icons.star_rounded, size: 18),
                  selected: favoritesOnly,
                  onSelected: (value) => setState(() => favoritesOnly = value),
                ),
                ...[DocumentKind.pdf, DocumentKind.word, DocumentKind.excel, DocumentKind.powerpoint, DocumentKind.text].map(
                  (kind) => Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text('${_kindName(kind)} ${count(kind)}'),
                      selected: filter == kind,
                      onSelected: (_) => setState(() { filter = filter == kind ? null : kind; favoritesOnly = false; }),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: docs.isEmpty
                ? _EmptyState(hasAny: all.isNotEmpty, onScan: _scan, onPick: _pick)
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView.builder(
                      padding: const EdgeInsets.only(bottom: 96),
                      itemCount: docs.length,
                      itemBuilder: (_, index) {
                        final item = docs[index];
                        return DocumentTile(
                          item: item,
                          onOpen: () => _open(item),
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
      ),
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
              const Icon(Icons.folder_copy_outlined, size: 72),
              const SizedBox(height: 16),
              Text(hasAny ? 'لا توجد نتائج مطابقة' : 'لم تتم فهرسة المستندات بعد', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(hasAny ? 'غيّر البحث أو الفلتر.' : 'افحص الهاتف أو اختر مستندات يدويًا.', textAlign: TextAlign.center),
              if (!hasAny) ...[
                const SizedBox(height: 20),
                Wrap(spacing: 10, runSpacing: 10, alignment: WrapAlignment.center, children: [
                  FilledButton.icon(onPressed: onScan, icon: const Icon(Icons.manage_search_rounded), label: const Text('فحص الهاتف')),
                  OutlinedButton.icon(onPressed: onPick, icon: const Icon(Icons.add_rounded), label: const Text('إضافة ملفات')),
                ]),
              ],
            ],
          ),
        ),
      );
}
