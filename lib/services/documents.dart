import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:xml/xml.dart';
import 'package:pdfrx/pdfrx.dart';

class DocumentText {
  static const _wordNs = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';
  static const _drawingNs = 'http://schemas.openxmlformats.org/drawingml/2006/main';

  static String fromBytes(Uint8List bytes, String extension) {
    switch (extension.toLowerCase()) {
      case 'txt':
      case 'md':
        return utf8.decode(bytes, allowMalformed: true);
      case 'docx':
        final zip = ZipDecoder().decodeBytes(bytes);
        final content = zip.findFile('word/document.xml')?.readBytes();
        if (content == null) throw const FormatException('Invalid DOCX file');
        final xml = XmlDocument.parse(utf8.decode(content, allowMalformed: true));
        return xml.findAllElements('p', namespaceUri: _wordNs).map((p) =>
          p.findAllElements('t', namespaceUri: _wordNs).map((t) => t.innerText).join(),
        ).where((line) => line.trim().isNotEmpty).join('\n');
      case 'pptx':
        final zip = ZipDecoder().decodeBytes(bytes);
        final slides = zip.files.where((f) => RegExp(r'^ppt/slides/slide\d+\.xml$').hasMatch(f.name)).toList();
        int number(String name) => int.tryParse(RegExp(r'slide(\d+)\.xml$').firstMatch(name)?.group(1) ?? '') ?? 0;
        slides.sort((a,b) => number(a.name).compareTo(number(b.name)));
        final buffer = StringBuffer();
        for (final slide in slides.take(100)) {
          final bytes = slide.readBytes();
          if (bytes == null) continue;
          final xml = XmlDocument.parse(utf8.decode(bytes, allowMalformed: true));
          buffer.writeln(xml.findAllElements('t', namespaceUri: _drawingNs).map((e) => e.innerText).where((t) => t.trim().isNotEmpty).join('\n'));
        }
        return buffer.toString();
      default:
        return '';
    }
  }

  static Future<String> pdfText(Uint8List bytes) async {
    await pdfrxFlutterInitialize();
    final pdf = await PdfDocument.openData(bytes);
    try {
      final output = StringBuffer();
      for (final page in pdf.pages.take(100)) {
        final text = await page.loadStructuredText(ensureLoaded: true);
        output.writeln(text.fullText);
      }
      return output.toString();
    } finally {
      await pdf.dispose();
    }
  }

  static Future<String> extract(Uint8List bytes, String ext) =>
    ext.toLowerCase() == 'pdf' ? pdfText(bytes) : Future.value(fromBytes(bytes, ext));

  static List<String> topics(String text, {int maxTopics = 120}) {
    final result = <String>[];
    final seen = <String>{};
    final heading = RegExp(
      r'^(?:#{1,5}\s+|(?:chapter|unit|lecture|lesson|topic|module|section)\s+\d+[.:\-\s]*|\d+(?:\.\d+)*[.)]\s+)',
      caseSensitive: false,
    );
    for (final original in text.split(RegExp(r'\r?\n'))) {
      final line = original.trim();
      if (line.length < 4 || line.length > 120 || !heading.hasMatch(line)) continue;
      final label = line.replaceFirst(RegExp(r'^#{1,5}\s+'), '').replaceAll(RegExp(r'\s+'), ' ').trim();
      if (label.length >= 4 && seen.add(label.toLowerCase())) result.add(label);
      if (result.length >= maxTopics) break;
    }
    return result;
  }
}
