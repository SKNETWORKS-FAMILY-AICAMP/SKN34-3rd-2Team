import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/constants/attendance_status.dart';
import '../../core/utils/date_utils.dart';

class AttendanceModel {
  const AttendanceModel({
    required this.id,
    required this.userId,
    required this.type,
    required this.dateKey,
    this.status,
    this.userDisplayName,
    this.timestamp,
  });

  final String id;
  final String userId;
  final String type; // legacy: checkIn, checkOut
  final String dateKey;
  final String? status;
  final String? userDisplayName;
  final DateTime? timestamp;

  String? get dayStatus =>
      AttendanceStatus.normalize(status, legacyType: type);

  String get typeLabel => dayStatus != null
      ? AttendanceStatus.labelOf(dayStatus)
      : (type == 'checkIn' ? '출석' : '퇴실');

  factory AttendanceModel.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data()!;
    return AttendanceModel(
      id: doc.id,
      userId: data['userId'] as String? ?? '',
      type: data['type'] as String? ?? 'checkIn',
      dateKey: data['dateKey'] as String? ?? '',
      status: data['status'] as String?,
      userDisplayName: data['userDisplayName'] as String?,
      timestamp: AppDateUtils.timestampToDateTime(data['timestamp']),
    );
  }

  Map<String, dynamic> toFirestore({
    required String userDisplayName,
    String? status,
  }) =>
      {
        'userId': userId,
        'userDisplayName': userDisplayName,
        if (type.isNotEmpty) 'type': type,
        'dateKey': dateKey,
        if (status != null) 'status': status,
        'timestamp': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
      };
}

class MileageTransactionModel {
  const MileageTransactionModel({
    required this.id,
    required this.userId,
    required this.amount,
    required this.reason,
    this.type,
    this.relatedId,
    this.adjustedBy,
    this.createdAt,
  });

  final String id;
  final String userId;
  final int amount;
  final String reason;
  final String? type;
  final String? relatedId;
  final String? adjustedBy;
  final DateTime? createdAt;

  factory MileageTransactionModel.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data()!;
    return MileageTransactionModel(
      id: doc.id,
      userId: data['userId'] as String? ?? '',
      amount: data['amount'] as int? ?? 0,
      reason: data['reason'] as String? ?? '',
      type: data['type'] as String?,
      relatedId: data['relatedId'] as String?,
      adjustedBy: data['adjustedBy'] as String?,
      createdAt: AppDateUtils.timestampToDateTime(data['createdAt']),
    );
  }
}

class ScheduleModel {
  const ScheduleModel({
    required this.dateKey,
    required this.sessions,
    this.currentSessionIndex = 0,
  });

  final String dateKey;
  final List<ScheduleSession> sessions;
  final int currentSessionIndex;

  factory ScheduleModel.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data()!;
    final rawSessions = data['sessions'] as List? ?? [];
    return ScheduleModel(
      dateKey: data['dateKey'] as String? ?? doc.id,
      sessions: rawSessions
          .map((s) => ScheduleSession.fromMap(s as Map<String, dynamic>))
          .toList(),
      currentSessionIndex: data['currentSessionIndex'] as int? ?? 0,
    );
  }
}

class ScheduleSession {
  const ScheduleSession({
    required this.title,
    required this.startTime,
    required this.endTime,
    this.instructor,
    this.isBreak = false,
  });

  final String title;
  final String startTime;
  final String endTime;
  final String? instructor;
  final bool isBreak;

  factory ScheduleSession.fromMap(Map<String, dynamic> map) {
    return ScheduleSession(
      title: map['title'] as String? ?? '',
      startTime: map['startTime'] as String? ?? '',
      endTime: map['endTime'] as String? ?? '',
      instructor: map['instructor'] as String?,
      isBreak: map['isBreak'] as bool? ?? false,
    );
  }
}

class MaterialModel {
  const MaterialModel({
    required this.id,
    required this.title,
    required this.fileUrl,
    required this.fileName,
    this.description,
    this.createdAt,
  });

  final String id;
  final String title;
  final String fileUrl;
  final String fileName;
  final String? description;
  final DateTime? createdAt;

  factory MaterialModel.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data()!;
    return MaterialModel(
      id: doc.id,
      title: data['title'] as String? ?? '',
      fileUrl: data['fileUrl'] as String? ?? '',
      fileName: data['fileName'] as String? ?? '',
      description: data['description'] as String?,
      createdAt: AppDateUtils.timestampToDateTime(data['createdAt']),
    );
  }
}

class AssignmentModel {
  const AssignmentModel({
    required this.id,
    required this.title,
    required this.description,
    required this.dueDate,
    this.submitted = false,
  });

  final String id;
  final String title;
  final String description;
  final DateTime dueDate;
  final bool submitted;

  factory AssignmentModel.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data()!;
    return AssignmentModel(
      id: doc.id,
      title: data['title'] as String? ?? '',
      description: data['description'] as String? ?? '',
      dueDate:
          AppDateUtils.timestampToDateTime(data['dueDate']) ?? DateTime.now(),
      submitted: data['submitted'] as bool? ?? false,
    );
  }
}
