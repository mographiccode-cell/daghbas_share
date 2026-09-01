import 'dart:io';
import 'package:path/path.dart' as p;

enum DocumentKind { pdf, word, excel, powerpoint, text, other }

class DocumentItem {
  final String path;
  final String name;
  final String extension;
  final int size;
  final DateTime modifiedAt;
  final DateTime? lastOpenedAt;
  final bool isFavorite;

  const DocumentItem({
    required this.path,
    required this.name,
    required this.extension,
    required this.size,
    required this.modifiedAt,
    this.lastOpenedAt,
    this.isFavorite = false,
  });

  static const supportedExtensions = <String>{
    'pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx',
    'txt', 'csv', 'rtf', 'md', 'json', 'xml', 'log', 'yaml', 'yml',
  };

  static const officeExtensions = <String>{'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx'};
  static const textExtensions = <String>{'txt', 'csv', 'rtf', 'md', 'json', 'xml', 'log', 'yaml', 'yml'};

  bool get isSupported => supportedExtensions.contains(extension.toLowerCase());

  DocumentKind get kind => kindForExtension(extension);

  static DocumentKind kindForExtension(String rawExtension) {
    final ext = rawExtension.replaceFirst('.', '').toLowerCase();
    if (ext == 'pdf') return DocumentKind.pdf;
    if (ext == 'doc' || ext == 'docx') return DocumentKind.word;
    if (ext == 'xls' || ext == 'xlsx') return DocumentKind.excel;
    if (ext == 'ppt' || ext == 'pptx') return DocumentKind.powerpoint;
    if (textExtensions.contains(ext)) {
      return DocumentKind.text;
    }
    return DocumentKind.other;
  }

  static Future<DocumentItem?> fromPath(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return null;
      final ext = p.extension(filePath).replaceFirst('.', '').toLowerCase();
      if (!supportedExtensions.contains(ext)) return null;
      final stat = await file.stat();
      if (stat.type != FileSystemEntityType.file) return null;
      return DocumentItem(
        path: filePath,
        name: p.basename(filePath),
        extension: ext,
        size: stat.size,
        modifiedAt: stat.modified,
      );
    } on FileSystemException {
      return null;
    }
  }

  Map<String, Object?> toMap() => {
        'path': path,
        'name': name,
        'extension': extension,
        'size': size,
        'modified_at': modifiedAt.millisecondsSinceEpoch,
        'last_opened_at': lastOpenedAt?.millisecondsSinceEpoch,
        'is_favorite': isFavorite ? 1 : 0,
      };

  factory DocumentItem.fromMap(Map<String, Object?> map) => DocumentItem(
        path: map['path']! as String,
        name: map['name']! as String,
        extension: (map['extension'] as String? ?? '').toLowerCase(),
        size: map['size'] as int? ?? 0,
        modifiedAt: DateTime.fromMillisecondsSinceEpoch(map['modified_at'] as int? ?? 0),
        lastOpenedAt: map['last_opened_at'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(map['last_opened_at']! as int),
        isFavorite: (map['is_favorite'] as int? ?? 0) == 1,
      );

  DocumentItem copyWith({DateTime? lastOpenedAt, bool? isFavorite}) => DocumentItem(
        path: path,
        name: name,
        extension: extension,
        size: size,
        modifiedAt: modifiedAt,
        lastOpenedAt: lastOpenedAt ?? this.lastOpenedAt,
        isFavorite: isFavorite ?? this.isFavorite,
      );
}
