import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/utils/date_utils.dart';

class NoticeModel {
  const NoticeModel({
    required this.id,
    required this.title,
    required this.content,
    required this.authorName,
    this.isFavorite = false,
    this.priority = 0,
    this.source,
    this.channelLabel,
    this.scheduledNoticeId,
    this.createdAt,
  });

  final String id;
  final String title;
  final String content;
  final String authorName;
  final bool isFavorite;
  final int priority;
  final String? source;
  final String? channelLabel;
  final String? scheduledNoticeId;
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
      isFavorite: data['isFavorite'] as bool? ??
          data['isPinned'] as bool? ??
          false,
      priority: data['priority'] as int? ?? 0,
      source: data['source'] as String?,
      channelLabel: data['channelLabel'] as String?,
      scheduledNoticeId: data['scheduledNoticeId'] as String?,
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
        'isFavorite': isFavorite,
        'priority': priority,
        if (source != null) 'source': source,
        if (channelLabel != null) 'channelLabel': channelLabel,
        if (scheduledNoticeId != null) 'scheduledNoticeId': scheduledNoticeId,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

  Map<String, dynamic> toFirestoreUpdate({
    String? authorId,
    String? authorName,
  }) =>
      {
        'title': title,
        'content': content,
        'isFavorite': isFavorite,
        if (authorId != null) 'authorId': authorId,
        if (authorName != null) 'authorName': authorName,
        'updatedAt': FieldValue.serverTimestamp(),
      };

  NoticeModel copyWith({
    String? id,
    String? title,
    String? content,
    String? authorName,
    bool? isFavorite,
    int? priority,
    String? source,
    String? channelLabel,
    String? scheduledNoticeId,
    DateTime? createdAt,
  }) {
    return NoticeModel(
      id: id ?? this.id,
      title: title ?? this.title,
      content: content ?? this.content,
      authorName: authorName ?? this.authorName,
      isFavorite: isFavorite ?? this.isFavorite,
      priority: priority ?? this.priority,
      source: source ?? this.source,
      channelLabel: channelLabel ?? this.channelLabel,
      scheduledNoticeId: scheduledNoticeId ?? this.scheduledNoticeId,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
