import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/utils/date_utils.dart';

class NoticeModel {
  const NoticeModel({
    required this.id,
    required this.title,
    required this.content,
    required this.authorName,
    this.isPinned = false,
    this.priority = 0,
    this.source,
    this.channelLabel,
    this.createdAt,
  });

  final String id;
  final String title;
  final String content;
  final String authorName;
  final bool isPinned;
  final int priority;
  final String? source;
  final String? channelLabel;
  final DateTime? createdAt;

  bool get isFromDiscord => source == 'discord';

  String get displayLabel => channelLabel ?? (isFromDiscord ? '디스코드' : '공지');

  factory NoticeModel.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    return NoticeModel(
      id: doc.id,
      title: data['title'] as String? ?? '',
      content: data['content'] as String? ?? '',
      authorName: data['authorName'] as String? ?? '',
      isPinned: data['isPinned'] as bool? ?? false,
      priority: data['priority'] as int? ?? 0,
      source: data['source'] as String?,
      channelLabel: data['channelLabel'] as String?,
      createdAt: AppDateUtils.timestampToDateTime(data['createdAt']),
    );
  }

  Map<String, dynamic> toFirestore({
    required String authorId,
    required String authorName,
  }) =>
      {
        'title': title,
        'content': content,
        'authorId': authorId,
        'authorName': authorName,
        'isPinned': isPinned,
        'priority': priority,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };
}
