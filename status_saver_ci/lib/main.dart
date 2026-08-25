import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() => runApp(const StatusSaverApp());

const _brand = Color(0xFF0AA66F);

class StatusItem {
  const StatusItem({
    required this.uri,
    required this.name,
    required this.mimeType,
    required this.isVideo,
    required this.lastModified,
    required this.size,
  });

  final String uri;
  final String name;
  final String mimeType;
  final bool isVideo;
  final int lastModified;
  final int size;

  factory StatusItem.fromMap(Map<Object?, Object?> m) {
    final mime = (m['mimeType'] ?? '').toString();
    return StatusItem(
      uri: (m['uri'] ?? '').toString(),
      name: (m['name'] ?? '').toString(),
      mimeType: mime,
      isVideo: m['isVideo'] == true || mime.startsWith('video/'),
      lastModified: (m['lastModified'] as num?)?.toInt() ?? 0,
      size: (m['size'] as num?)?.toInt() ?? 0,
    );
  }
}

List<StatusItem> filterStatuses(List<StatusItem> items, int tab) => switch (tab) {
      1 => items.where((e) => !e.isVideo).toList(),
      2 => items.where((e) => e.isVideo).toList(),
      _ => items,
    };

String formatFileSize(int bytes) {
  if (bytes <= 0) return '';
  if (bytes < 1024) return '$bytes B';
  final kb = bytes / 1024;
  if (kb < 1024) return '${kb.toStringAsFixed(kb >= 100 ? 0 : 1)} KB';
  final mb = kb / 1024;
  return '${mb.toStringAsFixed(mb >= 100 ? 0 : 1)} MB';
}

class NativeStatusService {
  static const _channel = MethodChannel('status_saver/native');

  Future<bool> hasFolder() async =>
      await _channel.invokeMethod<bool>('hasFolder') ?? false;

  Future<String?> folderLabel() =>
      _channel.invokeMethod<String>('getFolderLabel');

  Future<bool> selectFolder(String kind) async =>
      await _channel.invokeMethod<bool>('selectFolder', {'kind': kind}) ?? false;

  Future<List<StatusItem>> list() async {
    final raw = await _channel.invokeMethod<List<dynamic>>('listStatuses') ?? [];
    final items = raw
        .whereType<Map<dynamic, dynamic>>()
        .map((e) => StatusItem.fromMap(Map<Object?, Object?>.from(e)))
        .where((e) => e.uri.isNotEmpty)
        .toList();
    items.sort((a, b) => b.lastModified.compareTo(a.lastModified));
    return items;
  }

  Future<Uint8List?> thumbnail(StatusItem item, {int size = 520}) =>
      _channel.invokeMethod<Uint8List>('getThumbnail', {
        'uri': item.uri,
        'mimeType': item.mimeType,
        'size': size,
      });

  Future<String?> save(StatusItem item) =>
      _channel.invokeMethod<String>('saveStatus', {
        'uri': item.uri,
        'name': item.name,
        'mimeType': item.mimeType,
        'isVideo': item.isVideo,
      });

  Future<void> share(StatusItem item) =>
      _channel.invokeMethod<void>('shareStatus', {
        'uri': item.uri,
        'mimeType': item.mimeType,
      });

  Future<void> open(StatusItem item) =>
      _channel.invokeMethod<void>('openStatus', {
        'uri': item.uri,
        'mimeType': item.mimeType,
      });
}

class StatusSaverApp extends StatelessWidget {
  const StatusSaverApp({super.key});

