import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() => runApp(const StatusSaverApp());

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

class NativeStatusService {
  static const _channel = MethodChannel('status_saver/native');

  Future<bool> hasFolder() async =>
      await _channel.invokeMethod<bool>('hasFolder') ?? false;
  Future<String?> folderLabel() => _channel.invokeMethod<String>('getFolderLabel');
  Future<bool> selectFolder(String kind) async =>
      await _channel.invokeMethod<bool>('selectFolder', {'kind': kind}) ?? false;

  Future<List<StatusItem>> list() async {
    final raw = await _channel.invokeMethod<List<dynamic>>('listStatuses') ?? [];
    final items = raw
        .whereType<Map<dynamic, dynamic>>()
        .map((e) => StatusItem.fromMap(Map<Object?, Object?>.from(e)))
        .toList();
    items.sort((a, b) => b.lastModified.compareTo(a.lastModified));
    return items;
  }

  Future<Uint8List?> thumbnail(StatusItem item) =>
      _channel.invokeMethod<Uint8List>('getThumbnail', {
        'uri': item.uri,
        'mimeType': item.mimeType,
      });
  Future<Uint8List?> bytes(StatusItem item) =>
      _channel.invokeMethod<Uint8List>('readBytes', {'uri': item.uri});
  Future<String?> save(StatusItem item) => _channel.invokeMethod<String>('saveStatus', {
        'uri': item.uri,
        'name': item.name,
        'mimeType': item.mimeType,
        'isVideo': item.isVideo,
      });
  Future<void> share(StatusItem item) => _channel.invokeMethod<void>('shareStatus', {
        'uri': item.uri,
        'mimeType': item.mimeType,
      });
  Future<void> open(StatusItem item) => _channel.invokeMethod<void>('openStatus', {
        'uri': item.uri,
        'mimeType': item.mimeType,
      });
}

