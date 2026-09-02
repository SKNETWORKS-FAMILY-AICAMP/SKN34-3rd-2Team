class CurriculumTopicModel {
  const CurriculumTopicModel({
    required this.id,
    required this.title,
    this.description = '',
    this.tags = const [],
  });

  final String id;
  final String title;
  final String description;
  final List<String> tags;

  factory CurriculumTopicModel.fromMap(Map<String, dynamic> map) {
    return CurriculumTopicModel(
      id: map['id'] as String? ?? '',
      title: map['title'] as String? ?? '',
      description: map['description'] as String? ?? '',
      tags: (map['tags'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'description': description,
        'tags': tags,
      };

  CurriculumTopicModel copyWith({
    String? id,
    String? title,
    String? description,
    List<String>? tags,
  }) {
    return CurriculumTopicModel(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      tags: tags ?? this.tags,
    );
  }
}
