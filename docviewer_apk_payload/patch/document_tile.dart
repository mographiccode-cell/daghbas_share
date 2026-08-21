import 'package:flutter/material.dart';
import '../models/document_item.dart';

class DocumentTile extends StatelessWidget {
  final DocumentItem item;
  final VoidCallback onOpen;
  final VoidCallback onFavorite;
  final bool isOpening;
  const DocumentTile({
    super.key,
    required this.item,
    required this.onOpen,
    required this.onFavorite,
    this.isOpening = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = _kindColor(item.kind);
    return Card(
      elevation: 0,
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: isOpening ? null : onOpen,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(color: color.withValues(alpha: .12), borderRadius: BorderRadius.circular(14)),
                child: Icon(_icon(item.kind), color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _cleanName(item.name),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 5),
                    Wrap(
                      spacing: 7,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(item.extension.toUpperCase(), style: TextStyle(color: color, fontWeight: FontWeight.w700)),
                        Text(_size(item.size)),
                        Text(_date(item.modifiedAt)),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              if (isOpening)
                const SizedBox(width: 42, height: 42, child: Padding(padding: EdgeInsets.all(10), child: CircularProgressIndicator(strokeWidth: 2.4)))
              else
                IconButton(
                  tooltip: item.isFavorite ? 'إزالة من المفضلة' : 'إضافة للمفضلة',
                  onPressed: onFavorite,
                  icon: Icon(item.isFavorite ? Icons.star_rounded : Icons.star_border_rounded),
                ),
            ],
          ),
        ),
      ),
    );
  }

  static String _cleanName(String value) {
    final cleaned = value.replaceAll('\uFFFD', '').replaceAll(RegExp(r'\s+'), ' ').trim();
    return cleaned.isEmpty ? 'مستند بدون اسم' : cleaned;
  }

  static IconData _icon(DocumentKind kind) => switch (kind) {
        DocumentKind.pdf => Icons.picture_as_pdf_rounded,
        DocumentKind.word => Icons.description_rounded,
        DocumentKind.excel => Icons.table_chart_rounded,
        DocumentKind.powerpoint => Icons.slideshow_rounded,
        DocumentKind.text => Icons.article_rounded,
        DocumentKind.other => Icons.insert_drive_file_rounded,
      };

  static Color _kindColor(DocumentKind kind) => switch (kind) {
        DocumentKind.pdf => Colors.red.shade700,
        DocumentKind.word => Colors.blue.shade700,
        DocumentKind.excel => Colors.green.shade700,
        DocumentKind.powerpoint => Colors.deepOrange.shade700,
        DocumentKind.text => Colors.teal.shade700,
        DocumentKind.other => Colors.grey.shade700,
      };

  static String _size(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  static String _date(DateTime d) => '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';
}
