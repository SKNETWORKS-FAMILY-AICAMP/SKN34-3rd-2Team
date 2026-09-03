import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/curriculum_day_model.dart';

class CurriculumPdfParseResult {
  const CurriculumPdfParseResult({
    required this.days,
    required this.parsedCount,
  });

  final List<CurriculumDayModel> days;
  final int parsedCount;
}

/// Cloud Function — 커리큘럼 PDF 파싱
class CurriculumPdfParserService {
  CurriculumPdfParserService(this._functions);

  final FirebaseFunctions _functions;

  static const _maxParseBytes = 10 * 1024 * 1024;

  Future<CurriculumPdfParseResult> parsePdf(Uint8List bytes) async {
    if (bytes.length > _maxParseBytes) {
      throw StateError('PDF 파싱은 10MB 이하 파일만 지원합니다.');
    }

    final callable = _functions.httpsCallable(
      'parseCurriculumPdf',
      options: HttpsCallableOptions(timeout: const Duration(seconds: 120)),
    );

    final result = await callable.call<Map<String, dynamic>>({
      'pdfBase64': base64Encode(bytes),
    });

    final data = result.data;
    final rawDays = data['days'] as List<dynamic>? ?? [];
    final days = rawDays.map((raw) {
      final map = Map<String, dynamic>.from(raw as Map);
      final dateParts = (map['classDate'] as String).split('-');
      final classDate = DateTime(
        int.parse(dateParts[0]),
        int.parse(dateParts[1]),
        int.parse(dateParts[2]),
      );
      final dayNumber = map['dayNumber'] as int? ?? 0;
      return CurriculumDayModel(
        id: 'draft-$dayNumber',
        dayNumber: dayNumber,
        classDate: classDate,
        subject: map['subject'] as String? ?? '',
        content: map['content'] as String? ?? '',
        published: false,
        order: dayNumber,
      );
    }).toList();

    return CurriculumPdfParseResult(
      days: days,
      parsedCount: data['parsedCount'] as int? ?? days.length,
    );
  }
}

final curriculumPdfParserServiceProvider =
    Provider<CurriculumPdfParserService>((ref) {
  return CurriculumPdfParserService(
    FirebaseFunctions.instanceFor(region: 'asia-northeast3'),
  );
});
