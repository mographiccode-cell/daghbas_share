import 'package:flutter_test/flutter_test.dart';
import 'package:local_share/models.dart';
import 'package:local_share/notifications.dart';

void main() {
  ChatMessage incoming({
    required String id,
    ChatMessageKind kind = ChatMessageKind.text,
    String text = '',
    String? fileName,
    int? fileSize,
  }) {
    return ChatMessage(
      id: id,
      peerId: 'peer_12345678',
      peerName: 'جهاز الاختبار',
      kind: kind,
      direction: ChatMessageDirection.receive,
      sentAt: DateTime(2026, 8, 25, 19, 0),
      text: text,
      fileName: fileName,
      fileSize: fileSize,
    );
  }

  test('notification preview sanitizes controls and excessive whitespace', () {
    final body = notificationBodyFor(
      incoming(id: 'msg_clean_123', text: 'مرحبا\n\n   بك\x07'),
    );
    expect(body, 'مرحبا بك');
  });

  test('notification preview is bounded', () {
    final body = notificationBodyFor(
      incoming(id: 'msg_long_123', text: List.filled(250, 'ا').join()),
    );
    expect(body.length, lessThanOrEqualTo(180));
    expect(body.endsWith('…'), isTrue);
  });

  test('file notification contains safe file summary', () {
    final body = notificationBodyFor(
      incoming(
        id: 'file_msg_123',
        kind: ChatMessageKind.file,
        fileName: 'report.pdf',
        fileSize: 2048,
      ),
    );
    expect(body, contains('report.pdf'));
    expect(body, contains('2.00 KB'));
  });

  test('link notification shows host rather than full sensitive URL', () {
    final body = notificationBodyFor(
      incoming(
        id: 'link_msg_123',
        kind: ChatMessageKind.link,
        text: 'https://example.com/private/token?secret=123',
      ),
    );
    expect(body, contains('example.com'));
    expect(body, isNot(contains('secret=123')));
  });

  test('notification id is deterministic and positive', () {
    final first = notificationIdFor('message_abc_123');
    final second = notificationIdFor('message_abc_123');
    expect(first, second);
    expect(first, greaterThan(0));
  });
}
