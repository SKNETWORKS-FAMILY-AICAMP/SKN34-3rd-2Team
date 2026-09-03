import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/utils/date_utils.dart';

/// `cohorts/{cohortId}/curriculumProgress/{userId}`
class CurriculumProgressModel {
  const CurriculumProgressModel({
    this.completedWeekIds = const [],
    this.completedDayIds = const [],
    this.completedTopicIds = const [],
    this.lastViewedWeekId,
    this.lastViewedDayId,
    this.updatedAt,
  });

  final List<String> completedWeekIds;
  final List<String> completedDayIds;
  final List<String> completedTopicIds;
  final String? lastViewedWeekId;
  final String? lastViewedDayId;
  final DateTime? updatedAt;

  bool isWeekCompleted(String weekId) => completedWeekIds.contains(weekId);
  bool isDayCompleted(String dayId) => completedDayIds.contains(dayId);

  factory CurriculumProgressModel.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? {};
    return CurriculumProgressModel(
      completedWeekIds: (data['completedWeekIds'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      completedDayIds: (data['completedDayIds'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      completedTopicIds: (data['completedTopicIds'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      lastViewedWeekId: data['lastViewedWeekId'] as String?,
      lastViewedDayId: data['lastViewedDayId'] as String?,
      updatedAt: AppDateUtils.timestampToDateTime(data['updatedAt']),
    );
  }

  Map<String, dynamic> toFirestore() => {
        'completedWeekIds': completedWeekIds,
        'completedDayIds': completedDayIds,
        'completedTopicIds': completedTopicIds,
        if (lastViewedWeekId != null) 'lastViewedWeekId': lastViewedWeekId,
        if (lastViewedDayId != null) 'lastViewedDayId': lastViewedDayId,
        'updatedAt': FieldValue.serverTimestamp(),
      };

  CurriculumProgressModel copyWith({
    List<String>? completedWeekIds,
    List<String>? completedDayIds,
    List<String>? completedTopicIds,
    String? lastViewedWeekId,
    String? lastViewedDayId,
  }) {
    return CurriculumProgressModel(
      completedWeekIds: completedWeekIds ?? this.completedWeekIds,
      completedDayIds: completedDayIds ?? this.completedDayIds,
      completedTopicIds: completedTopicIds ?? this.completedTopicIds,
      lastViewedWeekId: lastViewedWeekId ?? this.lastViewedWeekId,
      lastViewedDayId: lastViewedDayId ?? this.lastViewedDayId,
      updatedAt: updatedAt,
    );
  }
}