  ThemeData _theme(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: _brand,
      brightness: brightness,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor:
          brightness == Brightness.light ? const Color(0xFFF7F8F7) : null,
      cardTheme: const CardThemeData(
        margin: EdgeInsets.zero,
        elevation: 0,
        clipBehavior: Clip.antiAlias,
      ),
      inputDecorationTheme: const InputDecorationTheme(filled: true),
    );
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'حافظ الحالات',
        theme: _theme(Brightness.light),
        darkTheme: _theme(Brightness.dark),
        themeMode: ThemeMode.system,
        home: const Directionality(
          textDirection: TextDirection.rtl,
          child: HomeScreen(),
        ),
      );
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final service = NativeStatusService();
  final thumbs = <String, Future<Uint8List?>>{};
  final selected = <String>{};
  final saving = <String>{};

  bool loading = true;
  bool refreshing = false;
  bool batchSaving = false;
  bool hasFolder = false;
  String label = '';
  String? error;
  int tab = 0;
  List<StatusItem> items = [];

  bool get selectionMode => selected.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool showSpinner = false}) async {
    if (showSpinner && mounted) setState(() => refreshing = true);
    try {
      final has = await service.hasFolder();
      final loaded = has ? await service.list() : <StatusItem>[];
      final folder = has ? await service.folderLabel() : null;
      if (!mounted) return;
      setState(() {
        hasFolder = has;
        items = loaded;
        label = folder ?? 'WhatsApp';
        error = null;
        loading = false;
        refreshing = false;
        thumbs.clear();
        selected.removeWhere((uri) => !loaded.any((e) => e.uri == uri));
      });
    } on PlatformException catch (e) {
      if (!mounted) return;
      setState(() {
        loading = false;
        refreshing = false;
        error = e.message ?? 'تعذر قراءة حالات واتساب';
      });
    }
  }

  Future<void> _select(String kind) async {
    try {
      final accepted = await service.selectFolder(kind);
      if (!accepted || !mounted) return;
      setState(() {
        loading = true;
        selected.clear();
      });
      await _load();
    } on PlatformException catch (e) {
      _message(e.message ?? 'تعذر اختيار المجلد');
    }
  }

  void _message(String text, {bool success = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(
                success ? Icons.check_circle_outline : Icons.info_outline,
                color: Colors.white,
              ),
              const SizedBox(width: 10),
              Expanded(child: Text(text)),
            ],
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  Future<bool?> _saveOne(StatusItem item, {bool silent = false}) async {
    if (saving.contains(item.uri)) return null;
    if (mounted) setState(() => saving.add(item.uri));
    try {
      final result = await service.save(item);
      final already = result == 'ALREADY_SAVED';
      if (!silent) {
        _message(
          already ? 'هذه الحالة محفوظة مسبقًا' : 'تم حفظ الحالة في المعرض',
          success: true,
        );
      }
      return !already;
    } on PlatformException catch (e) {
      if (!silent) _message(e.message ?? 'تعذر حفظ الحالة');
      return null;
    } finally {
      if (mounted) setState(() => saving.remove(item.uri));
    }
  }

  Future<void> _saveSelected() async {
    if (batchSaving || selected.isEmpty) return;
    final targets = items.where((e) => selected.contains(e.uri)).toList();
    setState(() => batchSaving = true);
    var savedCount = 0;
    var existingCount = 0;
    var failedCount = 0;
    for (final item in targets) {
      final result = await _saveOne(item, silent: true);
      if (result == true) {
        savedCount++;
      } else if (result == false) {
        existingCount++;
      } else {
        failedCount++;
      }
    }
    if (!mounted) return;
    setState(() {
      batchSaving = false;
      selected.clear();
    });
    final parts = <String>[];
    if (savedCount > 0) parts.add('تم حفظ $savedCount');
    if (existingCount > 0) parts.add('$existingCount محفوظة مسبقًا');
    if (failedCount > 0) parts.add('تعذر حفظ $failedCount');
    _message(parts.join(' • '), success: failedCount == 0);
  }

  void _toggleSelection(StatusItem item) {
    setState(() {
      if (!selected.add(item.uri)) selected.remove(item.uri);
    });
  }

  void _selectAllVisible() {
    final visible = filterStatuses(items, tab);
    setState(() {
      if (visible.every((e) => selected.contains(e.uri))) {
        for (final item in visible) {
          selected.remove(item.uri);
        }
      } else {
        selected.addAll(visible.map((e) => e.uri));
      }
    });
  }

  void _folderSheet() => showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (_) => Directionality(
          textDirection: TextDirection.rtl,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'اختر نسخة واتساب',
                    style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'ستظهر نافذة ملفات أندرويد داخل مجلد Media الصحيح. اختر “استخدام هذا المجلد”.',
                    style: TextStyle(
                      height: 1.5,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 18),
                  _sourceChoice(
                    title: 'WhatsApp العادي',
                    subtitle: 'com.whatsapp',
                    icon: Icons.chat_bubble_outline_rounded,
                    onTap: () {
                      Navigator.pop(context);
                      _select('whatsapp');
                    },
                  ),
                  const SizedBox(height: 10),
                  _sourceChoice(
                    title: 'WhatsApp Business',
                    subtitle: 'com.whatsapp.w4b',
                    icon: Icons.business_center_outlined,
                    onTap: () {
                      Navigator.pop(context);
                      _select('business');
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      );

  Widget _sourceChoice({
    required String title,
    required String subtitle,
    required IconData icon,
    required VoidCallback onTap,
  }) => Card(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        child: ListTile(
          onTap: onTap,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          leading: CircleAvatar(
            backgroundColor: Theme.of(context).colorScheme.primaryContainer,
            child: Icon(icon),
          ),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(subtitle, textDirection: TextDirection.ltr),
          trailing: const Icon(Icons.chevron_left_rounded),
        ),
      );

  @override
  Widget build(BuildContext context) {
    if (loading) return const _LoadingScreen();
    return Scaffold(
      appBar: selectionMode ? _selectionAppBar() : _normalAppBar(),
      body: SafeArea(child: hasFolder ? _gallery() : _setup()),
    );
  }

  PreferredSizeWidget _normalAppBar() => AppBar(
        title: const Text(
          'حافظ الحالات',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          if (hasFolder)
            IconButton(
              onPressed: refreshing ? null : () => _load(showSpinner: true),
              icon: refreshing
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh_rounded),
              tooltip: 'تحديث الحالات',
            ),
          IconButton(
            onPressed: _folderSheet,
            icon: const Icon(Icons.folder_open_rounded),
            tooltip: 'تغيير مصدر الحالات',
          ),
        ],
      );

  PreferredSizeWidget _selectionAppBar() => AppBar(
        leading: IconButton(
          onPressed: () => setState(selected.clear),
          icon: const Icon(Icons.close_rounded),
          tooltip: 'إلغاء التحديد',
        ),
        title: Text('${selected.length} محددة'),
        actions: [
          IconButton(
            onPressed: batchSaving ? null : _selectAllVisible,
            icon: const Icon(Icons.select_all_rounded),
            tooltip: 'تحديد الكل',
          ),
          IconButton(
            onPressed: batchSaving ? null : _saveSelected,
            icon: batchSaving
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.download_rounded),
            tooltip: 'حفظ المحدد',
          ),
        ],
      );

  Widget _setup() => ListView(
        padding: const EdgeInsets.fromLTRB(22, 18, 22, 28),
        children: [
          const SizedBox(height: 12),
          Center(
            child: Container(
              width: 116,
              height: 116,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                boxShadow: const [
                  BoxShadow(blurRadius: 24, offset: Offset(0, 10), color: Color(0x1F000000)),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: Image.asset('assets/app_icon.png', fit: BoxFit.cover),
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'احفظ حالات واتساب بسهولة',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 25, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          Text(
            'خصوصية كاملة: لا إنترنت، لا تسجيل دخول، ولا وصول شامل إلى ملفات هاتفك.',
            textAlign: TextAlign.center,
            style: TextStyle(
              height: 1.55,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          _step(1, 'شاهد الحالة داخل واتساب', 'الحالات التي لم تُفتح في واتساب قد لا تكون محفوظة على الهاتف.'),
          _step(2, 'اختر نسخة واتساب', 'سيطلب أندرويد إذن قراءة مجلد Media مرة واحدة فقط.'),
          _step(3, 'احفظ أو شارك', 'يمكنك تحديد عدة حالات وحفظها دفعة واحدة.'),
          const SizedBox(height: 22),
          FilledButton.icon(
            onPressed: _folderSheet,
            icon: const Icon(Icons.folder_open_rounded),
            label: const Padding(
              padding: EdgeInsets.symmetric(vertical: 13),
              child: Text('اختيار مجلد الحالات', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            ),
          ),
          if (error != null) ...[
            const SizedBox(height: 14),
            _errorCard(error!),
          ],
        ],
      );

  Widget _step(int number, String title, String subtitle) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              child: Text('$number', style: const TextStyle(fontWeight: FontWeight.w800)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      height: 1.45,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _gallery() {
    final visible = filterStatuses(items, tab);
    final imageCount = items.where((e) => !e.isVideo).length;
    final videoCount = items.length - imageCount;
    return RefreshIndicator(
      onRefresh: () => _load(showSpinner: true),
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
              child: Column(
                children: [
                  Card(
                    color: Theme.of(context).colorScheme.surfaceContainerLow,
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              CircleAvatar(
                                backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                                child: const Icon(Icons.folder_special_outlined),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('مصدر الحالات', style: TextStyle(fontSize: 12)),
                                    Text(
                                      label,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontWeight: FontWeight.w800),
                                    ),
                                  ],
                                ),
                              ),
                              TextButton(onPressed: _folderSheet, child: const Text('تغيير')),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(child: _countBox(Icons.photo_outlined, 'الصور', imageCount)),
                              const SizedBox(width: 8),
                              Expanded(child: _countBox(Icons.movie_outlined, 'الفيديو', videoCount)),
                              const SizedBox(width: 8),
                              Expanded(child: _countBox(Icons.collections_outlined, 'الكل', items.length)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<int>(
                      segments: const [
                        ButtonSegment(value: 0, label: Text('الكل')),
                        ButtonSegment(value: 1, label: Text('الصور')),
                        ButtonSegment(value: 2, label: Text('الفيديو')),
                      ],
                      selected: {tab},
                      showSelectedIcon: false,
                      onSelectionChanged: (v) => setState(() {
                        tab = v.first;
                        selected.clear();
                      }),
                    ),
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 10),
                    _errorCard(error!),
                  ],
                ],
              ),
            ),
          ),
          if (visible.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: _emptyState(),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 20),
              sliver: SliverLayoutBuilder(
                builder: (context, constraints) {
                  final width = constraints.crossAxisExtent;
                  final count = width >= 700 ? 5 : width >= 500 ? 4 : 3;
                  return SliverGrid(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: count,
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                      childAspectRatio: .77,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (_, i) => _card(visible[i]),
                      childCount: visible.length,
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _countBox(IconData icon, String label, int value) => Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: .55),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            Icon(icon, size: 19),
            const SizedBox(height: 4),
            Text('$value', style: const TextStyle(fontWeight: FontWeight.w900)),
            Text(label, style: const TextStyle(fontSize: 11)),
          ],
        ),
      );

  Widget _errorCard(String message) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Icon(Icons.error_outline_rounded, color: Theme.of(context).colorScheme.onErrorContainer),
            const SizedBox(width: 10),
            Expanded(child: Text(message)),
            TextButton(onPressed: _load, child: const Text('إعادة المحاولة')),
          ],
        ),
      );

  Widget _emptyState() {
    final text = switch (tab) {
      1 => 'لا توجد صور حالات حاليًا',
      2 => 'لا توجد فيديوهات حالات حاليًا',
      _ => 'لا توجد حالات متاحة حاليًا',
    };
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.hourglass_empty_rounded, size: 56, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 14),
            Text(text, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(
              'شاهد حالة داخل واتساب أولًا ثم ارجع إلى التطبيق واضغط تحديث.',
              textAlign: TextAlign.center,
              style: TextStyle(height: 1.5, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () => _load(showSpinner: true),
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('تحديث'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _card(StatusItem item) {
    final future = thumbs.putIfAbsent(item.uri, () => service.thumbnail(item));
    final isSelected = selected.contains(item.uri);
    final isSaving = saving.contains(item.uri);
    return Semantics(
      label: item.isVideo ? 'حالة فيديو' : 'حالة صورة',
      button: true,
      selected: isSelected,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Material(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: InkWell(
            onLongPress: () => _toggleSelection(item),
            onTap: () {
              if (selectionMode) {
                _toggleSelection(item);
              } else {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => Directionality(
                      textDirection: TextDirection.rtl,
                      child: PreviewScreen(item: item, service: service),
                    ),
                  ),
                );
              }
            },
            child: Stack(
              fit: StackFit.expand,
              children: [
                FutureBuilder<Uint8List?>(
                  future: future,
                  builder: (_, snap) {
                    if (snap.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
                    }
                    if (snap.data == null) {
                      return Icon(item.isVideo ? Icons.movie_outlined : Icons.image_outlined, size: 46);
                    }
                    return Image.memory(
                      snap.data!,
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                      filterQuality: FilterQuality.medium,
                    );
                  },
                ),
                if (item.isVideo)
                  const Center(
                    child: CircleAvatar(
                      backgroundColor: Color(0x99000000),
                      child: Icon(Icons.play_arrow_rounded, color: Colors.white),
                    ),
                  ),
                if (isSelected)
                  Positioned.fill(
                    child: ColoredBox(
                      color: Theme.of(context).colorScheme.primary.withValues(alpha: .26),
                    ),
                  ),
                PositionedDirectional(
                  top: 6,
                  end: 6,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 160),
                    child: isSelected
                        ? CircleAvatar(
                            key: const ValueKey('selected'),
                            radius: 14,
                            backgroundColor: Theme.of(context).colorScheme.primary,
                            child: const Icon(Icons.check_rounded, size: 18, color: Colors.white),
                          )
                        : const SizedBox.shrink(key: ValueKey('none')),
                  ),
                ),
                if (!selectionMode)
                  PositionedDirectional(
                    start: 6,
                    bottom: 6,
                    child: IconButton.filledTonal(
                      visualDensity: VisualDensity.compact,
                      tooltip: 'حفظ',
                      onPressed: isSaving ? null : () => _saveOne(item),
                      icon: isSaving
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.download_rounded, size: 19),
                    ),
                  ),
                if (item.size > 0)
                  PositionedDirectional(
                    end: 6,
                    bottom: 6,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: const Color(0x99000000),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                        child: Text(
                          formatFileSize(item.size),
                          style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: Image.asset('assets/app_icon.png', width: 88, height: 88),
                ),
                const SizedBox(height: 20),
                const CircularProgressIndicator(),
                const SizedBox(height: 12),
                Text('جاري تجهيز الحالات…', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
        ),
      );
}

class PreviewScreen extends StatefulWidget {
  const PreviewScreen({super.key, required this.item, required this.service});

  final StatusItem item;
  final NativeStatusService service;

  @override
  State<PreviewScreen> createState() => _PreviewScreenState();
}

class _PreviewScreenState extends State<PreviewScreen> {
  Uint8List? data;
  bool loading = true;
  bool saving = false;
  String? loadError;

  @override
  void initState() {
    super.initState();
    _loadPreview();
  }

  Future<void> _loadPreview() async {
    try {
      final value = await widget.service.thumbnail(widget.item, size: 1440);
      if (!mounted) return;
      setState(() {
        data = value;
        loading = false;
        loadError = value == null ? 'تعذر إنشاء معاينة لهذه الحالة' : null;
      });
    } on PlatformException catch (e) {
      if (!mounted) return;
      setState(() {
        loading = false;
        loadError = e.message ?? 'تعذر تحميل المعاينة';
      });
    }
  }

  void _message(String text, {bool success = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(text),
        ),
      );
  }

  Future<void> _save() async {
    if (saving) return;
    setState(() => saving = true);
    try {
      final result = await widget.service.save(widget.item);
      _message(
        result == 'ALREADY_SAVED' ? 'هذه الحالة محفوظة مسبقًا' : 'تم حفظ الحالة في المعرض',
        success: true,
      );
    } on PlatformException catch (e) {
      _message(e.message ?? 'تعذر الحفظ');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> _share() async {
    try {
      await widget.service.share(widget.item);
    } on PlatformException catch (e) {
      _message(e.message ?? 'تعذر فتح المشاركة');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: const Color(0xFF0B0F0D),
        appBar: AppBar(
          backgroundColor: const Color(0xFF0B0F0D),
          foregroundColor: Colors.white,
          title: Text(
            widget.item.isVideo ? 'معاينة الفيديو' : 'معاينة الصورة',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        body: Column(
          children: [
            Expanded(
              child: Center(
                child: loading
                    ? const CircularProgressIndicator()
                    : loadError != null
                        ? Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.broken_image_outlined, color: Colors.white70, size: 56),
                                const SizedBox(height: 12),
                                Text(loadError!, style: const TextStyle(color: Colors.white70), textAlign: TextAlign.center),
                                const SizedBox(height: 14),
                                OutlinedButton(onPressed: _loadPreview, child: const Text('إعادة المحاولة')),
                              ],
                            ),
                          )
                        : Stack(
                            alignment: Alignment.center,
                            children: [
                              if (data != null)
                                InteractiveViewer(
                                  minScale: .8,
                                  maxScale: 4,
                                  child: Image.memory(data!, fit: BoxFit.contain, gaplessPlayback: true),
                                ),
                              if (widget.item.isVideo)
                                IconButton.filled(
                                  onPressed: () async {
                                    try {
                                      await widget.service.open(widget.item);
                                    } on PlatformException catch (e) {
                                      _message(e.message ?? 'تعذر فتح الفيديو');
                                    }
                                  },
                                  iconSize: 58,
                                  tooltip: 'تشغيل الفيديو',
                                  icon: const Icon(Icons.play_arrow_rounded),
                                ),
                            ],
                          ),
              ),
            ),
            Container(
              decoration: const BoxDecoration(
                color: Color(0xFF111815),
                border: Border(top: BorderSide(color: Color(0xFF26322D))),
              ),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: saving ? null : _save,
                          icon: saving
                              ? const SizedBox.square(
                                  dimension: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.download_rounded),
                          label: const Text('حفظ'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(foregroundColor: Colors.white),
                          onPressed: _share,
                          icon: const Icon(Icons.share_outlined),
                          label: const Text('مشاركة'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      );
}
