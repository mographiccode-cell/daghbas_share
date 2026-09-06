import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';
import 'security.dart';

class LocalShareService extends ChangeNotifier {
  static const int serverPort = 40404;
  static const int discoveryPort = 40405;
  static const int protocolVersion = 2;
  static const int pairCodeLength = 6;
  static const int _chunkSize = 256 * 1024;
  static const int _maxFileBytes = 50 * 1024 * 1024 * 1024;
  static const int _maxConcurrentIncoming = 2;
  static const int _maxSmallBodyBytes = 8192;
  static const Duration _pairCodeLifetime = Duration(minutes: 5);
  static const Duration _requestClockSkew = Duration(minutes: 2);
  static const Duration _idleTimeout = Duration(seconds: 30);
  static const MethodChannel _native = MethodChannel('local_share/native');
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();
  static const String _securePeersKey = 'localshare_peers_v2';

  final LocalShareCrypto _crypto = LocalShareCrypto();
  HttpServer? _server;
  RawDatagramSocket? _discoverySocket;
  Timer? _broadcastTimer;
  Timer? _staleTimer;
  Timer? _pairCodeTimer;
  SharedPreferences? _prefs;

  final Map<String, DiscoveredDevice> _discovered = {};
  final Map<String, Peer> _paired = {};
  final List<TransferItem> _transfers = [];
  final Map<String, List<DateTime>> _pairFailures = {};
  final Map<String, DateTime> _recentTransferNonces = {};

  late Directory receiveDirectory;
  String deviceId = '';
  String deviceName = '';
  String pairCode = '';
  String localIp = '—';
  bool initialized = false;
  bool discoveryAvailable = true;
  String? startupError;

  List<int> _pairSalt = const [];
  int _pairEpoch = 0;
  int _activePairDerivations = 0;
  int _activeIncoming = 0;

  List<DiscoveredDevice> get discoveredDevices {
    final items = _discovered.values.toList()
      ..sort((a, b) {
        final ap = _paired.containsKey(a.deviceId) ? 0 : 1;
        final bp = _paired.containsKey(b.deviceId) ? 0 : 1;
        if (ap != bp) return ap.compareTo(bp);
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    return items;
  }

  List<Peer> get pairedPeers => _paired.values.toList();
  List<TransferItem> get transfers => List.unmodifiable(_transfers.reversed);

  Future<void> init() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      deviceId = _prefs!.getString('device_id') ?? _randomToken(24);
      await _prefs!.setString('device_id', deviceId);
      final savedName = _prefs!.getString('device_name');
      deviceName = savedName ?? _defaultDeviceName();
      await _prefs!.setString('device_name', deviceName);

      await _prefs!.remove('paired_peers');
      await _loadPeers();
      _rotatePairCode();
      receiveDirectory = await _resolveReceiveDirectory();
      await receiveDirectory.create(recursive: true);
      localIp = await _bestLocalIp();
      await _startServer();
      await _startDiscovery();
      _pairCodeTimer = Timer.periodic(
        _pairCodeLifetime,
        (_) => _rotatePairCode(),
      );
      initialized = true;
      notifyListeners();
    } catch (e) {
      startupError = e.toString();
      initialized = true;
      notifyListeners();
    }
  }

  String _defaultDeviceName() {
    if (Platform.isAndroid) return 'هاتف Android';
    if (Platform.isWindows) {
      final host = Platform.localHostname.trim();
      return host.isEmpty ? 'Windows PC' : host;
    }
    return Platform.localHostname.isEmpty
        ? 'LocalShare'
        : Platform.localHostname;
  }

  Future<void> setDeviceName(String value) async {
    final clean = value.trim();
    if (clean.isEmpty || clean == deviceName) return;
    deviceName = clean.length > 32 ? clean.substring(0, 32) : clean;
    await _prefs?.setString('device_name', deviceName);
    _broadcastPresence();
    notifyListeners();
  }

  Peer? peerFor(String id) => _paired[id];

  bool isOnline(String id) {
    final item = _discovered[id];
    if (item == null) return false;
    return DateTime.now().difference(item.lastSeen) <
        const Duration(seconds: 12);
  }

  Future<Directory> _resolveReceiveDirectory() async {
    if (Platform.isWindows) {
      final downloads = await getDownloadsDirectory();
      if (downloads != null) {
        return Directory(
          '${downloads.path}${Platform.pathSeparator}LocalShare',
        );
      }
    }
    if (Platform.isAndroid) {
      final external = await getExternalStorageDirectory();
      if (external != null) {
        return Directory('${external.path}${Platform.pathSeparator}LocalShare');
      }
    }
    final docs = await getApplicationDocumentsDirectory();
    return Directory('${docs.path}${Platform.pathSeparator}LocalShare');
  }

