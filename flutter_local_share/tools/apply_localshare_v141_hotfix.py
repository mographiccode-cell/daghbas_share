from pathlib import Path

root = Path(__file__).resolve().parents[1]
main_path = root / 'lib' / 'main.dart'
service_path = root / 'lib' / 'chat_local_share_service.dart'

main = main_path.read_text(encoding='utf-8')
service = service_path.read_text(encoding='utf-8')

old_init = """    _nativeShareChannel.setMethodCallHandler(_handleNativeShareMethod);
    unawaited(service.init().then((_) => _consumePendingAndroidShares()));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(notifications.requestPermission());
    });
"""
new_init = """    _nativeShareChannel.setMethodCallHandler(_handleNativeShareMethod);
    unawaited(service.init().then((_) => _consumePendingAndroidShares()));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_startPostLaunchServices());
    });
"""
if old_init in main:
    main = main.replace(old_init, new_init, 1)

marker = """  @override
  void onWindowClose() async {
"""
insert = """  Future<void> _startPostLaunchServices() async {
    await notifications.requestPermission();
    if (Platform.isAndroid) {
      await LocalShareRuntimeKeepAlive.enableAndroidBackgroundAfterLaunch();
    }
  }

"""
if insert not in main:
    if marker not in main:
        raise SystemExit('main marker missing')
    main = main.replace(marker, insert + marker, 1)

old_ip = """  Future<String> _bestLocalIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      final addresses = <String>[];
      for (final interface in interfaces) {
        for (final address in interface.addresses) {
          if (!address.isLoopback) addresses.add(address.address);
        }
      }
      for (final ip in addresses) {
        if (_isPrivateIp(ip)) return ip;
      }
      if (addresses.isNotEmpty) return addresses.first;
    } catch (_) {}
    return '—';
  }
"""
new_ip = """  Future<String> _bestLocalIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      final candidates = <({String ip, int score})>[];
      for (final interface in interfaces) {
        final name = interface.name.toLowerCase();
        final virtual = name.contains('wsl') ||
            name.contains('vethernet') ||
            name.contains('docker') ||
            name.contains('vmware') ||
            name.contains('virtualbox') ||
            name.contains('tailscale') ||
            name.contains('zerotier') ||
            name.contains('vpn');
        var interfaceScore = 0;
        if (name.contains('wi-fi') || name.contains('wifi') || name.contains('wlan')) {
          interfaceScore += 120;
        } else if (name.contains('ethernet') || name.startsWith('eth')) {
          interfaceScore += 90;
        }
        if (virtual) interfaceScore -= 250;
        for (final address in interface.addresses) {
          final ip = address.address;
          if (address.isLoopback || !_isPrivateIp(ip)) continue;
          var score = interfaceScore;
          if (ip.startsWith('192.168.')) {
            score += 45;
          } else if (ip.startsWith('10.')) {
            score += 30;
          } else {
            score += 20;
          }
          candidates.add((ip: ip, score: score));
        }
      }
      if (candidates.isNotEmpty) {
        candidates.sort((a, b) => b.score.compareTo(a.score));
        return candidates.first.ip;
      }
    } catch (_) {}
    return '—';
  }
"""
if old_ip in service:
    service = service.replace(old_ip, new_ip, 1)

old_start = """      localIp = await _bestLocalIp();
      await _startServer();
      await _startDiscovery();
"""
new_start = """      localIp = await _bestLocalIp();
      if (Platform.isAndroid) {
        try {
          await _native.invokeMethod<void>('acquireMulticastLock');
        } catch (_) {}
      }
      await _startServer();
      await _startDiscovery();
"""
if old_start in service:
    service = service.replace(old_start, new_start, 1)

old_broadcast = """  void _broadcastPresence() {
    _sendDiscovery('DISCOVER', InternetAddress('255.255.255.255'));
  }
"""
new_broadcast = """  void _broadcastPresence() {
    final targets = <String>{'255.255.255.255'};
    final parts = localIp.split('.');
    if (parts.length == 4 && _isPrivateIp(localIp)) {
      targets.add('${parts[0]}.${parts[1]}.${parts[2]}.255');
    }
    for (final peer in _paired.values) {
      if (_isValidLanIp(peer.ip)) targets.add(peer.ip);
    }
    for (final target in targets) {
      try {
        _sendDiscovery('DISCOVER', InternetAddress(target));
      } catch (_) {}
    }
  }
"""
if old_broadcast in service:
    service = service.replace(old_broadcast, new_broadcast, 1)

main_path.write_text(main, encoding='utf-8')
service_path.write_text(service, encoding='utf-8')
print('Applied LocalShare 1.4.1 startup/discovery hotfix')
