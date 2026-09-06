import 'package:flutter_test/flutter_test.dart';
import 'package:local_share/models.dart';

void main() {
  group('safeFileName', () {
    test('removes path traversal', () {
      expect(safeFileName('../../secret.txt'), 'secret.txt');
      expect(safeFileName(r'C:\\temp\\photo.jpg'), 'photo.jpg');
    });

    test('replaces invalid and control characters', () {
      expect(safeFileName('bad:name?.pdf'), 'bad_name_.pdf');
      expect(safeFileName('bad\u0000name.txt'), 'bad_name.txt');
    });

    test('blocks reserved Windows device names', () {
      expect(safeFileName('CON'), '_CON');
      expect(safeFileName('lpt1.txt'), '_lpt1.txt');
    });

    test('removes trailing dots and spaces', () {
      expect(safeFileName('report.txt...  '), 'report.txt');
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