  Future<String> _bestLocalIp() async {
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

  bool _isPrivateIp(String ip) {
    if (ip.startsWith('192.168.') || ip.startsWith('10.')) return true;
    final parts = ip.split('.');
    if (parts.length != 4 || parts[0] != '172') return false;
    final second = int.tryParse(parts[1]) ?? -1;
    return second >= 16 && second <= 31;
  }

  bool _isValidLanIp(String ip) {
    final parsed = InternetAddress.tryParse(ip);
    return parsed != null &&
        parsed.type == InternetAddressType.IPv4 &&
        _isPrivateIp(ip);
  }

  Future<void> _startServer() async {
    _server = await HttpServer.bind(
      InternetAddress.anyIPv4,
      serverPort,
      shared: true,
    );
    _server!.listen(
      _handleRequest,
      onError: (Object e) {
        startupError = 'Server: $e';
        notifyListeners();
      },
    );
  }

  Future<void> _startDiscovery() async {
    try {
      _discoverySocket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        discoveryPort,
        reuseAddress: true,
      );
      _discoverySocket!.broadcastEnabled = true;
      _discoverySocket!.listen(
        _onDiscoveryEvent,
        onError: (_) {
          discoveryAvailable = false;
          notifyListeners();
        },
      );
      _broadcastTimer = Timer.periodic(
        const Duration(seconds: 3),
        (_) => _broadcastPresence(),
      );
      _staleTimer = Timer.periodic(
        const Duration(seconds: 5),
        (_) => _removeStaleDevices(),
      );
      _broadcastPresence();
    } catch (_) {
      discoveryAvailable = false;
      notifyListeners();
    }
  }

  void _onDiscoveryEvent(RawSocketEvent event) {
    if (event != RawSocketEvent.read || _discoverySocket == null) return;
    Datagram? datagram;
    while ((datagram = _discoverySocket!.receive()) != null) {
      final data = datagram!;
      if (!_isPrivateIp(data.address.address)) continue;
      final text = utf8.decode(data.data, allowMalformed: true);
      final parts = text.split('|');
      if (parts.length != 5 || parts[0] != 'LOCALSHARE2') continue;
      final type = parts[1];
      final id = parts[2];
      if (!_isValidDeviceId(id) || id == deviceId) continue;
      final port = int.tryParse(parts[4]) ?? 0;
      if (port < 1 || port > 65535) continue;
      String name;
      try {
        name = Uri.decodeComponent(parts[3]);
      } catch (_) {
        continue;
      }
      if (name.isEmpty || name.length > 64) continue;
      _rememberDiscovered(id, name, data.address.address, port);
      if (type == 'DISCOVER') _sendDiscovery('HERE', data.address);
    }
  }

  void _rememberDiscovered(String id, String name, String ip, int port) {
    if (!_isValidDeviceId(id) || !_isValidLanIp(ip)) return;
    _discovered[id] = DiscoveredDevice(
      deviceId: id,
      name: name.length > 64 ? name.substring(0, 64) : name,
      ip: ip,
      port: port,
      lastSeen: DateTime.now(),
    );
    notifyListeners();
  }

  void _broadcastPresence() {
    _sendDiscovery('DISCOVER', InternetAddress('255.255.255.255'));
  }

  void _sendDiscovery(String type, InternetAddress address) {
    final socket = _discoverySocket;
    if (socket == null) return;
    final message =
        'LOCALSHARE2|$type|$deviceId|${Uri.encodeComponent(deviceName)}|$serverPort';
    try {
      socket.send(utf8.encode(message), address, discoveryPort);
    } catch (_) {}
  }

  void _removeStaleDevices() {
    final now = DateTime.now();
    final before = _discovered.length;
    _discovered.removeWhere(
      (_, value) =>
          now.difference(value.lastSeen) > const Duration(seconds: 18),
    );
    _recentTransferNonces.removeWhere(
      (_, value) => now.difference(value) > const Duration(minutes: 10),
    );
    _pairFailures.removeWhere((_, failures) {
      failures.removeWhere(
        (time) => now.difference(time) > const Duration(minutes: 2),
      );
      return failures.isEmpty;
    });
    if (_discovered.length != before) notifyListeners();
  }

  void _rotatePairCode() {
    pairCode = (100000 + Random.secure().nextInt(900000)).toString();
    _pairSalt = _crypto.randomBytes(16);
    _pairEpoch = DateTime.now().millisecondsSinceEpoch;
    if (initialized) notifyListeners();
  }

  Future<void> _handleRequest(HttpRequest request) async {
    final remoteIp = request.connectionInfo?.remoteAddress.address ?? '';
    if (!_isValidLanIp(remoteIp)) {
      request.response.statusCode = HttpStatus.forbidden;
      await request.response.close();
      return;
    }

    request.response.headers.set('X-Content-Type-Options', 'nosniff');
    request.response.headers.set('Cache-Control', 'no-store');
    request.response.headers.set('X-LocalShare', '$protocolVersion');
    try {
      if (request.method == 'GET' && request.uri.path == '/hello') {
        _jsonResponse(request, HttpStatus.ok, {
          'protocol': protocolVersion,
          'deviceId': deviceId,
          'name': deviceName,
          'port': serverPort,
          'pairSalt': _crypto.b64(_pairSalt),
          'pairEpoch': _pairEpoch,
        });
        return;
      }
      if (request.method == 'POST' && request.uri.path == '/pair') {
        await _handlePair(request, remoteIp);
        return;
      }
      if (request.method == 'POST' && request.uri.path == '/verify') {
        await _handleVerify(request);
        return;
      }
      if (request.method == 'POST' && request.uri.path == '/upload2') {
        await _handleEncryptedUpload(request);
        return;
      }
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
    } on _RequestException catch (e) {
      _jsonResponse(request, e.statusCode, {'error': e.code});
    } catch (_) {
      try {
        _jsonResponse(request, HttpStatus.internalServerError, {
          'error': 'transfer_error',
        });
      } catch (_) {}
    }
  }

