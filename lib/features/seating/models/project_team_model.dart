import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../core/utils/date_utils.dart';

/// 프로젝트 팀 (기수별). 인원 권장 4~5명.
class ProjectTeamModel {
  const ProjectTeamModel({
    required this.id,
    required this.name,
    this.memberIds = const [],
    this.sortOrder = 0,
    this.colorIndex = 0,
    this.updatedAt,
    this.updatedBy,
  });

  static const minMembers = 4;
  static const maxMembers = 5;

  final String id;
  final String name;
  final List<String> memberIds;
  final int sortOrder;
  final int colorIndex;
  final DateTime? updatedAt;
  final String? updatedBy;

  int get memberCount => memberIds.length;

  bool get isComplete =>
      memberCount >= minMembers && memberCount <= maxMembers;

  bool get isOverfull => memberCount > maxMembers;

  bool get isUnderfilled => memberCount > 0 && memberCount < minMembers;

  String get sizeLabel {
    if (memberCount == 0) return '비어 있음';
    if (isComplete) return '$memberCount명 · 구성 완료';
    if (isOverfull) return '$memberCount명 · ${maxMembers}명 초과';
    return '$memberCount명 · ${minMembers}명 이상 권장';
  }

  factory ProjectTeamModel.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? {};
    final rawMembers = data['memberIds'] as List? ?? [];
    return ProjectTeamModel(
      id: doc.id,
      name: data['name'] as String? ?? '',
      memberIds: rawMembers.map((e) => e.toString()).toList(),
      sortOrder: (data['sortOrder'] as num?)?.toInt() ?? 0,
      colorIndex: (data['colorIndex'] as num?)?.toInt() ?? 0,
      updatedAt: AppDateUtils.timestampToDateTime(data['updatedAt']),
      updatedBy: data['updatedBy'] as String?,
    );
  }

  Map<String, dynamic> toFirestore({
    required String updatedBy,
    bool isCreate = false,
  }) =>
      {
        'name': name,
        'memberIds': memberIds,
        'sortOrder': sortOrder,
        'colorIndex': colorIndex,
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': updatedBy,
        if (isCreate) 'createdAt': FieldValue.serverTimestamp(),
      };

  ProjectTeamModel copyWith({
    String? name,
    List<String>? memberIds,
    int? sortOrder,
    int? colorIndex,
  }) {
    return ProjectTeamModel(
      id: id,
      name: name ?? this.name,
      memberIds: memberIds ?? this.memberIds,
      sortOrder: sortOrder ?? this.sortOrder,
      colorIndex: colorIndex ?? this.colorIndex,
      updatedAt: updatedAt,
      updatedBy: updatedBy,
    );
  }
}

/// 팀 카드 악센트 팔레트
abstract final class ProjectTeamColors {
  static const _accents = <(Color, Color)>[
    (Color(0xFF0055FF), Color(0xFFE8F0FF)),
    (Color(0xFF0D9488), Color(0xFFCCFBF1)),
    (Color(0xFF7C3AED), Color(0xFFEDE9FE)),
    (Color(0xFFDB2777), Color(0xFFFCE7F3)),
    (Color(0xFFEA580C), Color(0xFFFFEDD5)),
    (Color(0xFF2563EB), Color(0xFFDBEAFE)),
    (Color(0xFF059669), Color(0xFFD1FAE5)),
    (Color(0xFFCA8A04), Color(0xFFFEF9C3)),
  ];

  static Color accentOf(int index) =>
      _accents[index.abs() % _accents.length].$1;

  static Color softOf(int index) =>
      _accents[index.abs() % _accents.length].$2;
}
