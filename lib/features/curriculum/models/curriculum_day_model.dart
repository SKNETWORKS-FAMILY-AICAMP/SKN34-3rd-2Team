import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/utils/date_utils.dart';
import 'curriculum_attachment_model.dart';
import 'curriculum_link_model.dart';

/// `cohorts/{cohortId}/curriculumDays/{dayId}`
class CurriculumDayModel {
  const CurriculumDayModel({
    required this.id,
    required this.dayNumber,
    required this.classDate,
    this.subject = '',
    this.content = '',
    this.published = true,
    this.order = 0,
    this.links = const [],
    this.attachments = const [],
    this.updatedAt,
  });

  final String id;
  final int dayNumber;
  final DateTime classDate;
  final String subject;
  final String content;
  final bool published;
  final int order;
  final List<CurriculumLinkModel> links;
  final List<CurriculumAttachmentModel> attachments;
  final DateTime? updatedAt;

  bool isOnDate(DateTime date) {
    final d = DateTime(date.year, date.month, date.day);
    final c = DateTime(classDate.year, classDate.month, classDate.day);
    return d == c;
  }

  factory CurriculumDayModel.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? {};
    return CurriculumDayModel(
      id: doc.id,
      dayNumber: data['dayNumber'] as int? ?? 0,
      classDate: AppDateUtils.timestampToDateTime(data['classDate']) ??
          DateTime.now(),
      subject: data['subject'] as String? ?? '',
      content: data['content'] as String? ?? '',
      published: data['published'] as bool? ?? true,
      order: data['order'] as int? ?? data['dayNumber'] as int? ?? 0,
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
        'dayNumber': dayNumber,
        'classDate': Timestamp.fromDate(classDate),
        'subject': subject,
        'content': content,
        'published': published,
        'order': order,
        'links': links.map((l) => l.toMap()).toList(),
        'attachments': attachments.map((a) => a.toMap()).toList(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

  CurriculumDayModel copyWith({
    int? dayNumber,
    DateTime? classDate,
    String? subject,
    String? content,
    bool? published,
    int? order,
    List<CurriculumLinkModel>? links,
    List<CurriculumAttachmentModel>? attachments,
  }) {
    return CurriculumDayModel(
      id: id,
      dayNumber: dayNumber ?? this.dayNumber,
      classDate: classDate ?? this.classDate,
      subject: subject ?? this.subject,
      content: content ?? this.content,
      published: published ?? this.published,
      order: order ?? this.order,
      links: links ?? this.links,
      attachments: attachments ?? this.attachments,
      updatedAt: updatedAt,
    );
  }
}