  Future<void> _handlePair(HttpRequest request, String remoteIp) async {
    if (!_pairAttemptAllowed(remoteIp)) {
      throw const _RequestException(
        HttpStatus.tooManyRequests,
        'too_many_attempts',
      );
    }
    if (_activePairDerivations >= 2) {
      throw const _RequestException(
        HttpStatus.serviceUnavailable,
        'pairing_busy',
      );
    }

    final data = await _readJsonBody(request);
    final sourceId = '${data['deviceId'] ?? ''}'.trim();
    final sourceName = '${data['name'] ?? ''}'.trim();
    final sourcePort = (data['port'] as num?)?.toInt() ?? 0;
    final clientNonce = '${data['clientNonce'] ?? ''}'.trim();
    final pairEpoch = (data['pairEpoch'] as num?)?.toInt() ?? 0;
    final proof = '${data['proof'] ?? ''}'.trim();

    if (!_isValidDeviceId(sourceId) ||
        sourceId == deviceId ||
        sourceName.isEmpty ||
        sourceName.length > 64 ||
        sourcePort < 1 ||
        sourcePort > 65535 ||
        !_crypto.isValidB64Length(clientNonce, 16) ||
        proof.isEmpty ||
        pairEpoch != _pairEpoch) {
      _recordPairFailure(remoteIp);
      throw const _RequestException(
        HttpStatus.forbidden,
        'invalid_or_expired_pairing',
      );
    }

    _activePairDerivations++;
    try {
      final pairKey = await _crypto.derivePairKey(
        pairCode,
        _pairSalt,
        sourceId,
        deviceId,
      );
      final proofMessage =
          'pair|$protocolVersion|$sourceId|$deviceId|$clientNonce|$sourceName|$sourcePort|$pairEpoch';
      final expectedProof = await _crypto.macString(pairKey, proofMessage);
      if (!_crypto.constantTimeEquals(expectedProof, proof)) {
        _recordPairFailure(remoteIp);
        throw const _RequestException(HttpStatus.forbidden, 'wrong_code');
      }

      final serverNonce = _crypto.b64(_crypto.randomBytes(16));
      final sharedKey = await _crypto.deriveSessionKey(
        pairKey,
        sourceId,
        deviceId,
        clientNonce,
        serverNonce,
      );
      final responseProof = await _crypto.macString(
        pairKey,
        'accept|$protocolVersion|$deviceId|$sourceId|$clientNonce|$serverNonce|$pairEpoch',
      );

      _paired[sourceId] = Peer(
        deviceId: sourceId,
        name: sourceName,
        ip: remoteIp,
        port: sourcePort,
        sharedKey: _crypto.b64(sharedKey),
      );
      await _savePeers();
      _pairFailures.remove(remoteIp);
      _rememberDiscovered(sourceId, sourceName, remoteIp, sourcePort);

      _jsonResponse(request, HttpStatus.ok, {
        'protocol': protocolVersion,
        'deviceId': deviceId,
        'name': deviceName,
        'port': serverPort,
        'serverNonce': serverNonce,
        'pairEpoch': pairEpoch,
        'proof': responseProof,
      });
      _rotatePairCode();
    } finally {
      _activePairDerivations--;
    }
  }

  Future<void> _handleVerify(HttpRequest request) async {
    final data = await _readJsonBody(request);
    final sourceId = '${data['deviceId'] ?? ''}'.trim();
    final timestamp = (data['timestamp'] as num?)?.toInt() ?? 0;
    final nonce = '${data['nonce'] ?? ''}'.trim();
    final proof = '${data['proof'] ?? ''}'.trim();
    final peer = _paired[sourceId];
    if (peer == null ||
        !_timestampIsFresh(timestamp) ||
        !_crypto.isValidB64Length(nonce, 16)) {
      throw const _RequestException(
        HttpStatus.unauthorized,
        'verification_failed',
      );
    }
    final key = _peerKey(peer);
    final expected = await _crypto.macString(
      key,
      'verify|$protocolVersion|$sourceId|$deviceId|$timestamp|$nonce',
    );
    if (!_crypto.constantTimeEquals(expected, proof)) {
      throw const _RequestException(
        HttpStatus.unauthorized,
        'verification_failed',
      );
    }
    final responseProof = await _crypto.macString(
      key,
      'verified|$protocolVersion|$deviceId|$sourceId|$timestamp|$nonce',
    );
    _jsonResponse(request, HttpStatus.ok, {
      'deviceId': deviceId,
      'name': deviceName,
      'port': serverPort,
      'proof': responseProof,
    });
  }

