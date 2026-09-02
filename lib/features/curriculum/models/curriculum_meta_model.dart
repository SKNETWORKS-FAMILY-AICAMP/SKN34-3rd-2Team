import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/utils/date_utils.dart';

/// `cohorts/{cohortId}/curriculum/meta`
class CurriculumMetaModel {
  const CurriculumMetaModel({
    this.title = '',
    this.description = '',
    this.totalWeeks = 0,
    this.totalDays = 0,
    this.startDate,
    this.endDate,
    this.published = false,
    this.version = 1,
    this.fullPdfUrl,
    this.fullPdfFileName,
    this.updatedAt,
    this.updatedBy,
  });

  final String title;
  final String description;
  final int totalWeeks;
  final int totalDays;
  final DateTime? startDate;
  final DateTime? endDate;
  final bool published;
  final int version;
  final String? fullPdfUrl;
  final String? fullPdfFileName;
  final DateTime? updatedAt;
  final String? updatedBy;

  bool get hasFullPdf =>
      fullPdfUrl != null && fullPdfUrl!.trim().isNotEmpty;

  int get effectiveTotalDays => totalDays > 0 ? totalDays : totalWeeks;

  factory CurriculumMetaModel.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? {};
    return CurriculumMetaModel(
      title: data['title'] as String? ?? '',
      description: data['description'] as String? ?? '',
      totalWeeks: data['totalWeeks'] as int? ?? 0,
      totalDays: data['totalDays'] as int? ?? data['totalWeeks'] as int? ?? 0,
      startDate: AppDateUtils.timestampToDateTime(data['startDate']),
      endDate: AppDateUtils.timestampToDateTime(data['endDate']),
      published: data['published'] as bool? ?? false,
      version: data['version'] as int? ?? 1,
      fullPdfUrl: data['fullPdfUrl'] as String?,
      fullPdfFileName: data['fullPdfFileName'] as String?,
      updatedAt: AppDateUtils.timestampToDateTime(data['updatedAt']),
      updatedBy: data['updatedBy'] as String?,
    );
  }

  Map<String, dynamic> toFirestore({String? updatedBy}) => {
        'title': title,
        'description': description,
        'totalWeeks': totalWeeks,
        'totalDays': totalDays > 0 ? totalDays : totalWeeks,
        if (startDate != null) 'startDate': Timestamp.fromDate(startDate!),
        if (endDate != null) 'endDate': Timestamp.fromDate(endDate!),
        'published': published,
        'version': version,
        if (fullPdfUrl != null && fullPdfUrl!.isNotEmpty) 'fullPdfUrl': fullPdfUrl,
        if (fullPdfFileName != null && fullPdfFileName!.isNotEmpty)
          'fullPdfFileName': fullPdfFileName,
        'updatedAt': FieldValue.serverTimestamp(),
        if (updatedBy != null) 'updatedBy': updatedBy,
      };

  CurriculumMetaModel copyWith({
    String? title,
    String? description,
    int? totalWeeks,
    int? totalDays,
    DateTime? startDate,
    DateTime? endDate,
    bool? published,
    int? version,
    String? fullPdfUrl,
    String? fullPdfFileName,
    bool clearFullPdf = false,
  }) {
    return CurriculumMetaModel(
      title: title ?? this.title,
      description: description ?? this.description,
      totalWeeks: totalWeeks ?? this.totalWeeks,
      totalDays: totalDays ?? this.totalDays,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      published: published ?? this.published,
      version: version ?? this.version,
      fullPdfUrl: clearFullPdf ? null : (fullPdfUrl ?? this.fullPdfUrl),
      fullPdfFileName:
          clearFullPdf ? null : (fullPdfFileName ?? this.fullPdfFileName),
      updatedAt: updatedAt,
      updatedBy: updatedBy,
    );
  }
}
