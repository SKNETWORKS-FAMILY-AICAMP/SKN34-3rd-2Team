import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/utils/date_utils.dart';
import 'curriculum_attachment_model.dart';
import 'curriculum_link_model.dart';
import 'curriculum_topic_model.dart';

/// `cohorts/{cohortId}/curriculumWeeks/{weekId}`
class CurriculumWeekModel {
  const CurriculumWeekModel({
    required this.id,
    required this.weekNumber,
    required this.title,
    this.summary = '',
    this.startDate,
    this.endDate,
    this.published = true,
    this.order = 0,
    this.topics = const [],
    this.links = const [],
    this.attachments = const [],
    this.updatedAt,
  });

  final String id;
  final int weekNumber;
  final String title;
  final String summary;
  final DateTime? startDate;
  final DateTime? endDate;
  final bool published;
  final int order;
  final List<CurriculumTopicModel> topics;
  final List<CurriculumLinkModel> links;
  final List<CurriculumAttachmentModel> attachments;
  final DateTime? updatedAt;

  bool containsDate(DateTime date) {
    if (startDate == null || endDate == null) return false;
    final d = DateTime(date.year, date.month, date.day);
    final s = DateTime(startDate!.year, startDate!.month, startDate!.day);
    final e = DateTime(endDate!.year, endDate!.month, endDate!.day);
    return !d.isBefore(s) && !d.isAfter(e);
  }

  factory CurriculumWeekModel.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? {};
    return CurriculumWeekModel(
      id: doc.id,
      weekNumber: data['weekNumber'] as int? ?? 0,
      title: data['title'] as String? ?? '',
      summary: data['summary'] as String? ?? '',
      startDate: AppDateUtils.timestampToDateTime(data['startDate']),
      endDate: AppDateUtils.timestampToDateTime(data['endDate']),
      published: data['published'] as bool? ?? true,
      order: data['order'] as int? ?? data['weekNumber'] as int? ?? 0,
      topics: (data['topics'] as List<dynamic>? ?? [])
          .map((e) => CurriculumTopicModel.fromMap(e as Map<String, dynamic>))
          .toList(),
      links: (data['links'] as List<dynamic>? ?? [])
          .map((e) => CurriculumLinkModel.fromMap(e as Map<String, dynamic>))
          .toList(),
      attachments: (data['attachments'] as List<dynamic>? ?? [])
          .map(
            (e) => CurriculumAttachmentModel.fromMap(e as Map<String, dynamic>),
          )
          .toList(),
      updatedAt: AppDateUtils.timestampToDateTime(data['updatedAt']),
    );
  }

  Map<String, dynamic> toFirestore() => {
        'weekNumber': weekNumber,
        'title': title,
        'summary': summary,
        if (startDate != null) 'startDate': Timestamp.fromDate(startDate!),
        if (endDate != null) 'endDate': Timestamp.fromDate(endDate!),
        'published': published,
        'order': order,
        'topics': topics.map((t) => t.toMap()).toList(),
        'links': links.map((l) => l.toMap()).toList(),
        'attachments': attachments.map((a) => a.toMap()).toList(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

  CurriculumWeekModel copyWith({
    int? weekNumber,
    String? title,
    String? summary,
    DateTime? startDate,
    DateTime? endDate,
    bool? published,
    int? order,
    List<CurriculumTopicModel>? topics,
    List<CurriculumLinkModel>? links,
    List<CurriculumAttachmentModel>? attachments,
  }) {
    return CurriculumWeekModel(
      id: id,
      weekNumber: weekNumber ?? this.weekNumber,
      title: title ?? this.title,
      summary: summary ?? this.summary,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      published: published ?? this.published,
      order: order ?? this.order,
      topics: topics ?? this.topics,
      links: links ?? this.links,
      attachments: attachments ?? this.attachments,
      updatedAt: updatedAt,
    );
  }
}