  Future<void> _handleEncryptedUpload(HttpRequest request) async {
    if (_activeIncoming >= _maxConcurrentIncoming) {
      throw const _RequestException(
        HttpStatus.tooManyRequests,
        'receiver_busy',
      );
    }

    final sourceId = request.headers.value('x-localshare-device') ?? '';
    final timestamp =
        int.tryParse(request.headers.value('x-localshare-time') ?? '') ?? 0;
    final transferNonce = request.headers.value('x-localshare-transfer') ?? '';
    final metaHeader = request.headers.value('x-localshare-meta') ?? '';
    final peer = _paired[sourceId];
    if (peer == null ||
        !_timestampIsFresh(timestamp) ||
        !_crypto.isValidB64Length(transferNonce, 8) ||
        metaHeader.isEmpty ||
        metaHeader.length > 4096) {
      throw const _RequestException(HttpStatus.unauthorized, 'unauthorized');
    }

    final replayKey = '$sourceId:$transferNonce';
    if (_recentTransferNonces.containsKey(replayKey)) {
      throw const _RequestException(HttpStatus.conflict, 'replay_rejected');
    }

    final sharedKey = _peerKey(peer);
    Map<String, dynamic> meta;
    try {
      meta = await _crypto.decryptMetadata(
        sharedKey: sharedKey,
        senderId: sourceId,
        receiverId: deviceId,
        timestamp: timestamp,
        transferNonce: transferNonce,
        encodedBox: metaHeader,
      );
    } catch (_) {
      throw const _RequestException(
        HttpStatus.unauthorized,
        'invalid_metadata',
      );
    }

    final fileName = safeFileName('${meta['name'] ?? ''}');
    final total = (meta['size'] as num?)?.toInt() ?? -1;
    if (total < 0 || total > _maxFileBytes) {
      throw const _RequestException(HttpStatus.badRequest, 'invalid_file_size');
    }
    final expectedBodyLength = _crypto.encryptedBodyLength(total);
    if (request.contentLength >= 0 &&
        request.contentLength != expectedBodyLength) {
      throw const _RequestException(
        HttpStatus.badRequest,
        'invalid_body_length',
      );
    }

    _recentTransferNonces[replayKey] = DateTime.now();
    final destination = await _uniqueFile(fileName);
    _activeIncoming++;
    final transfer = TransferItem(
      id: _randomToken(12),
      fileName: destination.uri.pathSegments.last,
      peerName: peer.name,
      direction: TransferDirection.receive,
      totalBytes: total,
      startedAt: DateTime.now(),
      status: TransferStatus.running,
      localPath: destination.path,
    );
    _transfers.add(transfer);
    notifyListeners();

    IOSink? sink;
    try {
      final transferBase = _crypto.b64d(transferNonce);
      final transferKey = await _crypto.deriveTransferKey(
        sharedKey,
        timestamp,
        transferBase,
        sourceId,
        deviceId,
      );
      final reader = _ByteStreamReader(request, timeout: _idleTimeout);
      sink = destination.openWrite();
      var remaining = total;
      var chunkIndex = 0;
      var received = 0;
      var lastNotify = DateTime.fromMillisecondsSinceEpoch(0);

      while (remaining > 0) {
        final plainLength = min(_chunkSize, remaining);
        final cipherText = await reader.readExact(plainLength);
        final macBytes = await reader.readExact(
          _crypto.cipher.macAlgorithm.macLength,
        );
        final nonce = _crypto.chunkNonce(transferBase, chunkIndex);
        final aad = _crypto.chunkAad(
          sourceId,
          deviceId,
          timestamp,
          transferNonce,
          chunkIndex,
          total,
        );
        final clear = await _crypto.cipher.decrypt(
          SecretBox(cipherText, nonce: nonce, mac: Mac(macBytes)),
          secretKey: SecretKey(transferKey),
          aad: aad,
        );
        sink.add(clear);
        received += clear.length;
        remaining -= clear.length;
        chunkIndex++;
        transfer.progress = total == 0
            ? 1.0
            : (received / total).clamp(0.0, 1.0).toDouble();
        final now = DateTime.now();
        if (now.difference(lastNotify) > const Duration(milliseconds: 120)) {
          lastNotify = now;
          notifyListeners();
        }
      }

      if (await reader.hasMore()) {
        throw const FormatException('Unexpected trailing encrypted data');
      }
      await sink.flush();
      await sink.close();
      sink = null;
      transfer.progress = 1;
      transfer.status = TransferStatus.completed;
      notifyListeners();
      final ack = await _crypto.macString(
        sharedKey,
        'ack|$protocolVersion|$deviceId|$sourceId|$timestamp|$transferNonce|$received',
      );
      _jsonResponse(request, HttpStatus.ok, {
        'ok': true,
        'bytes': received,
        'proof': ack,
      });
    } catch (e) {
      try {
        await sink?.close();
      } catch (_) {}
      try {
        if (await destination.exists()) await destination.delete();
      } catch (_) {}
      transfer.status = TransferStatus.failed;
      transfer.error = 'فشل التحقق من النقل المشفّر';
      notifyListeners();
      if (e is _RequestException) rethrow;
      throw const _RequestException(
        HttpStatus.badRequest,
        'encrypted_transfer_failed',
      );
    } finally {
      _activeIncoming--;
    }
  }

