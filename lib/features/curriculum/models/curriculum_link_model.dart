/// 커리큘럼 주차 연결 리소스 유형
enum CurriculumLinkType {
  inflearnPackage('inflearnPackage', '학습실 패키지'),
  formTask('formTask', '설문 · 제출'),
  weeklyTask('weeklyTask', '주간 필수 학습'),
  schedule('schedule', '시간표'),
  external('external', '외부 링크'),
  recordType('recordType', '기록실');

  const CurriculumLinkType(this.value, this.label);
  final String value;
  final String label;

  static CurriculumLinkType fromString(String? raw) {
    return CurriculumLinkType.values.firstWhere(
      (t) => t.value == raw,
      orElse: () => CurriculumLinkType.external,
    );
  }
}

class CurriculumLinkModel {
  const CurriculumLinkModel({
    required this.type,
    required this.label,
    this.refId,
    this.url,
  });

  final CurriculumLinkType type;
  final String label;
  final String? refId;
  final String? url;

  factory CurriculumLinkModel.fromMap(Map<String, dynamic> map) {
    return CurriculumLinkModel(
      type: CurriculumLinkType.fromString(map['type'] as String?),
      label: map['label'] as String? ?? '',
      refId: map['refId'] as String?,
      url: map['url'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
        'type': type.value,
        'label': label,
        if (refId != null && refId!.isNotEmpty) 'refId': refId,
        if (url != null && url!.isNotEmpty) 'url': url,
      };

  CurriculumLinkModel copyWith({
    CurriculumLinkType? type,
    String? label,
    String? refId,
    String? url,
  }) {
    return CurriculumLinkModel(
      type: type ?? this.type,
      label: label ?? this.label,
      refId: refId ?? this.refId,
      url: url ?? this.url,
    );
  }
}
