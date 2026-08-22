import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'local_share_service.dart';
import 'models.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const LocalShareApp());
}

class LocalShareApp extends StatelessWidget {
  const LocalShareApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF3569F2);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'LocalShare',
      locale: const Locale('ar'),
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.light),
        scaffoldBackgroundColor: const Color(0xFFF7F8FC),
        cardTheme: const CardThemeData(
          elevation: 0,
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFE5E8F0)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: seed, width: 1.6),
          ),
        ),
      ),
      home: const Directionality(
        textDirection: TextDirection.rtl,
        child: LocalShareShell(),
      ),
    );
  }
}

class LocalShareShell extends StatefulWidget {
  const LocalShareShell({super.key});

  @override
  State<LocalShareShell> createState() => _LocalShareShellState();
}

class _LocalShareShellState extends State<LocalShareShell> {
  late final LocalShareService service;
  int pageIndex = 0;

  @override
  void initState() {
    super.initState();
    service = LocalShareService();
    service.init();
  }

  @override
  void dispose() {
    service.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: service,
      builder: (context, _) {
        if (!service.initialized) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (service.startupError != null) {
          return Scaffold(
            body: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: _ErrorCard(message: service.startupError!),
                ),
              ),
            ),
          );
        }

        final wide = MediaQuery.sizeOf(context).width >= 850;
        final pages = [
          _HomePage(service: service),
          _ReceivedPage(service: service),
          _SettingsPage(service: service),
        ];

        if (wide) {
          return Scaffold(
            body: SafeArea(
              child: Row(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(14),
                    child: NavigationRail(
                      backgroundColor: Colors.white,
                      selectedIndex: pageIndex,
                      onDestinationSelected: (value) => setState(() => pageIndex = value),
                      labelType: NavigationRailLabelType.all,
                      leading: const Padding(
                        padding: EdgeInsets.only(bottom: 18),
                        child: _AppMark(),
                      ),
                      destinations: const [
                        NavigationRailDestination(
                          icon: Icon(Icons.devices_outlined),
                          selectedIcon: Icon(Icons.devices_rounded),
                          label: Text('الأجهزة'),
                        ),
                        NavigationRailDestination(
                          icon: Icon(Icons.folder_copy_outlined),
                          selectedIcon: Icon(Icons.folder_copy_rounded),
                          label: Text('المستلمة'),
                        ),
                        NavigationRailDestination(
                          icon: Icon(Icons.settings_outlined),
                          selectedIcon: Icon(Icons.settings_rounded),
                          label: Text('الإعدادات'),
                        ),
                      ],
                    ),
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(child: pages[pageIndex]),
                ],
              ),
            ),
          );
        }

        return Scaffold(
          body: SafeArea(child: pages[pageIndex]),
          bottomNavigationBar: NavigationBar(
            selectedIndex: pageIndex,
            onDestinationSelected: (value) => setState(() => pageIndex = value),
            destinations: const [
              NavigationDestination(icon: Icon(Icons.devices_outlined), selectedIcon: Icon(Icons.devices), label: 'الأجهزة'),
              NavigationDestination(icon: Icon(Icons.folder_copy_outlined), selectedIcon: Icon(Icons.folder_copy), label: 'المستلمة'),
              NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: 'الإعدادات'),
            ],
          ),
        );
      },
    );
  }
}

