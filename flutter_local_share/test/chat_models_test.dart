import 'package:flutter_test/flutter_test.dart';
import 'package:local_share/models.dart';

void main() {
  test('classifies http and https URLs as links', () {
    expect(classifyChatText('https://openai.com'), ChatMessageKind.link);
    expect(classifyChatText('http://192.168.1.1/test'), ChatMessageKind.link);
  });

  test('ordinary text remains chat text', () {
    expect(classifyChatText('مرحبا من LocalShare'), ChatMessageKind.text);
    expect(classifyChatText('openai.com'), ChatMessageKind.text);
  });

  test('chat file state can move from temporary to permanent', () {
    final message = ChatMessage(
      id: 'message_12345678',
      peerId: 'peer_device_12345678',
      peerName: 'PC',
      kind: ChatMessageKind.file,
      direction: ChatMessageDirection.receive,
      sentAt: DateTime(2026, 8, 22),
      fileName: 'report.pdf',
      fileSize: 123,
      localPath: r'C:\Temp\report.pdf',
      temporary: true,
    );
    expect(message.temporary, isTrue);
    expect(message.savedPermanently, isFalse);
    message.temporary = false;
    message.savedPermanently = true;
    message.localPath = r'C:\Users\User\Downloads\report.pdf';
    expect(message.temporary, isFalse);
    expect(message.savedPermanently, isTrue);
  });

  test('safe file name blocks traversal and Windows device names', () {
    expect(safeFileName('../../CON.txt'), '_CON.txt');
    expect(safeFileName('..\\..\\photo.jpg'), 'photo.jpg');
  });
}
