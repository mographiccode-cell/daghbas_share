import 'package:flutter_test/flutter_test.dart';
import 'package:status_saver/main.dart';

void main() {
  test('StatusItem detects video mime type', () {
    final item = StatusItem.fromMap({
      'uri': 'content://example/1',
      'name': 'status.mp4',
      'mimeType': 'video/mp4',
      'lastModified': 123,
      'size': 456,
    });
    expect(item.isVideo, isTrue);
    expect(item.name, 'status.mp4');
  });

  test('filterStatuses separates images and videos', () {
    const image = StatusItem(
      uri: 'a',
      name: 'a.jpg',
      mimeType: 'image/jpeg',
      isVideo: false,
      lastModified: 1,
      size: 10,
    );
    const video = StatusItem(
      uri: 'b',
      name: 'b.mp4',
      mimeType: 'video/mp4',
      isVideo: true,
      lastModified: 2,
      size: 20,
    );
    expect(filterStatuses([image, video], 0).length, 2);
    expect(filterStatuses([image, video], 1), [image]);
    expect(filterStatuses([image, video], 2), [video]);
  });
}