class _HomePage extends StatelessWidget {
  const _HomePage({required this.service});
  final LocalShareService service;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
          sliver: SliverToBoxAdapter(child: _TopBar(service: service)),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
          sliver: SliverToBoxAdapter(child: _MyDeviceCard(service: service)),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 26, 20, 10),
          sliver: SliverToBoxAdapter(
            child: _SectionHeader(
              title: 'الأجهزة القريبة',
              subtitle: service.discoveryAvailable
                  ? 'يتم البحث تلقائيًا داخل نفس شبكة Wi‑Fi'
                  : 'الاكتشاف التلقائي غير متاح؛ استخدم الربط اليدوي',
              trailing: TextButton.icon(
                onPressed: () => _showManualIpDialog(context, service),
                icon: const Icon(Icons.add_link_rounded),
                label: const Text('ربط يدوي'),
              ),
            ),
          ),
        ),
        if (service.discoveredDevices.isEmpty)
          const SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            sliver: SliverToBoxAdapter(child: _EmptyDevices()),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            sliver: SliverList.separated(
              itemCount: service.discoveredDevices.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final device = service.discoveredDevices[index];
                final peer = service.peerFor(device.deviceId);
                return _DeviceCard(service: service, device: device, peer: peer);
              },
            ),
          ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 28, 20, 10),
          sliver: SliverToBoxAdapter(
            child: _SectionHeader(
              title: 'آخر عمليات النقل',
              subtitle: 'الإرسال يتم مباشرة بين الجهازين بدون رفع الملفات للسحابة',
            ),
          ),
        ),
        if (service.transfers.isEmpty)
          const SliverPadding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 30),
            sliver: SliverToBoxAdapter(child: _EmptyTransfers()),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 30),
            sliver: SliverList.separated(
              itemCount: service.transfers.take(12).length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) => _TransferTile(item: service.transfers[index]),
            ),
          ),
      ],
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.service});
  final LocalShareService service;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const _AppMark(),
        const SizedBox(width: 12),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('LocalShare', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 22)),
              SizedBox(height: 2),
              Text('مشاركة ملفات سريعة داخل الشبكة المحلية', style: TextStyle(color: Color(0xFF747B8E))),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFFEAF8EF),
            borderRadius: BorderRadius.circular(30),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_outline_rounded, size: 16, color: Color(0xFF208A4B)),
              SizedBox(width: 6),
              Text('محلي', style: TextStyle(color: Color(0xFF208A4B), fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ],
    );
  }
}

class _MyDeviceCard extends StatelessWidget {
  const _MyDeviceCard({required this.service});
  final LocalShareService service;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFF2E5EE8), Color(0xFF4D7CFA)]),
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [BoxShadow(color: Color(0x1A2E5EE8), blurRadius: 26, offset: Offset(0, 12))],
      ),
      padding: const EdgeInsets.all(20),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 560;
          final identity = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(color: Colors.white.withValues(alpha: .16), borderRadius: BorderRadius.circular(14)),
                    child: Icon(Platform.isWindows ? Icons.computer_rounded : Icons.smartphone_rounded, color: Colors.white),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(service.deviceName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18)),
                        const SizedBox(height: 3),
                        Text('IP: ${service.localIp}', style: TextStyle(color: Colors.white.withValues(alpha: .75))),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'تعديل الاسم',
                    onPressed: () => _renameDevice(context, service),
                    icon: const Icon(Icons.edit_outlined, color: Colors.white),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                'افتح LocalShare على الجهاز الآخر ثم اختر هذا الجهاز وأدخل رمز الربط مرة واحدة فقط.',
                style: TextStyle(color: Colors.white.withValues(alpha: .83), height: 1.45),
              ),
            ],
          );
          final code = Container(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('رمز الربط', style: TextStyle(color: Color(0xFF70788B), fontSize: 12, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Directionality(
                  textDirection: TextDirection.ltr,
                  child: SelectableText(service.pairCode, style: const TextStyle(fontSize: 27, fontWeight: FontWeight.w900, letterSpacing: 4)),
                ),
              ],
            ),
          );
          if (compact) {
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [identity, const SizedBox(height: 16), code]);
          }
          return Row(children: [Expanded(child: identity), const SizedBox(width: 22), code]);
        },
      ),
    );
  }
}

class _DeviceCard extends StatelessWidget {
  const _DeviceCard({required this.service, required this.device, required this.peer});
  final LocalShareService service;
  final DiscoveredDevice device;
  final Peer? peer;

  @override
  Widget build(BuildContext context) {
    final paired = peer != null;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE7EAF1)),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(color: const Color(0xFFF0F4FF), borderRadius: BorderRadius.circular(14)),
            child: const Icon(Icons.devices_rounded, color: Color(0xFF3569F2)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(child: Text(device.name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
                    const SizedBox(width: 8),
                    Container(
                      width: 7,
                      height: 7,
                      decoration: const BoxDecoration(color: Color(0xFF33B86B), shape: BoxShape.circle),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Directionality(
                  textDirection: TextDirection.ltr,
                  child: Text('${device.ip}:${device.port}', textAlign: TextAlign.left, style: const TextStyle(color: Color(0xFF7B8293), fontSize: 12)),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          if (paired)
            FilledButton.icon(
              onPressed: () => _sendFiles(context, service, peer!),
              icon: const Icon(Icons.send_rounded, size: 18),
              label: const Text('إرسال ملف'),
            )
          else
            FilledButton.tonalIcon(
              onPressed: () => _pair(context, service, device),
              icon: const Icon(Icons.link_rounded, size: 18),
              label: const Text('ربط'),
            ),
          if (paired) ...[
            const SizedBox(width: 4),
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'forget') service.forgetPeer(device.deviceId);
              },
              itemBuilder: (_) => const [PopupMenuItem(value: 'forget', child: Text('نسيان الجهاز'))],
            ),
          ],
        ],
      ),
    );
  }
}