  Future<Map<String, dynamic>> _readJsonBody(HttpRequest request) async {
    final builder = BytesBuilder(copy: false);
    var total = 0;
    await for (final chunk in request.timeout(_idleTimeout)) {
      total += chunk.length;
      if (total > _maxSmallBodyBytes) {
        throw const _RequestException(413, 'request_too_large');
      }
      builder.add(chunk);
    }
    try {
      final decoded = jsonDecode(utf8.decode(builder.takeBytes()));
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Expected JSON object');
      }
      return decoded;
    } catch (_) {
      throw const _RequestException(HttpStatus.badRequest, 'invalid_json');
    }
  }

  void _jsonResponse(
    HttpRequest request,
    int status,
    Map<String, dynamic> body,
  ) {
    request.response.statusCode = status;
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode(body));
    unawaited(request.response.close());
  }

  Future<File> _uniqueFile(String fileName) async {
    final separator = Platform.pathSeparator;
    var target = File('${receiveDirectory.path}$separator$fileName');
    if (!await target.exists()) return target;
    final dot = fileName.lastIndexOf('.');
    final stem = dot > 0 ? fileName.substring(0, dot) : fileName;
    final ext = dot > 0 ? fileName.substring(dot) : '';
    var index = 1;
    while (index <= 100000) {
      target = File('${receiveDirectory.path}$separator$stem ($index)$ext');
      if (!await target.exists()) return target;
      index++;
    }
    throw const FileSystemException('Unable to allocate a unique file name');
  }

  Future<void> probeIp(String rawIp) async {
    var ip = rawIp.trim();
    ip = ip.replaceFirst(RegExp(r'^https?://'), '');
    ip = ip.split('/').first;
    if (ip.contains(':')) ip = ip.split(':').first;
    if (!_isValidLanIp(ip)) {
      throw const FormatException('أدخل عنوان IP محلي صحيح');
    }
    final hello = await _fetchHello(ip, serverPort);
    final id = '${hello['deviceId'] ?? ''}';
    if (!_isValidDeviceId(id) || id == deviceId) return;
    _rememberDiscovered(
      id,
      '${hello['name'] ?? 'Device'}',
      ip,
      (hello['port'] as num?)?.toInt() ?? serverPort,
    );
  }

  Future<Map<String, dynamic>> _fetchHello(String ip, int port) async {
    if (!_isValidLanIp(ip) || port < 1 || port > 65535) {
      throw const PairingException('عنوان الجهاز غير صالح');
    }
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
    try {
      final request = await client.getUrl(
        Uri(scheme: 'http', host: ip, port: port, path: '/hello'),
      );
      final response = await request.close().timeout(
        const Duration(seconds: 5),
      );
      final text = await utf8.decoder.bind(response).join();
      if (response.statusCode != HttpStatus.ok) {
        throw const PairingException(
          'الجهاز لا يستجيب كبروتوكول LocalShare الآمن',
        );
      }
      final decoded = jsonDecode(text);
      if (decoded is! Map<String, dynamic>) {
        throw const PairingException('استجابة الجهاز غير صالحة');
      }
      if ((decoded['protocol'] as num?)?.toInt() != protocolVersion ||
          !_isValidDeviceId('${decoded['deviceId'] ?? ''}') ||
          !_crypto.isValidB64Length('${decoded['pairSalt'] ?? ''}', 16)) {
        throw const PairingException(
          'إصدار LocalShare على الجهاز الآخر غير متوافق',
        );
      }
      return decoded;
    } finally {
      client.close(force: true);
    }
  }

  Future<Peer> pairDevice(DiscoveredDevice device, String code) async {
    if (!RegExp(r'^\d{6}$').hasMatch(code.trim())) {
      throw const PairingException('رمز الربط يجب أن يكون 6 أرقام');
    }
    final hello = await _fetchHello(device.ip, device.port);
    final remoteId = '${hello['deviceId']}';
    if (remoteId != device.deviceId) {
      throw const PairingException('هوية الجهاز تغيّرت. أعد البحث عن الأجهزة.');
    }
    final pairSalt = _crypto.b64d('${hello['pairSalt']}');
    final pairEpoch = (hello['pairEpoch'] as num?)?.toInt() ?? 0;
    final remoteName = '${hello['name'] ?? device.name}';
    final remotePort = (hello['port'] as num?)?.toInt() ?? device.port;
    if (remotePort < 1 || remotePort > 65535) {
      throw const PairingException('منفذ الجهاز الآخر غير صالح');
    }
    final pairKey = await _crypto.derivePairKey(
      code.trim(),
      pairSalt,
      deviceId,
      remoteId,
    );
    final clientNonce = _crypto.b64(_crypto.randomBytes(16));
    final proof = await _crypto.macString(
      pairKey,
      'pair|$protocolVersion|$deviceId|$remoteId|$clientNonce|$deviceName|$serverPort|$pairEpoch',
    );

    final client = HttpClient()..connectionTimeout = const Duration(seconds: 4);
    try {
      final request = await client.postUrl(
        Uri(scheme: 'http', host: device.ip, port: remotePort, path: '/pair'),
      );
      request.headers.contentType = ContentType.json;
      request.write(
        jsonEncode({
          'deviceId': deviceId,
          'name': deviceName,
          'port': serverPort,
          'clientNonce': clientNonce,
          'pairEpoch': pairEpoch,
          'proof': proof,
        }),
      );
      final response = await request.close().timeout(
        const Duration(seconds: 20),
      );
      final text = await utf8.decoder.bind(response).join();
      if (response.statusCode == HttpStatus.tooManyRequests) {
        throw const PairingException(
          'تم إيقاف محاولات الربط مؤقتًا بسبب محاولات كثيرة.',
        );
      }
      if (response.statusCode != HttpStatus.ok) {
        throw const PairingException('فشل الربط. تحقق من الرمز وحاول من جديد.');
      }
      final decoded = jsonDecode(text);
      if (decoded is! Map<String, dynamic>) {
        throw const PairingException('استجابة الربط غير صالحة');
      }
      final responseId = '${decoded['deviceId'] ?? ''}';
      final serverNonce = '${decoded['serverNonce'] ?? ''}';
      final responseProof = '${decoded['proof'] ?? ''}';
      if (responseId != remoteId ||
          !_crypto.isValidB64Length(serverNonce, 16)) {
        throw const PairingException('استجابة الربط غير صالحة');
      }
      final expected = await _crypto.macString(
        pairKey,
        'accept|$protocolVersion|$remoteId|$deviceId|$clientNonce|$serverNonce|$pairEpoch',
      );
      if (!_crypto.constantTimeEquals(expected, responseProof)) {
        throw const PairingException('تعذر التحقق من هوية الجهاز الآخر');
      }
      final sharedKey = await _crypto.deriveSessionKey(
        pairKey,
        deviceId,
        remoteId,
        clientNonce,
        serverNonce,
      );
      final peer = Peer(
        deviceId: remoteId,
        name: remoteName,
        ip: device.ip,
        port: remotePort,
        sharedKey: _crypto.b64(sharedKey),
      );
      _paired[peer.deviceId] = peer;
      await _savePeers();
      notifyListeners();
      return peer;
    } on TimeoutException {
      throw const PairingException(
        'انتهت مهلة الاتصال. تأكد أن الجهازين على نفس الشبكة.',
      );
    } finally {
      client.close(force: true);
    }
  }

  Future<void> forgetPeer(String id) async {
    _paired.remove(id);
    await _savePeers();
    notifyListeners();
  }

  Future<void> pickAndSend(Peer peer) async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: false,
      withReadStream: false,
    );
    if (result == null) return;
    for (final picked in result.files) {
      final path = picked.path;
      if (path == null || path.isEmpty) continue;
      await sendFile(peer, File(path));
    }
  }

  Future<void> sendFile(Peer peer, File file) async {
    if (!await file.exists()) {
      throw const FileSystemException('الملف غير موجود');
    }
    final total = await file.length();
    if (total < 0 || total > _maxFileBytes) {
      throw const FileSystemException(
        'حجم الملف يتجاوز حد الأمان البالغ 50 GB',
      );
    }
    final fileName = safeFileName(file.uri.pathSegments.last);
    final transfer = TransferItem(
      id: _randomToken(12),
      fileName: fileName,
      peerName: peer.name,
      direction: TransferDirection.send,
      totalBytes: total,
      startedAt: DateTime.now(),
      status: TransferStatus.running,
    );
    _transfers.add(transfer);
    notifyListeners();

    try {
      final current = await _resolveVerifiedPeer(peer);
      final sharedKey = _peerKey(current);
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final transferBase = _crypto.randomBytes(8);
      final transferNonce = _crypto.b64(transferBase);
      final metaHeader = await _crypto.encryptMetadata(
        sharedKey: sharedKey,
        senderId: deviceId,
        receiverId: current.deviceId,
        timestamp: timestamp,
        transferNonce: transferNonce,
        fileName: fileName,
        size: total,
      );
      final transferKey = await _crypto.deriveTransferKey(
        sharedKey,
        timestamp,
        transferBase,
        deviceId,
        current.deviceId,
      );
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 5);
      try {
        final request = await client.postUrl(
          Uri(
            scheme: 'http',
            host: current.ip,
            port: current.port,
            path: '/upload2',
          ),
        );
        request.headers.set('x-localshare-device', deviceId);
        request.headers.set('x-localshare-time', '$timestamp');
        request.headers.set('x-localshare-transfer', transferNonce);
        request.headers.set('x-localshare-meta', metaHeader);
        request.headers.contentType = ContentType.binary;
        request.contentLength = _crypto.encryptedBodyLength(total);

        var sent = 0;
        var chunkIndex = 0;
        var lastNotify = DateTime.fromMillisecondsSinceEpoch(0);
        final source = await file.open();
        try {
          while (sent < total) {
            final plain = await source.read(min(_chunkSize, total - sent));
            if (plain.isEmpty) {
              throw const FileSystemException('Unexpected end of source file');
            }
            final nonce = _crypto.chunkNonce(transferBase, chunkIndex);
            final aad = _crypto.chunkAad(
              deviceId,
              current.deviceId,
              timestamp,
              transferNonce,
              chunkIndex,
              total,
            );
            final box = await _crypto.cipher.encrypt(
              plain,
              secretKey: SecretKey(transferKey),
              nonce: nonce,
              aad: aad,
            );
            request.add(box.cipherText);
            request.add(box.mac.bytes);
            sent += plain.length;
            chunkIndex++;
            if (chunkIndex % 4 == 0) await request.flush();
            transfer.progress = total == 0
                ? 1.0
                : (sent / total).clamp(0.0, 1.0).toDouble();
            final now = DateTime.now();
            if (now.difference(lastNotify) >
                const Duration(milliseconds: 120)) {
              lastNotify = now;
              notifyListeners();
            }
          }
        } finally {
          await source.close();
        }

        final response = await request.close().timeout(_idleTimeout);
        final text = await utf8.decoder.bind(response).join();
        if (response.statusCode != HttpStatus.ok) {
          throw HttpException('Transfer failed: ${response.statusCode}');
        }
        final decoded = jsonDecode(text);
        if (decoded is! Map<String, dynamic>) {
          throw const PairingException('استجابة استلام الملف غير صالحة');
        }
        final bytes = (decoded['bytes'] as num?)?.toInt() ?? -1;
        final ack = '${decoded['proof'] ?? ''}';
        final expectedAck = await _crypto.macString(
          sharedKey,
          'ack|$protocolVersion|${current.deviceId}|$deviceId|$timestamp|$transferNonce|$bytes',
        );
        if (bytes != total || !_crypto.constantTimeEquals(expectedAck, ack)) {
          throw const PairingException(
            'تعذر التحقق من استلام الملف على الجهاز الآخر',
          );
        }
      } finally {
        client.close(force: true);
      }
      transfer.progress = 1;
      transfer.status = TransferStatus.completed;
      notifyListeners();
    } catch (e) {
      transfer.status = TransferStatus.failed;
      transfer.error = e.toString();
      notifyListeners();
      rethrow;
    }
  }

  Future<Peer> _resolveVerifiedPeer(Peer peer) async {
    final stored = _paired[peer.deviceId] ?? peer;
    final candidate = _discovered[peer.deviceId];
    final endpoints = <({String ip, int port, String name})>[];
    if (candidate != null) {
      endpoints.add((
        ip: candidate.ip,
        port: candidate.port,
        name: candidate.name,
      ));
    }
    if (!endpoints.any((e) => e.ip == stored.ip && e.port == stored.port)) {
      endpoints.add((ip: stored.ip, port: stored.port, name: stored.name));
    }
    for (final endpoint in endpoints) {
      if (await _verifyPeerEndpoint(stored, endpoint.ip, endpoint.port)) {
        final updated = stored.copyWith(
          ip: endpoint.ip,
          port: endpoint.port,
          name: endpoint.name,
        );
        _paired[updated.deviceId] = updated;
        await _savePeers();
        return updated;
      }
    }
    throw const PairingException(
      'تعذر التحقق من الجهاز المرتبط. تأكد أنه مفتوح وعلى نفس الشبكة.',
    );
  }

  Future<bool> _verifyPeerEndpoint(Peer peer, String ip, int port) async {
    if (!_isValidLanIp(ip) || port < 1 || port > 65535) return false;
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final nonce = _crypto.b64(_crypto.randomBytes(16));
    final key = _peerKey(peer);
    final proof = await _crypto.macString(
      key,
      'verify|$protocolVersion|$deviceId|${peer.deviceId}|$timestamp|$nonce',
    );
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
    try {
      final request = await client.postUrl(
        Uri(scheme: 'http', host: ip, port: port, path: '/verify'),
      );
      request.headers.contentType = ContentType.json;
      request.write(
        jsonEncode({
          'deviceId': deviceId,
          'timestamp': timestamp,
          'nonce': nonce,
          'proof': proof,
        }),
      );
      final response = await request.close().timeout(
        const Duration(seconds: 5),
      );
      final text = await utf8.decoder.bind(response).join();
      if (response.statusCode != HttpStatus.ok) return false;
      final decoded = jsonDecode(text);
      if (decoded is! Map<String, dynamic> ||
          '${decoded['deviceId'] ?? ''}' != peer.deviceId) {
        return false;
      }
      final responseProof = '${decoded['proof'] ?? ''}';
      final expected = await _crypto.macString(
        key,
        'verified|$protocolVersion|${peer.deviceId}|$deviceId|$timestamp|$nonce',
      );
      return _crypto.constantTimeEquals(expected, responseProof);
    } catch (_) {
      return false;
    } finally {
      client.close(force: true);
    }
  }

  bool _pairAttemptAllowed(String ip) {
    final now = DateTime.now();
    final failures = _pairFailures.putIfAbsent(ip, () => <DateTime>[]);
    failures.removeWhere(
      (time) => now.difference(time) > const Duration(minutes: 2),
    );
    return failures.length < 5;
  }

  void _recordPairFailure(String ip) {
    final failures = _pairFailures.putIfAbsent(ip, () => <DateTime>[]);
    failures.add(DateTime.now());
    if (failures.length > 20) {
      failures.removeRange(0, failures.length - 20);
    }
  }

  bool _timestampIsFresh(int timestamp) {
    if (timestamp <= 0) return false;
    final now = DateTime.now().millisecondsSinceEpoch;
    return (now - timestamp).abs() <= _requestClockSkew.inMilliseconds;
  }

  bool _isValidDeviceId(String id) {
    return id.length >= 16 &&
        id.length <= 64 &&
        RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(id);
  }

  List<int> _peerKey(Peer peer) {
    if (!_crypto.isValidB64Length(peer.sharedKey, 32)) {
      throw const PairingException(
        'بيانات ثقة الجهاز المرتبط غير صالحة. أعد الربط.',
      );
    }
    return _crypto.b64d(peer.sharedKey);
  }

  Future<List<FileSystemEntity>> receivedFiles() async {
    if (!await receiveDirectory.exists()) return [];
    final items = await receiveDirectory
        .list(followLinks: false)
        .where((e) => e is File)
        .toList();
    items.sort(
      (a, b) => b.statSync().modified.compareTo(a.statSync().modified),
    );
    return items;
  }

  Future<String> exportReceivedFile(File file) async {
    if (Platform.isWindows) {
      final target = await FilePicker.platform.saveFile(
        dialogTitle: 'حفظ نسخة من الملف',
        fileName: file.uri.pathSegments.last,
      );
      if (target == null) return '';
      await file.copy(target);
      return target;
    }
    if (Platform.isAndroid) {
      final result = await _native.invokeMethod<String>('exportToDownloads', {
        'path': file.path,
        'name': file.uri.pathSegments.last,
      });
      return result ?? '';
    }
    return '';
  }

  Future<void> _loadPeers() async {
    final raw = await _secureStorage.read(key: _securePeersKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List<dynamic>)
        throw const FormatException('Invalid peers');
      for (final item in decoded) {
        final peer = Peer.fromJson(Map<String, dynamic>.from(item as Map));
        if (_isValidDeviceId(peer.deviceId) &&
            _isValidLanIp(peer.ip) &&
            peer.port > 0 &&
            peer.port <= 65535 &&
            _crypto.isValidB64Length(peer.sharedKey, 32)) {
          _paired[peer.deviceId] = peer;
        }
      }
    } catch (_) {
      await _secureStorage.delete(key: _securePeersKey);
    }
  }

  Future<void> _savePeers() async {
    final raw = jsonEncode(_paired.values.map((e) => e.toJson()).toList());
    await _secureStorage.write(key: _securePeersKey, value: raw);
  }

  String _randomToken(int length) {
    const alphabet =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_';
    final random = Random.secure();
    return List.generate(
      length,
      (_) => alphabet[random.nextInt(alphabet.length)],
    ).join();
  }

  @override
  void dispose() {
    _broadcastTimer?.cancel();
    _staleTimer?.cancel();
    _pairCodeTimer?.cancel();
    _discoverySocket?.close();
    unawaited(_server?.close(force: true));
    super.dispose();
  }
}

