import 'dart:convert';
import 'dart:io';

import 'package:doc_viewer/doc_viewer.dart';
import 'package:docx_file_viewer/docx_file_viewer.dart';
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import '../models/document_item.dart';

class ViewerScreen extends StatelessWidget {
  final DocumentItem item;
  const ViewerScreen({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    final typeColor = _kindColor(item.kind);
    return Scaffold(
      backgroundColor: item.extension.toLowerCase() == 'docx'
          ? const Color(0xFFE9EBF1)
          : Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            Text(
              item.extension.toUpperCase(),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(color: typeColor),
            ),
          ],
        ),
      ),
      body: _buildViewer(context),
    );
  }

  Widget _buildViewer(BuildContext context) {
    if (item.kind == DocumentKind.pdf) {
      return PdfViewer.file(item.path);
    }
    if (item.kind == DocumentKind.word && item.extension.toLowerCase() == 'docx') {
      return _DocxViewer(item: item);
    }
    if (item.kind == DocumentKind.word ||
        item.kind == DocumentKind.excel ||
        item.kind == DocumentKind.powerpoint) {
      return _OfficeViewer(item: item);
    }
    if (item.kind == DocumentKind.text) {
      return _TextViewer(path: item.path);
    }
    return const _ViewerMessage(
      icon: Icons.error_outline_rounded,
      title: 'هذا النوع غير مدعوم',
      message: 'لا يمكن معاينة هذا المستند داخل التطبيق.',
    );
  }

  static Color _kindColor(DocumentKind kind) => switch (kind) {
        DocumentKind.pdf => Colors.red.shade700,
        DocumentKind.word => Colors.blue.shade700,
        DocumentKind.excel => Colors.green.shade700,
        DocumentKind.powerpoint => Colors.deepOrange.shade700,
        DocumentKind.text => Colors.teal.shade700,
        DocumentKind.other => Colors.grey.shade700,
      };
}

class _DocxViewer extends StatelessWidget {
  final DocumentItem item;
  const _DocxViewer({required this.item});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFFE9EBF1),
      child: DocxView.file(
        File(item.path),
        config: DocxViewConfig(
          pageMode: DocxPageMode.paged,
          pageWidth: 794,
          pageHeight: 1123,
          enableZoom: true,
          enableSearch: true,
          enableSelection: true,
          showPageBreaks: true,
          showDebugInfo: false,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          backgroundColor: const Color(0xFFE9EBF1),
          theme: DocxViewTheme.light(),
          customFontFallbacks: const [
            'Arial',
            'Calibri',
            'Times New Roman',
            'Roboto',
          ],
        ),
        onError: (error) {
          debugPrint('DOCX render error: $error');
        },
      ),
    );
  }
}

class _OfficeViewer extends StatelessWidget {
  final DocumentItem item;
  const _OfficeViewer({required this.item});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Theme.of(context).colorScheme.surface,
      child: DocViewerView(
        filePath: item.path,
        darkMode: Theme.of(context).brightness == Brightness.dark,
        missingFileBuilder: (_) => const _ViewerMessage(
          icon: Icons.file_present_outlined,
          title: 'الملف غير موجود',
          message: 'تعذر العثور على المستند في موقعه الحالي.',
        ),
        unsupportedBuilder: (_) => const _ViewerMessage(
          icon: Icons.description_outlined,
          title: 'تعذرت المعاينة',
          message: 'هذا الملف غير مدعوم بواسطة عارض Office على هذا الجهاز.',
        ),
      ),
    );
  }
}

class _TextViewer extends StatefulWidget {
  final String path;
  const _TextViewer({required this.path});
  @override
  State<_TextViewer> createState() => _TextViewerState();
}

class _TextViewerState extends State<_TextViewer> {
  late final Future<String> _content = _load();

  Future<String> _load() async {
    final file = File(widget.path);
    final length = await file.length();
    if (length > 8 * 1024 * 1024) {
      return 'الملف النصي أكبر من 8 MB، لذلك تم إيقاف المعاينة لحماية ذاكرة الهاتف.';
    }
    final bytes = await file.readAsBytes();
    return utf8.decode(bytes, allowMalformed: true);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<String>(
        future: _content,
        builder: (context, snap) {
          if (snap.hasError) {
            return _ViewerMessage(
              icon: Icons.error_outline_rounded,
              title: 'تعذرت قراءة الملف',
              message: '${snap.error}',
            );
          }
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          return SelectionArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: SizedBox(width: double.infinity, child: Text(snap.data!)),
            ),
          );
        },
      );
}

class _ViewerMessage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  const _ViewerMessage({required this.icon, required this.title, required this.message});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 54, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 14),
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(message, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
        ),
      );
}
