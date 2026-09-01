import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/constants/app_constants.dart';
import '../../core/utils/date_utils.dart';
import 'resume_content.dart';
class WeeklyTaskModel {
  const WeeklyTaskModel({
    required this.id,
    required this.title,
    required this.dueDate,
    required this.totalCount,
  });

  final String id;
  final String title;
  final DateTime dueDate;
  final int totalCount;

  int get daysRemaining {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final due = DateTime(dueDate.year, dueDate.month, dueDate.day);
    return due.difference(today).inDays;
  }

  factory WeeklyTaskModel.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data()!;
    return WeeklyTaskModel(
      id: doc.id,
      title: data['title'] as String? ?? '',
      dueDate:
          AppDateUtils.timestampToDateTime(data['dueDate']) ?? DateTime.now(),
      totalCount: data['totalCount'] as int? ?? 0,
    );
  }
}

class UserProgressModel {
  const UserProgressModel({
    required this.userId,
    required this.completedCount,
    required this.totalCount,
  });

  final String userId;
  final int completedCount;
  final int totalCount;

  double get progressPercent =>
      totalCount == 0 ? 0 : (completedCount / totalCount) * 100;

  factory UserProgressModel.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data()!;
    return UserProgressModel(
      userId: doc.id,
      completedCount: data['completedCount'] as int? ?? 0,
      totalCount: data['totalCount'] as int? ?? 0,
    );
  }
}

class ResumeModel {
  const ResumeModel({
    required this.id,
    required this.userId,
    required this.title,
    required this.status,
    required this.sections,
    this.content = const ResumeContent(),
    this.feedbackCount = 0,
    this.lastSeenFeedbackCount = 0,
    this.revisionCount = 0,
    this.updatedAt,
  });

  final String id;
  final String userId;
  final String title;
  final String status;
  final Map<String, bool> sections;
  final ResumeContent content;
  final int feedbackCount;
  final int lastSeenFeedbackCount;
  final int revisionCount;
  final DateTime? updatedAt;

  int get completedCount => sections.values.where((v) => v).length;
  int get totalCount => AppConstants.resumeSections.length;
  double get progress =>
      totalCount == 0 ? 0 : completedCount / totalCount;

  int get unreadFeedbackCount {
    final unread = feedbackCount - lastSeenFeedbackCount;
    return unread < 0 ? 0 : unread;
  }

  bool get hasUnreadFeedback => unreadFeedbackCount > 0;

  factory ResumeModel.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    final rawSections = data['sections'] as Map<String, dynamic>? ?? {};
    final content = ResumeContent.fromMap(
      data['content'] as Map<String, dynamic>?,
    );
    final sections = rawSections.isNotEmpty
        ? rawSections.map((k, v) => MapEntry(k, v as bool? ?? false))
        : content.computeSections();
    return ResumeModel(
      id: doc.id,
      userId: data['userId'] as String? ?? '',
      title: data['title'] as String? ?? '새 이력서',
      status: data['status'] as String? ?? 'writing',
      sections: sections,
      content: content,
      feedbackCount: data['feedbackCount'] as int? ?? 0,
      lastSeenFeedbackCount: data['lastSeenFeedbackCount'] as int? ?? 0,
      revisionCount: data['revisionCount'] as int? ?? 0,
      updatedAt: AppDateUtils.timestampToDateTime(data['updatedAt']),
    );
  }

  Map<String, dynamic> toFirestore({bool isCreate = false}) {
    final computedSections = content.computeSections();
    return {
      'userId': userId,
      'title': title,
      'status': status,
      'sections': computedSections,
      'content': content.toMap(),
      'feedbackCount': feedbackCount,
      'lastSeenFeedbackCount': lastSeenFeedbackCount,
      'revisionCount': revisionCount,
      'updatedAt': FieldValue.serverTimestamp(),
      if (isCreate) 'createdAt': FieldValue.serverTimestamp(),
    };
  }

  String get statusLabel => switch (status) {
        'submitted' => '제출 요청',
        'approved' || 'completed' => '승인 완료',
        _ => '작성 중',
      };

  bool get isSubmitted => status == 'submitted';
  bool get isApproved => status == 'approved' || status == 'completed';
  bool get canStudentEdit => !isApproved;

  ResumeModel copyWith({
    String? title,
    String? status,
    Map<String, bool>? sections,
    ResumeContent? content,
    int? feedbackCount,
    int? lastSeenFeedbackCount,
    int? revisionCount,
  }) {
    return ResumeModel(
      id: id,
      userId: userId,
      title: title ?? this.title,
      status: status ?? this.status,
      sections: sections ?? this.sections,
      content: content ?? this.content,
      feedbackCount: feedbackCount ?? this.feedbackCount,
      lastSeenFeedbackCount: lastSeenFeedbackCount ?? this.lastSeenFeedbackCount,
      revisionCount: revisionCount ?? this.revisionCount,
      updatedAt: updatedAt,
    );
  }
}
class ResumeFeedbackModel {
  const ResumeFeedbackModel({
    required this.id,
    required this.sectionKey,
    required this.content,
    required this.authorName,
    this.createdAt,
  });

  final String id;
  final String sectionKey;
  final String content;
  final String authorName;
  final DateTime? createdAt;

  factory ResumeFeedbackModel.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data()!;
    return ResumeFeedbackModel(
      id: doc.id,
      sectionKey: data['sectionKey'] as String? ?? '',
      content: data['content'] as String? ?? '',
      authorName: data['authorName'] as String? ?? '관리자',
      createdAt: AppDateUtils.timestampToDateTime(data['createdAt']),
    );
  }

  Map<String, dynamic> toFirestore({
    required String authorId,
    required String authorName,
  }) =>
      {
        'sectionKey': sectionKey,
        'content': content,
        'authorId': authorId,
        'authorName': authorName,
        'createdAt': FieldValue.serverTimestamp(),
      };
}
