import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_share/security.dart';

void main() {
  late LocalShareCrypto crypto;

  setUp(() {
    crypto = LocalShareCrypto();
  });

  test('session key is symmetric across device id order', () async {
    final pairKey = List<int>.generate(32, (i) => i);
    final clientNonce = crypto.b64(List<int>.filled(16, 7));
    final serverNonce = crypto.b64(List<int>.filled(16, 9));

    final a = await crypto.deriveSessionKey(
      pairKey,
      'device_A_123456789',
      'device_B_123456789',
      clientNonce,
      serverNonce,
    );
    final b = await crypto.deriveSessionKey(
      pairKey,
      'device_B_123456789',
      'device_A_123456789',
      clientNonce,
      serverNonce,
    );

    expect(a, b);
    expect(a.length, 32);
  });

  test('encrypted metadata rejects tampering', () async {
    final key = List<int>.generate(32, (i) => 255 - i);
    final transferNonce = crypto.b64(List<int>.filled(8, 3));
    final encoded = await crypto.encryptMetadata(
      sharedKey: key,
      senderId: 'sender_device_123456',
      receiverId: 'receiver_device_1234',
      timestamp: 1700000000000,
      transferNonce: transferNonce,
      fileName: 'report.pdf',
      size: 12345,
    );

    final decoded = await crypto.decryptMetadata(
      sharedKey: key,
      senderId: 'sender_device_123456',
      receiverId: 'receiver_device_1234',
      timestamp: 1700000000000,
      transferNonce: transferNonce,
      encodedBox: encoded,
    );
    expect(decoded['name'], 'report.pdf');
    expect(decoded['size'], 12345);

    final bytes = crypto.b64d(encoded);
    bytes[bytes.length ~/ 2] ^= 1;
    await expectLater(
      crypto.decryptMetadata(
        sharedKey: key,
        senderId: 'sender_device_123456',
        receiverId: 'receiver_device_1234',
        timestamp: 1700000000000,
        transferNonce: transferNonce,
        encodedBox: crypto.b64(bytes),
      ),
      throwsA(anything),
    );
  });

  test('chunk authentication detects modified ciphertext', () async {
    final shared = List<int>.generate(32, (i) => i * 3 % 256);
    final base = List<int>.filled(8, 4);
    final transferNonce = crypto.b64(base);
    final timestamp = 1700000001000;
    final transferKey = await crypto.deriveTransferKey(
      shared,
      timestamp,
      base,
      'sender_device_123456',
      'receiver_device_1234',
    );
    final nonce = crypto.chunkNonce(base, 0);
    final aad = crypto.chunkAad(
      'sender_device_123456',
      'receiver_device_1234',
      timestamp,
      transferNonce,
      0,
      5,
    );
    final box = await crypto.cipher.encrypt(
      [1, 2, 3, 4, 5],
      secretKey: SecretKey(transferKey),
      nonce: nonce,
      aad: aad,
    );
    final tampered = [...box.cipherText]..[0] ^= 1;

    await expectLater(
      crypto.cipher.decrypt(
        SecretBox(tampered, nonce: nonce, mac: box.mac),
        secretKey: SecretKey(transferKey),
        aad: aad,
      ),
      throwsA(anything),
    );
  });

  test('encrypted body length includes one authentication tag per chunk', () {
    expect(crypto.encryptedBodyLength(0), 0);
    expect(crypto.encryptedBodyLength(1), 17);
    expect(
      crypto.encryptedBodyLength(LocalShareCrypto.chunkSize + 1),
      LocalShareCrypto.chunkSize + 1 + 32,
    );
  });

  test('constant time equality requires exact value', () {
    expect(crypto.constantTimeEquals('abc', 'abc'), isTrue);
    expect(crypto.constantTimeEquals('abc', 'abd'), isFalse);
    expect(crypto.constantTimeEquals('abc', 'ab'), isFalse);
  });
}
