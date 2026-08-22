import 'package:flutter_test/flutter_test.dart';
import 'package:local_share/models.dart';

void main() {
  group('safeFileName', () {
    test('removes path traversal', () {
      expect(safeFileName('../../secret.txt'), 'secret.txt');
      expect(safeFileName(r'C:\\temp\\photo.jpg'), 'photo.jpg');
    });

    test('replaces invalid Windows characters', () {
      expect(safeFileName('bad:name?.pdf'), 'bad_name_.pdf');
    });

    test('uses fallback for empty names', () {
      expect(safeFileName('..'), 'received_file');
    });
  });

  group('formatBytes', () {
    test('formats common units', () {
      expect(formatBytes(512), '512 B');
      expect(formatBytes(1024), '1.00 KB');
      expect(formatBytes(1024 * 1024), '1.00 MB');
    });
  });
}
