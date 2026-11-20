import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:study_pulse_mobile/services/documents.dart';

void main(){
  test('Reads UTF8 TXT and detects headings without duplicates',(){
    final sample='Chapter 1 Introduction\nparagraph\n## Stacks\n## Stacks\n2. Queues';
    final text=DocumentText.fromBytes(Uint8List.fromList(utf8.encode(sample)),'txt');
    final topics=DocumentText.topics(text);
    expect(topics.contains('Chapter 1 Introduction'),true);
    expect(topics.contains('Stacks'),true);
    expect(topics.contains('2. Queues'),true);
    expect(topics.length,3);
  });
}