class _TransferTile extends StatelessWidget {
  const _TransferTile({required this.item});
  final TransferItem item;

  @override
  Widget build(BuildContext context) {
    final sending = item.direction == TransferDirection.send;
    final running = item.status == TransferStatus.running;
    final failed = item.status == TransferStatus.failed;
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFE9EBF2))),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: failed ? const Color(0xFFFFEEEE) : const Color(0xFFF0F4FF),
            foregroundColor: failed ? Colors.red : const Color(0xFF3569F2),
            child: Icon(failed ? Icons.error_outline : sending ? Icons.north_east_rounded : Icons.south_west_rounded),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.fileName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(
                  '${sending ? 'إلى' : 'من'} ${item.peerName} • ${formatBytes(item.totalBytes)}',
                  style: const TextStyle(color: Color(0xFF7B8293), fontSize: 12),
                ),
                if (running) ...[
                  const SizedBox(height: 9),
                  LinearProgressIndicator(value: item.totalBytes > 0 ? item.progress : null, minHeight: 5, borderRadius: BorderRadius.circular(9)),
                ],
                if (failed && item.error != null) ...[
                  const SizedBox(height: 5),
                  Text(item.error!, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.red, fontSize: 11)),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            failed ? 'فشل' : running ? '${(item.progress * 100).round()}%' : 'تم',
            style: TextStyle(fontWeight: FontWeight.w800, color: failed ? Colors.red : running ? const Color(0xFF3569F2) : const Color(0xFF208A4B)),
          ),
        ],
      ),
    );
  }
}

class _ReceivedPage extends StatelessWidget {
  const _ReceivedPage({required this.service});
  final LocalShareService service;

