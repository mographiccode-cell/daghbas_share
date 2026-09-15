import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

class XlsxWorkbookData {
  final List<XlsxSheetData> sheets;

  const XlsxWorkbookData(this.sheets);

  static Future<XlsxWorkbookData> decode(Uint8List bytes) {
    return Isolate.run(() => _decodeXlsx(bytes));
  }
}

class XlsxSheetData {
  final String name;
  final int maxRows;
  final int maxColumns;
  final bool isRtl;
  final Map<int, Map<int, String>> cells;
  final Map<int, double> columnWidths;
  final Map<int, double> rowHeights;

  const XlsxSheetData({
    required this.name,
    required this.maxRows,
    required this.maxColumns,
    required this.isRtl,
    required this.cells,
    required this.columnWidths,
    required this.rowHeights,
  });

  String valueAt(int row, int column) => cells[row]?[column] ?? '';

  double widthAt(int column) => columnWidths[column] ?? 12.0;

  double heightAt(int row) => rowHeights[row] ?? 20.0;
}

XlsxWorkbookData _decodeXlsx(Uint8List bytes) {
  if (bytes.length < 4 ||
      bytes[0] != 0x50 ||
      bytes[1] != 0x4B ||
      bytes[2] != 0x03 ||
      bytes[3] != 0x04) {
    throw const FormatException(
      'هذه ليست حزمة XLSX حديثة. ملفات XLS القديمة لا تُعرض في العارض الآمن الحالي.',
    );
  }

  final archive = ZipDecoder().decodeBytes(bytes, verify: true);
  final workbook = _xml(archive, 'xl/workbook.xml');
  final relationships = _xml(archive, 'xl/_rels/workbook.xml.rels');
  final sharedStrings = _readSharedStrings(archive);

  final relationTargets = <String, String>{};
  for (final rel in relationships.descendants.whereType<XmlElement>()) {
    if (rel.name.local != 'Relationship') continue;
    final id = _attr(rel, 'Id');
    final target = _attr(rel, 'Target');
    if (id == null || target == null) continue;
    relationTargets[id] = _resolveXlTarget(target);
  }

  final sheets = <XlsxSheetData>[];
  for (final node in workbook.descendants.whereType<XmlElement>()) {
    if (node.name.local != 'sheet') continue;
    final name = _attr(node, 'name') ?? 'Sheet ${sheets.length + 1}';
    final relationId = _attr(node, 'id');
    if (relationId == null) continue;
    final target = relationTargets[relationId];
    if (target == null) continue;
    final sheetXml = _xml(archive, target);
    sheets.add(_parseSheet(name, sheetXml, sharedStrings));
  }

  if (sheets.isEmpty) {
    throw const FormatException('لم يتم العثور على أوراق عمل قابلة للقراءة داخل الملف.');
  }
  return XlsxWorkbookData(List.unmodifiable(sheets));
}

XlsxSheetData _parseSheet(
  String name,
  XmlDocument document,
  List<String> sharedStrings,
) {
  final cells = <int, Map<int, String>>{};
  final widths = <int, double>{};
  final heights = <int, double>{};
  var maxRow = 0;
  var maxColumn = 0;
  var isRtl = false;

  for (final node in document.descendants.whereType<XmlElement>()) {
    switch (node.name.local) {
      case 'sheetView':
        final rtl = _attr(node, 'rightToLeft');
        if (rtl == '1' || rtl?.toLowerCase() == 'true') isRtl = true;
      case 'col':
        final min = int.tryParse(_attr(node, 'min') ?? '');
        final max = int.tryParse(_attr(node, 'max') ?? '');
        final width = double.tryParse(_attr(node, 'width') ?? '');
        if (min != null && max != null && width != null) {
          for (var col = min - 1; col <= max - 1 && col < 16384; col++) {
            widths[col] = width;
          }
        }
      case 'row':
        final rowNumber = int.tryParse(_attr(node, 'r') ?? '');
        final height = double.tryParse(_attr(node, 'ht') ?? '');
        if (rowNumber != null && height != null) {
          heights[rowNumber - 1] = height;
        }
      case 'c':
        final reference = _attr(node, 'r');
        if (reference == null) continue;
        final coordinate = _coordinate(reference);
        if (coordinate == null) continue;
        final row = coordinate.$1;
        final column = coordinate.$2;
        final value = _cellValue(node, sharedStrings);
        if (value.isNotEmpty) {
          (cells[row] ??= <int, String>{})[column] = value;
        }
        if (row + 1 > maxRow) maxRow = row + 1;
        if (column + 1 > maxColumn) maxColumn = column + 1;
    }
  }

  final dimension = document.descendants
      .whereType<XmlElement>()
      .where((e) => e.name.local == 'dimension')
      .cast<XmlElement?>()
      .firstOrNull;
  final dimensionRef = dimension == null ? null : _attr(dimension, 'ref');
  if (dimensionRef != null && dimensionRef.contains(':')) {
    final last = dimensionRef.split(':').last;
    final coordinate = _coordinate(last);
    if (coordinate != null) {
      maxRow = maxRow < coordinate.$1 + 1 ? coordinate.$1 + 1 : maxRow;
      maxColumn =
          maxColumn < coordinate.$2 + 1 ? coordinate.$2 + 1 : maxColumn;
    }
  }

  maxRow = maxRow.clamp(1, 1048576);
  maxColumn = maxColumn.clamp(1, 16384);

  return XlsxSheetData(
    name: name,
    maxRows: maxRow,
    maxColumns: maxColumn,
    isRtl: isRtl,
    cells: cells,
    columnWidths: widths,
    rowHeights: heights,
  );
}

