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
    this.readFeedbackIds = const [],
    this.reviewerReadFeedbackIds = const [],
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

  /// 학생이 **전문을 열어 본** 피드백. 종을 열거나 배너를 닫는 것으로는 늘지 않는다.
  /// 목록만 훑고 지나간 것을 읽었다고 세면, 정작 읽어야 할 말이 숫자와 함께 사라진다.
  final List<String> readFeedbackIds;

  /// 검토자(강사·관리자)가 읽은 학생 답글. 검토자끼리는 나눠 읽는다 —
  /// 한 사람이 읽으면 다른 강사에게도 읽은 것으로 본다. 같은 일을 두 번 하지 않는다.
  final List<String> reviewerReadFeedbackIds;
  final int revisionCount;
  final DateTime? updatedAt;

  int get completedCount => sections.values.where((v) => v).length;
  int get totalCount => AppConstants.resumeSections.length;
  double get progress =>
      totalCount == 0 ? 0 : completedCount / totalCount;

  int get unreadFeedbackCount {
    // 예전에는 화면을 열기만 해도 lastSeenFeedbackCount 를 채워 두었다. 그 기록이 남은
    // 이력서가 갑자기 안 읽음으로 돌아가지 않도록 둘 중 큰 쪽을 읽은 것으로 본다.
    final read = lastSeenFeedbackCount > readFeedbackIds.length
        ? lastSeenFeedbackCount
        : readFeedbackIds.length;
    final unread = feedbackCount - read;
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
      readFeedbackIds:
          (data['readFeedbackIds'] as List?)?.cast<String>() ?? const [],
      reviewerReadFeedbackIds:
          (data['reviewerReadFeedbackIds'] as List?)?.cast<String>() ?? const [],
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
      'readFeedbackIds': readFeedbackIds,
      'reviewerReadFeedbackIds': reviewerReadFeedbackIds,
      'revisionCount': revisionCount,
      'updatedAt': FieldValue.serverTimestamp(),
      if (isCreate) 'createdAt': FieldValue.serverTimestamp(),
    };
  }

  String get statusLabel => switch (status) {
        'submitted' => '피드백 요청',
        'approved' || 'completed' => '승인 완료',
        _ => '작성 중',
      };

  /// 저장된 값은 'submitted' 그대로 둔다. 이미 쌓인 이력서를 옮기지 않으려는 것이고,
  /// 바뀐 것은 학생에게 보이는 이름뿐이다.
  bool get isSubmitted => status == 'submitted';
  bool get isApproved => status == 'approved' || status == 'completed';

  /// 학생이 피드백을 요청했나. 작성 중인 이력서는 아직 남의 눈에 보일 것이 아니다.
  bool get isFeedbackRequested => isSubmitted;

  /// 강사·관리자가 이 이력서를 볼 수 있나. 작성 중인 것은 목록에서 아예 뺀다.
  bool get isVisibleToReviewer => isFeedbackRequested || isApproved;

  /// 피드백을 남길 수 있나. 요청하지 않은 이력서에는 손대지 않는다.
  bool get acceptsFeedback => isFeedbackRequested;
  /// 승인된 뒤에도 학생은 고칠 수 있다. 승인은 "더는 손대지 말라"가 아니라
  /// "여기까지 봤다"는 표시다. 회사마다 이력서를 손보는 것이 정상이고, 잠가 두면
  /// 승인받은 이력서를 두고 새로 만들어야 한다.
  bool get canStudentEdit => true;

  ResumeModel copyWith({
    String? title,
    String? status,
    Map<String, bool>? sections,
    ResumeContent? content,
    int? feedbackCount,
    int? lastSeenFeedbackCount,
    List<String>? readFeedbackIds,
    List<String>? reviewerReadFeedbackIds,
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
      readFeedbackIds: readFeedbackIds ?? this.readFeedbackIds,
      reviewerReadFeedbackIds:
          reviewerReadFeedbackIds ?? this.reviewerReadFeedbackIds,
      revisionCount: revisionCount ?? this.revisionCount,
      updatedAt: updatedAt,
    );
  }
}
/// 안 읽은 피드백. **보는 사람에 따라 다르다.**
///
/// 학생은 남이 남긴 말을 읽어야 하고, 검토자는 학생이 단 답글을 읽어야 한다.
/// 내가 쓴 글이 나에게 안 읽음으로 잡히면 숫자가 영영 줄지 않는다.
///
/// 예전에는 화면을 열기만 해도 읽음으로 넘겼다(`lastSeenFeedbackCount`).
/// 그 기록이 남은 이력서가 갑자기 안 읽음으로 돌아가지 않도록, 목록이 그 수만큼
/// 있으면 이미 다 본 것으로 친다.
List<ResumeFeedbackModel> unreadFeedback(
  List<ResumeFeedbackModel> items,
  ResumeModel resume, {
  required bool asReviewer,
}) {
  if (!asReviewer &&
      resume.readFeedbackIds.isEmpty &&
      resume.lastSeenFeedbackCount >= items.length) {
    return const [];
  }
  final read = (asReviewer ? resume.reviewerReadFeedbackIds : resume.readFeedbackIds)
      .toSet();
  return [
    for (final item in items)
      if (item.isReplyOn(resume) == asReviewer && !read.contains(item.id)) item,
  ];
}

class ResumeFeedbackModel {
  const ResumeFeedbackModel({
    required this.id,
    required this.sectionKey,
    required this.content,
    required this.authorName,
    this.authorId = '',
    this.createdAt,
  });

  final String id;
  final String sectionKey;
  final String content;
  final String authorName;

  /// 누가 썼나. 이력서 주인이 쓴 것이면 답글이다.
  /// 내가 쓴 글은 나에게 안 읽음이 아니다 — 이 구분에 쓰인다.
  final String authorId;
  final DateTime? createdAt;

  /// 이력서 주인이 쓴 글인가. 그러면 검토자가 읽어야 할 답글이다.
  /// 글쓴이를 모르는 옛 기록은 검토자가 남긴 것으로 본다 — 그때는 답글이 없었다.
  bool isReplyOn(ResumeModel resume) =>
      authorId.isNotEmpty && authorId == resume.userId;

  factory ResumeFeedbackModel.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data()!;
    return ResumeFeedbackModel(
      id: doc.id,
      sectionKey: data['sectionKey'] as String? ?? '',
      content: data['content'] as String? ?? '',
      authorName: data['authorName'] as String? ?? '관리자',
      authorId: data['authorId'] as String? ?? '',
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