  @override
  Widget build(BuildContext context) {
    final refreshKey = '${service.transfers.length}-${service.transfers.where((e) => e.status == TransferStatus.completed).length}';
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _PageTitle(title: 'الملفات المستلمة', subtitle: 'كل الملفات تبقى محليًا على جهازك حتى تقوم بحذفها بنفسك.'),
          const SizedBox(height: 18),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: const Color(0xFFEDF3FF), borderRadius: BorderRadius.circular(16)),
            child: Row(
              children: [
                const Icon(Icons.folder_outlined, color: Color(0xFF3569F2)),
                const SizedBox(width: 10),
                Expanded(child: Text('مجلد الاستقبال: ${service.receiveDirectory.path}', maxLines: 2, overflow: TextOverflow.ellipsis)),
                IconButton(
                  tooltip: 'نسخ المسار',
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: service.receiveDirectory.path));
                    if (context.mounted) _toast(context, 'تم نسخ المسار');
                  },
                  icon: const Icon(Icons.copy_rounded),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: FutureBuilder<List<FileSystemEntity>>(
              key: ValueKey(refreshKey),
              future: service.receivedFiles(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                final files = snapshot.data ?? const [];
                if (files.isEmpty) {
                  return const Center(child: _EmptyReceived());
                }
                return ListView.separated(
                  itemCount: files.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 9),
                  itemBuilder: (context, index) {
                    final file = files[index] as File;
                    final stat = file.statSync();
                    return Container(
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFE7EAF1))),
                      child: ListTile(
                        leading: const CircleAvatar(backgroundColor: Color(0xFFF0F4FF), child: Icon(Icons.insert_drive_file_outlined, color: Color(0xFF3569F2))),
                        title: Text(file.uri.pathSegments.last, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text(formatBytes(stat.size)),
                        trailing: FilledButton.tonalIcon(
                          icon: const Icon(Icons.save_alt_rounded, size: 18),
                          label: Text(Platform.isAndroid ? 'حفظ في التنزيلات' : 'حفظ نسخة'),
                          onPressed: () async {
                            try {
                              final path = await service.exportReceivedFile(file);
                              if (path.isNotEmpty && context.mounted) _toast(context, 'تم الحفظ بنجاح');
                            } catch (e) {
                              if (context.mounted) _toast(context, 'تعذر الحفظ: $e', error: true);
                            }
                          },
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsPage extends StatelessWidget {
  const _SettingsPage({required this.service});
  final LocalShareService service;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const _PageTitle(title: 'الإعدادات', subtitle: 'إعدادات الربط والتخزين المحلي.'),
        const SizedBox(height: 18),
        _SettingsTile(
          icon: Icons.badge_outlined,
          title: 'اسم هذا الجهاز',
          subtitle: service.deviceName,
          onTap: () => _renameDevice(context, service),
        ),
        const SizedBox(height: 10),
        _SettingsTile(
          icon: Icons.lan_outlined,
          title: 'عنوان الشبكة المحلي',
          subtitle: '${service.localIp}:${LocalShareService.serverPort}',
          onTap: () async {
            await Clipboard.setData(ClipboardData(text: service.localIp));
            if (context.mounted) _toast(context, 'تم نسخ عنوان IP');
          },
        ),
        const SizedBox(height: 10),
        _SettingsTile(
          icon: Icons.folder_outlined,
          title: 'مكان حفظ الملفات',
          subtitle: service.receiveDirectory.path,
          onTap: () async {
            await Clipboard.setData(ClipboardData(text: service.receiveDirectory.path));
            if (context.mounted) _toast(context, 'تم نسخ المسار');
          },
        ),
        const SizedBox(height: 22),
        const Text('الأجهزة المرتبطة', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        const SizedBox(height: 10),
        if (service.pairedPeers.isEmpty)
          const Text('لا توجد أجهزة مرتبطة حتى الآن.', style: TextStyle(color: Color(0xFF747B8E)))
        else
          ...service.pairedPeers.map(
            (peer) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Container(
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15), border: Border.all(color: const Color(0xFFE7EAF1))),
                child: ListTile(
                  leading: Icon(service.isOnline(peer.deviceId) ? Icons.link_rounded : Icons.link_off_rounded),
                  title: Text(peer.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(peer.ip),
                  trailing: TextButton(onPressed: () => service.forgetPeer(peer.deviceId), child: const Text('نسيان')),
                ),
              ),
            ),
          ),
        const SizedBox(height: 26),
        const _PrivacyNote(),
      ],
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({required this.icon, required this.title, required this.subtitle, required this.onTap});
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFE7EAF1))),
        child: Row(
          children: [
            CircleAvatar(backgroundColor: const Color(0xFFF0F4FF), child: Icon(icon, color: const Color(0xFF3569F2))),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 3),
                  Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFF747B8E), fontSize: 12)),
                ],
              ),
            ),
            const Icon(Icons.chevron_left_rounded),
          ],
        ),
      ),
    );
  }
}

class _PrivacyNote extends StatelessWidget {
  const _PrivacyNote();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: const Color(0xFFEAF8EF), borderRadius: BorderRadius.circular(16)),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.verified_user_outlined, color: Color(0xFF208A4B)),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'لا يستخدم LocalShare أي خادم سحابي. أسماء الأجهزة ورموز الثقة تحفظ محليًا، والملفات تنتقل مباشرة عبر شبكة Wi‑Fi المحلية.',
              style: TextStyle(color: Color(0xFF206E42), height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _PageTitle extends StatelessWidget {
  const _PageTitle({required this.title, required this.subtitle});
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w900)),
        const SizedBox(height: 4),
        Text(subtitle, style: const TextStyle(color: Color(0xFF747B8E))),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.subtitle, this.trailing});
  final String title;
  final String subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
              const SizedBox(height: 3),
              Text(subtitle, style: const TextStyle(color: Color(0xFF747B8E), fontSize: 12)),
            ],
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

class _AppMark extends StatelessWidget {
  const _AppMark();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFF3569F2), Color(0xFF6B8DFC)]),
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Icon(Icons.swap_horiz_rounded, color: Colors.white, size: 29),
    );
  }
}

class _EmptyDevices extends StatelessWidget {
  const _EmptyDevices();

