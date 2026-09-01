import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class ReadingProgressService {
  ReadingProgressService._();
  static final ReadingProgressService instance = ReadingProgressService._();

  final SharedPreferencesAsync _prefs = SharedPreferencesAsync();

  String _pathKey(String path) =>
      base64Url.encode(utf8.encode(path)).replaceAll('=', '');

  String _key(String type, String path) => 'reading.$type.${_pathKey(path)}';

  Future<int> pdfPage(String path) async {
    final page = await _prefs.getInt(_key('pdf.page', path));
    return page == null || page < 1 ? 1 : page;
  }

  Future<void> savePdfPage(String path, int page) async {
    if (page < 1) return;
    await _prefs.setInt(_key('pdf.page', path), page);
  }

  Future<double> docxOffset(String path) async {
    final offset = await _prefs.getDouble(_key('docx.offset', path));
    return offset == null || offset < 0 ? 0 : offset;
  }

  Future<void> saveDocxOffset(String path, double offset) async {
    if (!offset.isFinite || offset < 0) return;
    await _prefs.setDouble(_key('docx.offset', path), offset);
  }

  Future<void> clear(String path) async {
    await _prefs.remove(_key('pdf.page', path));
    await _prefs.remove(_key('docx.offset', path));
  }
}