class PairingException implements Exception {
  const PairingException(this.message);
  final String message;
  @override
  String toString() => message;
}

class _RequestException implements Exception {
  const _RequestException(this.statusCode, this.code);
  final int statusCode;
  final String code;
}

class _ByteStreamReader {
  _ByteStreamReader(Stream<List<int>> stream, {required this.timeout})
    : _iterator = StreamIterator<List<int>>(stream);

  final StreamIterator<List<int>> _iterator;
  final Duration timeout;
  List<int> _chunk = const [];
  int _offset = 0;
  bool _done = false;

  Future<List<int>> readExact(int length) async {
    if (length < 0) throw const FormatException('Negative read length');
    if (length == 0) return const [];
    final output = Uint8List(length);
    var written = 0;
    while (written < length) {
      if (_offset >= _chunk.length) {
        if (_done) {
          throw const FormatException('Unexpected end of encrypted stream');
        }
        final moved = await _iterator.moveNext().timeout(timeout);
        if (!moved) {
          _done = true;
          throw const FormatException('Unexpected end of encrypted stream');
        }
        _chunk = _iterator.current;
        _offset = 0;
        if (_chunk.isEmpty) continue;
      }
      final available = _chunk.length - _offset;
      final needed = length - written;
      final take = min(available, needed);
      output.setRange(written, written + take, _chunk, _offset);
      written += take;
      _offset += take;
    }
    return output;
  }

  Future<bool> hasMore() async {
    if (_offset < _chunk.length) return true;
    if (_done) return false;
    while (true) {
      final moved = await _iterator.moveNext().timeout(timeout);
      if (!moved) {
        _done = true;
        return false;
      }
      _chunk = _iterator.current;
      _offset = 0;
      if (_chunk.isNotEmpty) return true;
    }
  }
}