  @override
  Widget build(BuildContext context) {
    return const _EmptyBox(
      icon: Icons.radar_rounded,
      title: 'نبحث عن أجهزتك…',
      subtitle: 'افتح LocalShare على الجوال والكمبيوتر وتأكد أنهما على نفس شبكة Wi‑Fi.',
    );
  }
}

class _EmptyTransfers extends StatelessWidget {
  const _EmptyTransfers();

  @override
  Widget build(BuildContext context) {
    return const _EmptyBox(
      icon: Icons.swap_vert_rounded,
      title: 'لا توجد عمليات نقل بعد',
      subtitle: 'بعد ربط جهاز قريب اضغط «إرسال ملف» واختر أي ملف من جهازك.',
    );
  }
}

class _EmptyReceived extends StatelessWidget {
  const _EmptyReceived();

  @override
  Widget build(BuildContext context) {
    return const _EmptyBox(
      icon: Icons.inbox_outlined,
      title: 'لم تستلم ملفات بعد',
      subtitle: 'ستظهر الملفات هنا فور وصولها من جهاز مرتبط.',
    );
  }
}

class _EmptyBox extends StatelessWidget {
  const _EmptyBox({required this.icon, required this.title, required this.subtitle});
  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: const Color(0xFFE7EAF1))),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 34, color: const Color(0xFF8690A4)),
          const SizedBox(height: 10),
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 5),
          Text(subtitle, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFF747B8E), height: 1.4)),
        ],
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFFFFD8D8))),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline_rounded, color: Colors.red, size: 42),
          const SizedBox(height: 12),
          const Text('تعذر تشغيل خدمة المشاركة', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
          const SizedBox(height: 8),
          SelectableText(message, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

Future<void> _sendFiles(BuildContext context, LocalShareService service, Peer peer) async {
  try {
    await service.pickAndSend(peer);
  } catch (e) {
    if (context.mounted) _toast(context, 'فشل الإرسال: $e', error: true);
  }
}

Future<void> _pair(BuildContext context, LocalShareService service, DiscoveredDevice device) async {
  final controller = TextEditingController();
  final code = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('ربط مع ${device.name}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('أدخل رمز الربط المكوّن من 6 أرقام الظاهر على الجهاز الآخر.'),
          const SizedBox(height: 14),
          Directionality(
            textDirection: TextDirection.ltr,
            child: TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.number,
              maxLength: 6,
              textAlign: TextAlign.center,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: 4),
              onSubmitted: (value) {
                if (value.length == 6) Navigator.pop(context, value);
              },
            ),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
        FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('ربط')),
      ],
    ),
  );
  controller.dispose();
  if (code == null || code.length != 6) return;
  try {
    await service.pairDevice(device, code);
    if (context.mounted) _toast(context, 'تم ربط الجهازين بنجاح');
  } catch (e) {
    if (context.mounted) _toast(context, '$e', error: true);
  }
}

Future<void> _showManualIpDialog(BuildContext context, LocalShareService service) async {
  final controller = TextEditingController();
  final ip = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('ربط يدوي'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('اكتب عنوان IP الظاهر داخل LocalShare على الجهاز الآخر.'),
          const SizedBox(height: 12),
          Directionality(
            textDirection: TextDirection.ltr,
            child: TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(hintText: '192.168.1.20'),
              onSubmitted: (value) => Navigator.pop(context, value),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
        FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('بحث')),
      ],
    ),
  );
  controller.dispose();
  if (ip == null || ip.trim().isEmpty) return;
  try {
    await service.probeIp(ip);
    if (context.mounted) _toast(context, 'تم العثور على الجهاز');
  } catch (e) {
    if (context.mounted) _toast(context, 'لم يتم العثور على LocalShare في هذا العنوان', error: true);
  }
}

Future<void> _renameDevice(BuildContext context, LocalShareService service) async {
  final controller = TextEditingController(text: service.deviceName);
  final result = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('اسم الجهاز'),
      content: TextField(
        controller: controller,
        autofocus: true,
        maxLength: 32,
        onSubmitted: (value) => Navigator.pop(context, value),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
        FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('حفظ')),
      ],
    ),
  );
  controller.dispose();
  if (result != null) await service.setDeviceName(result);
}

void _toast(BuildContext context, String message, {bool error = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? Colors.red.shade700 : null,
        behavior: SnackBarBehavior.floating,
      ),
    );
}
