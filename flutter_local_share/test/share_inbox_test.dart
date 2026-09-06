import 'package:flutter_test/flutter_test.dart';
import 'package:local_share/share_inbox.dart';

void main() {
  test('external shared text is parsed safely', () {
    final item = ExternalShareItem.fromDynamic({
      'kind': 'text',
      'text': 'https://example.com',
    });
    expect(item.isText, isTrue);
    expect(item.isUri, isFalse);
    expect(item.text, 'https://example.com');
  });

  test('external shared content uri keeps display name', () {
    final item = ExternalShareItem.fromDynamic({
      'kind': 'uri',
      'uri': 'content://provider/document/42',
      'name': 'photo.png',
    });
    expect(item.isUri, isTrue);
    expect(item.isText, isFalse);
    expect(item.name, 'photo.png');
  });

  test('invalid external share is rejected by flags', () {
    final item = ExternalShareItem.fromDynamic({'kind': 'uri'});
    expect(item.isUri, isFalse);
    expect(item.isText, isFalse);
  });
}
