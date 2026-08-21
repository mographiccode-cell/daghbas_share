import 'package:flutter/material.dart';
import '../models/document_item.dart';

class DocumentTile extends StatelessWidget {
  final DocumentItem item;
  final VoidCallback onOpen;
  final VoidCallback onFavorite;
  final VoidCallback? onDetails;
  final bool isOpening;
  final bool compact;

  const DocumentTile({
    super.key,
    required this.item,
    required this.onOpen,
    required this.onFavorite,
    this.onDetails,
    this.isOpening = false,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = kindColor(item.kind);
    final scheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      margin: EdgeInsets.symmetric(horizontal: compact ? 0 : 14, vertical: 5),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: isOpening ? null : onOpen,
        onLongPress: onDetails,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 12 : 14,
            vertical: compact ? 10 : 12,
          ),
          child: Row(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: compact ? 46 : 52,
                    height: compact ? 46 : 52,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: .11),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: color.withValues(alpha: .10)),
                    ),
                    child: Icon(kindIcon(item.kind), color: color, size: compact ? 24 : 27),
                  ),
                  if (item.isFavorite)
                    Positioned(
                      left: -4,
                      top: -4,
                      child: Container(
                        width: 19,
                        height: 19,
                        decoration: BoxDecoration(
                          color: scheme.tertiaryContainer,
                          shape: BoxShape.circle,
                          border: Border.all(color: scheme.surface, width: 2),
                        ),
                        child: Icon(Icons.star_rounded, size: 12, color: scheme.onTertiaryContainer),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      cleanName(item.name),
                      maxLines: compact ? 1 : 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            height: 1.25,
                          ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 3,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: .10),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            item.extension.toUpperCase(),
                            style: TextStyle(
                              color: color,
                              fontWeight: FontWeight.w800,
                              fontSize: 11,
                            ),
                          ),
                        ),
                        Text(sizeText(item.size), style: Theme.of(context).textTheme.bodySmall),
                        Text('•', style: TextStyle(color: scheme.outline)),
                        Text(dateText(item.modifiedAt), style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              if (isOpening)
                const SizedBox(
                  width: 40,
                  height: 40,
                  child: Padding(
                    padding: EdgeInsets.all(10),
                    child: CircularProgressIndicator(strokeWidth: 2.4),
                  ),
                )
              else
                IconButton(
                  tooltip: 'معلومات المستند',
                  onPressed: onDetails,
                  icon: const Icon(Icons.more_vert_rounded),
                ),
            ],
          ),
        ),
      ),
    );
  }

  static String cleanName(String value) {
    final cleaned = value.replaceAll('\uFFFD', '').replaceAll(RegExp(r'\s+'), ' ').trim();
    return cleaned.isEmpty ? 'مستند بدون اسم' : cleaned;
  }

  static IconData kindIcon(DocumentKind kind) => switch (kind) {
        DocumentKind.pdf => Icons.picture_as_pdf_rounded,
        DocumentKind.word => Icons.description_rounded,
        DocumentKind.excel => Icons.table_chart_rounded,
        DocumentKind.powerpoint => Icons.slideshow_rounded,
        DocumentKind.text => Icons.article_rounded,
        DocumentKind.other => Icons.insert_drive_file_rounded,
      };

  static Color kindColor(DocumentKind kind) => switch (kind) {
        DocumentKind.pdf => const Color(0xFFE53935),
        DocumentKind.word => const Color(0xFF2472E8),
        DocumentKind.excel => const Color(0xFF168A4A),
        DocumentKind.powerpoint => const Color(0xFFF26522),
        DocumentKind.text => const Color(0xFF008C95),
        DocumentKind.other => const Color(0xFF667085),
      };

  static String sizeText(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  static String dateText(DateTime d) =>
      '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';
}
