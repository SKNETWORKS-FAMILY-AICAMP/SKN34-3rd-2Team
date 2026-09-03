class CurriculumAttachmentModel {
  const CurriculumAttachmentModel({
    required this.title,
    required this.fileUrl,
    required this.fileName,
    this.contentType = 'application/pdf',
  });

  final String title;
  final String fileUrl;
  final String fileName;
  final String contentType;

  factory CurriculumAttachmentModel.fromMap(Map<String, dynamic> map) {
    return CurriculumAttachmentModel(
      title: map['title'] as String? ?? '',
      fileUrl: map['fileUrl'] as String? ?? '',
      fileName: map['fileName'] as String? ?? '',
      contentType: map['contentType'] as String? ?? 'application/pdf',
    );
  }

  Map<String, dynamic> toMap() => {
        'title': title,
        'fileUrl': fileUrl,
        'fileName': fileName,
        'contentType': contentType,
      };
}