class StatusSaverApp extends StatelessWidget {
  const StatusSaverApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'حافظ الحالات',
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF25D366)),
          scaffoldBackgroundColor: const Color(0xFFF6F7F9),
        ),
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
  bool loading = true;
  bool hasFolder = false;
  String label = '';
  String? error;
  int tab = 0;
  List<StatusItem> items = [];
  final thumbs = <String, Future<Uint8List?>>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
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
        thumbs.clear();
      });
    } on PlatformException catch (e) {
      if (!mounted) return;
      setState(() {
        loading = false;
        error = e.message ?? 'تعذر قراءة حالات واتساب';
      });
    }
  }

  Future<void> _select(String kind) async {
    try {
      if (await service.selectFolder(kind)) {
        setState(() => loading = true);
        await _load();
      }
    } on PlatformException catch (e) {
      _message(e.message ?? 'تعذر اختيار المجلد');
    }
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _save(StatusItem item) async {
    try {
      await service.save(item);
      _message('تم حفظ الحالة في المعرض');
    } on PlatformException catch (e) {
      _message(e.message ?? 'تعذر حفظ الحالة');
    }
  }

  void _folderSheet() => showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (_) => Directionality(
          textDirection: TextDirection.rtl,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Text('اختيار مصدر الحالات',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 14),
                FilledButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    _select('whatsapp');
                  },
                  icon: const Icon(Icons.chat),
                  label: const Text('WhatsApp العادي'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    _select('business');
                  },
                  icon: const Icon(Icons.business_center),
                  label: const Text('WhatsApp Business'),
                ),
              ]),
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('حافظ الحالات', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          if (hasFolder)
            IconButton(onPressed: _load, icon: const Icon(Icons.refresh), tooltip: 'تحديث'),
          IconButton(onPressed: _folderSheet, icon: const Icon(Icons.folder_open), tooltip: 'المجلد'),
        ],
      ),
      body: SafeArea(child: hasFolder ? _gallery() : _setup()),
    );
  }

  Widget _setup() => ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 45),
          const CircleAvatar(
            radius: 54,
            backgroundColor: Color(0xFFE3F8EB),
            child: Icon(Icons.download_for_offline, size: 62, color: Color(0xFF128C7E)),
          ),
          const SizedBox(height: 28),
          const Text('احفظ حالات واتساب التي أعجبتك',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
          const SizedBox(height: 12),
          Text(
            'شاهد الحالة في واتساب أولًا، ثم اختر مجلد Media أو .Statuses. التطبيق لا يحتاج إلى الإنترنت ولا يطلب صلاحية الوصول لكل ملفات الهاتف.',
            textAlign: TextAlign.center,
            style: TextStyle(height: 1.6, color: Colors.grey.shade700),
          ),
          const SizedBox(height: 28),
          _sourceButton('اختيار واتساب العادي', Icons.chat, () => _select('whatsapp')),
          const SizedBox(height: 10),
          _sourceButton('اختيار واتساب الأعمال', Icons.business_center, () => _select('business')),
          const SizedBox(height: 18),
          const Card(
            child: Padding(
              padding: EdgeInsets.all(14),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.privacy_tip_outlined, color: Color(0xFF128C7E)),
                SizedBox(width: 10),
                Expanded(child: Text('كل المعالجة محلية على جهازك، ولا يتم رفع الحالات إلى أي خادم.')),
              ]),
            ),
          ),
          if (error != null) ...[
            const SizedBox(height: 12),
            Text(error!, style: const TextStyle(color: Colors.red), textAlign: TextAlign.center),
          ],
        ],
      );

  Widget _sourceButton(String text, IconData icon, VoidCallback onTap) =>
      FilledButton.icon(onPressed: onTap, icon: Icon(icon), label: Text(text));

  Widget _gallery() {
    final visible = filterStatuses(items, tab);
    return RefreshIndicator(
      onRefresh: _load,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
              child: Column(children: [
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.folder_special, color: Color(0xFF128C7E)),
                    title: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: Text('${items.length} حالة',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(height: 10),
                SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(value: 0, label: Text('الكل')),
                    ButtonSegment(value: 1, label: Text('الصور')),
                    ButtonSegment(value: 2, label: Text('الفيديو')),
                  ],
                  selected: {tab},
                  onSelectionChanged: (v) => setState(() => tab = v.first),
                ),
                if (error != null) ...[
                  const SizedBox(height: 8),
                  Text(error!, style: const TextStyle(color: Colors.red)),
                ],
              ]),
            ),
          ),
          if (visible.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: Text('لا توجد حالات. شاهد حالات واتساب ثم اضغط تحديث.')),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.all(10),
              sliver: SliverGrid.builder(
                itemCount: visible.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 7,
                  crossAxisSpacing: 7,
                  childAspectRatio: .76,
                ),
                itemBuilder: (_, i) => _card(visible[i]),
              ),
            ),
        ],
      ),
    );
  }

  Widget _card(StatusItem item) {
    final future = thumbs.putIfAbsent(item.uri, () => service.thumbnail(item));
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Material(
        color: Colors.grey.shade200,
        child: InkWell(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => Directionality(
                textDirection: TextDirection.rtl,
                child: PreviewScreen(item: item, service: service),
              ),
            ),
          ),
          child: Stack(fit: StackFit.expand, children: [
            FutureBuilder<Uint8List?>(
              future: future,
              builder: (_, snap) => snap.data == null
                  ? Icon(item.isVideo ? Icons.movie : Icons.image, size: 45)
                  : Image.memory(snap.data!, fit: BoxFit.cover),
            ),
            if (item.isVideo)
              const Center(child: CircleAvatar(backgroundColor: Colors.black54, child: Icon(Icons.play_arrow, color: Colors.white))),
            PositionedDirectional(
              start: 5,
              bottom: 5,
              child: IconButton.filledTonal(
                visualDensity: VisualDensity.compact,
                onPressed: () => _save(item),
                icon: const Icon(Icons.download, size: 19),
              ),
            ),
          ]),
        ),
      ),
    );
  }
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

  @override
  void initState() {
    super.initState();
    (widget.item.isVideo ? widget.service.thumbnail(widget.item) : widget.service.bytes(widget.item))
        .then((v) {
      if (mounted) {
        setState(() { data = v; loading = false; });
      }
    });
  }

  void _message(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: const Color(0xFF0D1117),
        appBar: AppBar(
          backgroundColor: const Color(0xFF0D1117),
          foregroundColor: Colors.white,
          title: Text(widget.item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
        body: Column(children: [
          Expanded(
            child: Center(
              child: loading
                  ? const CircularProgressIndicator()
                  : Stack(alignment: Alignment.center, children: [
                      if (data != null) Image.memory(data!, fit: BoxFit.contain),
                      if (widget.item.isVideo)
                        IconButton.filled(
                          onPressed: () => widget.service.open(widget.item),
                          iconSize: 58,
                          icon: const Icon(Icons.play_arrow),
                        ),
                    ]),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () async {
                      try {
                        await widget.service.save(widget.item);
                        _message('تم حفظ الحالة في المعرض');
                      } on PlatformException catch (e) {
                        _message(e.message ?? 'تعذر الحفظ');
                      }
                    },
                    icon: const Icon(Icons.download),
                    label: const Text('حفظ'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(foregroundColor: Colors.white),
                    onPressed: () => widget.service.share(widget.item),
                    icon: const Icon(Icons.share),
                    label: const Text('مشاركة'),
                  ),
                ),
              ]),
            ),
          ),
        ]),
      );
}
