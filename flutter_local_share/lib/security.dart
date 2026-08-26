import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

class LocalShareCrypto {
  LocalShareCrypto()
    : cipher = Chacha20.poly1305Aead(),
      hmac = Hmac.sha256(),
      hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32),
      pairKdf = Argon2id(
        memory: 64 * 1024,
        parallelism: 1,
        iterations: 2,
        hashLength: 32,
      );

  static const int protocolVersion = 3;
  static const int chunkSize = 256 * 1024;

  final Cipher cipher;
  final Hmac hmac;
  final Hkdf hkdf;
  final Argon2id pairKdf;

  Future<List<int>> derivePairKey(
    String code,
    List<int> salt,
    String firstId,
    String secondId,
  ) async {
    final ids = [firstId, secondId]..sort();
    final nonce = <int>[
      ...salt,
      ...utf8.encode('|${ids[0]}|${ids[1]}|LocalShare3'),
    ];
    final key = await pairKdf.deriveKeyFromPassword(
      password: code,
      nonce: nonce,
    );
    return key.extractBytes();
  }

  Future<List<int>> deriveSessionKey(
    List<int> pairKey,
    String firstId,
    String secondId,
    String clientNonce,
    String serverNonce,
  ) async {
    final ids = [firstId, secondId]..sort();
    final key = await hkdf.deriveKey(
      secretKey: SecretKey(pairKey),
      nonce: <int>[...b64d(clientNonce), ...b64d(serverNonce)],
      info: utf8.encode('LocalShare3-session|${ids[0]}|${ids[1]}'),
    );
    return key.extractBytes();
  }

  Future<List<int>> deriveTransferKey(
    List<int> sharedKey,
    int timestamp,
    List<int> transferNonce,
    String senderId,
    String receiverId,
  ) async {
    final key = await hkdf.deriveKey(
      secretKey: SecretKey(sharedKey),
      nonce: <int>[...transferNonce, ...int64be(timestamp)],
      info: utf8.encode('LocalShare3-transfer|$senderId|$receiverId'),
    );
    return key.extractBytes();
  }

  Future<String> macString(List<int> key, String message) async {
    final mac = await hmac.calculateMac(
      utf8.encode(message),
      secretKey: SecretKey(key),
    );
    return b64(mac.bytes);
  }

  Future<String> encryptMetadata({
    required List<int> sharedKey,
    required String senderId,
    required String receiverId,
    required int timestamp,
    required String transferNonce,
    required String fileName,
    required int size,
  }) {
    return encryptPayload(
      sharedKey: sharedKey,
      senderId: senderId,
      receiverId: receiverId,
      timestamp: timestamp,
      nonceId: transferNonce,
      purpose: 'meta',
      payload: {'name': fileName, 'size': size},
    );
  }

  Future<Map<String, dynamic>> decryptMetadata({
    required List<int> sharedKey,
    required String senderId,
    required String receiverId,
    required int timestamp,
    required String transferNonce,
    required String encodedBox,
  }) {
    return decryptPayload(
      sharedKey: sharedKey,
      senderId: senderId,
      receiverId: receiverId,
      timestamp: timestamp,
      nonceId: transferNonce,
      purpose: 'meta',
      encodedBox: encodedBox,
    );
  }

  Future<String> encryptPayload({
    required List<int> sharedKey,
    required String senderId,
    required String receiverId,
    required int timestamp,
    required String nonceId,
    required String purpose,
    required Map<String, dynamic> payload,
  }) async {
    final aad = payloadAad(senderId, receiverId, timestamp, nonceId, purpose);
    final box = await cipher.encrypt(
      utf8.encode(jsonEncode(payload)),
      secretKey: SecretKey(sharedKey),
      nonce: randomBytes(cipher.nonceLength),
      aad: aad,
    );
    return b64(box.concatenation());
  }

  Future<Map<String, dynamic>> decryptPayload({
    required List<int> sharedKey,
    required String senderId,
    required String receiverId,
    required int timestamp,
    required String nonceId,
    required String purpose,
    required String encodedBox,
  }) async {
    final raw = b64d(encodedBox);
    final box = SecretBox.fromConcatenation(
      raw,
      nonceLength: cipher.nonceLength,
      macLength: cipher.macAlgorithm.macLength,
    );
    final clear = await cipher.decrypt(
      box,
      secretKey: SecretKey(sharedKey),
      aad: payloadAad(senderId, receiverId, timestamp, nonceId, purpose),
    );
    final decoded = jsonDecode(utf8.decode(clear));
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid encrypted payload');
    }
    return decoded;
  }

  List<int> metadataAad(
    String senderId,
    String receiverId,
    int timestamp,
    String transferNonce,
  ) {
    return payloadAad(senderId, receiverId, timestamp, transferNonce, 'meta');
  }

  List<int> payloadAad(
    String senderId,
    String receiverId,
    int timestamp,
    String nonceId,
    String purpose,
  ) {
    return utf8.encode(
      'LocalShare3-$purpose|$senderId|$receiverId|$timestamp|$nonceId',
    );
  }

  List<int> chunkNonce(List<int> base, int index) {
    if (base.length != 8 || index < 0 || index > 0xFFFFFFFF) {
      throw const FormatException('Invalid chunk nonce');
    }
    return <int>[
      ...base,
      (index >> 24) & 0xFF,
      (index >> 16) & 0xFF,
      (index >> 8) & 0xFF,
      index & 0xFF,
    ];
  }

  List<int> chunkAad(
    String senderId,
    String receiverId,
    int timestamp,
    String transferNonce,
    int chunkIndex,
    int total,
  ) {
    return utf8.encode(
      'LocalShare3-chunk|$senderId|$receiverId|$timestamp|$transferNonce|$chunkIndex|$total',
    );
  }

  int encryptedBodyLength(int total) {
    if (total <= 0) return 0;
    final chunks = (total + chunkSize - 1) ~/ chunkSize;
    return total + chunks * cipher.macAlgorithm.macLength;
  }

  bool constantTimeEquals(String a, String b) {
    final aa = utf8.encode(a);
    final bb = utf8.encode(b);
    var diff = aa.length ^ bb.length;
    final maxLength = max(aa.length, bb.length);
    for (var i = 0; i < maxLength; i++) {
      final av = i < aa.length ? aa[i] : 0;
      final bv = i < bb.length ? bb[i] : 0;
      diff |= av ^ bv;
    }
    return diff == 0;
  }

  bool isValidB64Length(String value, int expectedBytes) {
    try {
      return b64d(value).length == expectedBytes;
    } catch (_) {
      return false;
    }
  }

  List<int> randomBytes(int length) {
    final random = Random.secure();
    return List<int>.generate(
      length,
      (_) => random.nextInt(256),
      growable: false,
    );
  }

  String b64(List<int> bytes) => base64UrlEncode(bytes).replaceAll('=', '');

  List<int> b64d(String value) {
    var padded = value.trim();
    final remainder = padded.length % 4;
    if (remainder != 0) padded += '=' * (4 - remainder);
    return base64Url.decode(padded);
  }

  List<int> int64be(int value) {
    final data = ByteData(8)..setInt64(0, value, Endian.big);
    return data.buffer.asUint8List();
  }
}
