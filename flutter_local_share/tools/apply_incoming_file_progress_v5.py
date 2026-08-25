from pathlib import Path

root = Path(__file__).resolve().parents[1]
service_path = root / 'lib' / 'chat_local_share_service.dart'
main_path = root / 'lib' / 'main.dart'
text = service_path.read_text(encoding='utf-8')

old = """    _transfers.add(transfer);
    _trimTransfers();
    notifyListeners();

    IOSink? sink;
"""
new = """    _transfers.add(transfer);
    _trimTransfers();
    final incomingMessage = ChatMessage(
      id: _randomToken(16),
      peerId: peer.deviceId,
      peerName: peer.name,
      kind: ChatMessageKind.file,
      direction: ChatMessageDirection.receive,
      sentAt: DateTime.now(),
      fileName: fileName,
      fileSize: total,
      localPath: destination.path,
      transferId: transfer.id,
      temporary: Platform.isWindows,
      savedPermanently: false,
      deliveryStatus: ChatDeliveryStatus.sending,
    );
    _messages.add(incomingMessage);
    _trimMessageHistory(peer.deviceId);
    notifyListeners();

    IOSink? sink;
"""
if old not in text:
    raise SystemExit('incoming transfer start marker not found')
text = text.replace(old, new, 1)

old = """      transfer.localPath = finalLocation;
      transfer.progress = 1;
      transfer.status = TransferStatus.completed;
      _messages.add(
        ChatMessage(
          id: _randomToken(12),
          peerId: peer.deviceId,
          peerName: peer.name,
          kind: ChatMessageKind.file,
          direction: ChatMessageDirection.receive,
          sentAt: DateTime.now(),
          fileName: fileName,
          fileSize: total,
          localPath: finalLocation,
          temporary: temporary,
          savedPermanently: permanent,
        ),
      );
      _trimMessageHistory(peer.deviceId);
      notifyListeners();
"""
new = """      transfer.localPath = finalLocation;
      transfer.progress = 1;
      transfer.status = TransferStatus.completed;
      incomingMessage.localPath = finalLocation;
      incomingMessage.temporary = temporary;
      incomingMessage.savedPermanently = permanent;
      incomingMessage.deliveryStatus = ChatDeliveryStatus.delivered;
      incomingMessage.error = null;
      notifyListeners();
"""
if old not in text:
    raise SystemExit('incoming transfer completion marker not found')
text = text.replace(old, new, 1)

old = """      transfer.status = TransferStatus.failed;
      transfer.error = 'فشل التحقق أو الحفظ النهائي للملف';
      notifyListeners();
"""
new = """      transfer.status = TransferStatus.failed;
      transfer.error = 'فشل التحقق أو الحفظ النهائي للملف';
      incomingMessage.localPath = null;
      incomingMessage.temporary = false;
      incomingMessage.savedPermanently = false;
      incomingMessage.deliveryStatus = ChatDeliveryStatus.failed;
      incomingMessage.error = 'فشل التحقق أو استلام الملف';
      notifyListeners();
"""
if old not in text:
    raise SystemExit('incoming transfer failure marker not found')
text = text.replace(old, new, 1)
service_path.write_text(text, encoding='utf-8')

main = main_path.read_text(encoding='utf-8')
old = """          Text(
            'فشل الإرسال • اضغط إعادة المحاولة',
            style: const TextStyle(
              color: Color(0xFFC62828),
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
            ),
          ),
"""
new = """          Text(
            message.isIncoming
                ? 'فشل استلام الملف'
                : 'فشل الإرسال • اضغط إعادة المحاولة',
            style: const TextStyle(
              color: Color(0xFFC62828),
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
            ),
          ),
"""
if old not in main:
    raise SystemExit('file failure UI marker not found')
main = main.replace(old, new, 1)
main_path.write_text(main, encoding='utf-8')
print('Applied incoming file timeline progress patch')
