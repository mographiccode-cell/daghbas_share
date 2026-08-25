import 'package:flutter_test/flutter_test.dart';
import '../lib/main.dart';

void main() {
  test('StatusItem detects video mime type', () {
    final item = StatusItem.fromMap({
      'uri': 'content://status/1',
      'name': 'clip.mp4',
      'mimeType': 'video/mp4',
      'lastModified': 1,
      'size': 10,
    });
    expect(item.isVideo, isTrue);
    expect(item.name, 'clip.mp4');
  });

  test('StatusItem accepts explicit video flag', () {
    final item = StatusItem.fromMap({
      'uri': 'content://status/2',
      'name': 'clip.bin',
      'mimeType': 'application/octet-stream',
      'isVideo': true,
    });
    expect(item.isVideo, isTrue);
  });

  test('filterStatuses separates images and videos', () {
    const image = StatusItem(
      uri: 'i',
      name: 'a.jpg',
      mimeType: 'image/jpeg',
      isVideo: false,
      lastModified: 1,
      size: 1,
    );
    const video = StatusItem(
      uri: 'v',
      name: 'b.mp4',
      mimeType: 'video/mp4',
      isVideo: true,
      lastModified: 2,
      size: 2,
    );
    expect(filterStatuses([image, video], 0).length, 2);
    expect(filterStatuses([image, video], 1), [image]);
    expect(filterStatuses([image, video], 2), [video]);
  });

  test('formatFileSize is readable and handles empty sizes', () {
    expect(formatFileSize(0), '');
    expect(formatFileSize(512), '512 B');
    expect(formatFileSize(1024), '1.0 KB');
    expect(formatFileSize(1024 * 1024), '1.0 MB');
  });
}