String _cellValue(XmlElement cell, List<String> sharedStrings) {
  final type = _attr(cell, 't');
  if (type == 'inlineStr') {
    return cell.descendants
        .whereType<XmlElement>()
        .where((e) => e.name.local == 't')
        .map((e) => e.innerText)
        .join();
  }

  final valueElement = cell.children
      .whereType<XmlElement>()
      .where((e) => e.name.local == 'v')
      .cast<XmlElement?>()
      .firstOrNull;
  final raw = valueElement?.innerText ?? '';

  if (type == 's') {
    final index = int.tryParse(raw);
    if (index != null && index >= 0 && index < sharedStrings.length) {
      return sharedStrings[index];
    }
    return raw;
  }
  if (type == 'b') return raw == '1' ? 'TRUE' : 'FALSE';
  if (type == 'str' || type == 'e') return raw;
  return raw;
}

List<String> _readSharedStrings(Archive archive) {
  final file = _find(archive, 'xl/sharedStrings.xml');
  if (file == null) return const [];
  final bytes = file.readBytes();
  if (bytes == null) return const [];
  final document = XmlDocument.parse(utf8.decode(bytes, allowMalformed: true));
  return document.descendants
      .whereType<XmlElement>()
      .where((e) => e.name.local == 'si')
      .map(
        (si) => si.descendants
            .whereType<XmlElement>()
            .where((e) => e.name.local == 't')
            .map((t) => t.innerText)
            .join(),
      )
      .toList(growable: false);
}

XmlDocument _xml(Archive archive, String name) {
  final file = _find(archive, name);
  if (file == null) throw FormatException('ملف XLSX الداخلي مفقود: $name');
  final bytes = file.readBytes();
  if (bytes == null) throw FormatException('تعذر قراءة جزء XLSX: $name');
  return XmlDocument.parse(utf8.decode(bytes, allowMalformed: true));
}

ArchiveFile? _find(Archive archive, String name) {
  final normalized = p.posix.normalize(name).replaceFirst(RegExp(r'^/'), '');
  for (final file in archive.files) {
    if (p.posix.normalize(file.name).replaceFirst(RegExp(r'^/'), '') ==
        normalized) {
      return file;
    }
  }
  return null;
}

String _resolveXlTarget(String target) {
  var value = target.replaceAll('\\', '/');
  if (value.startsWith('/')) value = value.substring(1);
  if (value.startsWith('xl/')) return p.posix.normalize(value);
  return p.posix.normalize(p.posix.join('xl', value));
}

String? _attr(XmlElement element, String localName) {
  for (final attribute in element.attributes) {
    if (attribute.name.local == localName) return attribute.value;
  }
  return null;
}

(int, int)? _coordinate(String reference) {
  final match = RegExp(r'^([A-Za-z]+)([0-9]+)').firstMatch(reference);
  if (match == null) return null;
  final letters = match.group(1)!.toUpperCase();
  final rowNumber = int.tryParse(match.group(2)!);
  if (rowNumber == null || rowNumber < 1) return null;
  var column = 0;
  for (final unit in letters.codeUnits) {
    column = column * 26 + (unit - 64);
  }
  if (column < 1) return null;
  return (rowNumber - 1, column - 1);
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
