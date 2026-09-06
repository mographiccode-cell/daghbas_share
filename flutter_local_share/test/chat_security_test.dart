import 'package:flutter_test/flutter_test.dart';
import 'package:local_share/security.dart';

void main() {
  test('encrypted chat payload round-trips and rejects tampering', () async {
    final crypto = LocalShareCrypto();
    final key = List<int>.generate(32, (i) => (i * 11) % 256);
    final nonce = crypto.b64(List<int>.generate(12, (i) => i + 1));
    const sender = 'sender_device_123456';
    const receiver = 'receiver_device_1234';
    const timestamp = 1700000000000;

    final encoded = await crypto.encryptPayload(
      sharedKey: key,
      senderId: sender,
      receiverId: receiver,
      timestamp: timestamp,
      nonceId: nonce,
      purpose: 'message',
      payload: const {
        'id': 'message_12345678',
        'kind': 'text',
        'text': 'hello',
      },
    );

    final decoded = await crypto.decryptPayload(
      sharedKey: key,
      senderId: sender,
      receiverId: receiver,
      timestamp: timestamp,
      nonceId: nonce,
      purpose: 'message',
      encodedBox: encoded,
    );
    expect(decoded['text'], 'hello');
    expect(decoded['kind'], 'text');

    final bytes = crypto.b64d(encoded);
    bytes[bytes.length ~/ 2] ^= 1;
    await expectLater(
      crypto.decryptPayload(
        sharedKey: key,
        senderId: sender,
        receiverId: receiver,
        timestamp: timestamp,
        nonceId: nonce,
        purpose: 'message',
        encodedBox: crypto.b64(bytes),
      ),
      throwsA(anything),
    );
  });

  test('chat payload purpose is authenticated', () async {
    final crypto = LocalShareCrypto();
    final key = List<int>.filled(32, 9);
    final nonce = crypto.b64(List<int>.filled(12, 4));
    final encoded = await crypto.encryptPayload(
      sharedKey: key,
      senderId: 'sender_device_123456',
      receiverId: 'receiver_device_1234',
      timestamp: 1700000000000,
      nonceId: nonce,
      purpose: 'message',
      payload: const {
        'id': 'message_12345678',
        'kind': 'link',
        'text': 'https://example.com',
      },
    );

    await expectLater(
      crypto.decryptPayload(
        sharedKey: key,
        senderId: 'sender_device_123456',
        receiverId: 'receiver_device_1234',
        timestamp: 1700000000000,
        nonceId: nonce,
        purpose: 'meta',
        encodedBox: encoded,
      ),
      throwsA(anything),
    );
  });
}
