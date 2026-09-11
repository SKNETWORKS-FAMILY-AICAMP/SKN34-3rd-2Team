import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/study_source_model.dart';

final studyNoteServiceProvider = Provider<StudyNoteService>((ref) {
  return StudyNoteService();
});

class StudyNoteService {
  StudyNoteService({FirebaseFunctions? functions})
      : _functions = functions ??
            FirebaseFunctions.instanceFor(region: 'asia-northeast3');

  final FirebaseFunctions _functions;

  Future<StudySourceTree> listTree({
    required String cohortId,
    required String sourceId,
  }) async {
    final result = await _functions
        .httpsCallable(
          'listStudySourceTree',
          options: HttpsCallableOptions(timeout: const Duration(seconds: 120)),
        )
        .call({'cohortId': cohortId, 'sourceId': sourceId});
    return StudySourceTree.fromMap(Map<String, dynamic>.from(result.data as Map));
  }

  Future<StudyNoteModel> generate({
    required String cohortId,
    required String sourceId,
    required String scopeType,
    required Object scopeValue,
  }) async {
    final result = await _functions
        .httpsCallable(
          'generateStudyNote',
          options: HttpsCallableOptions(timeout: const Duration(seconds: 540)),
        )
        .call({
      'cohortId': cohortId,
      'sourceId': sourceId,
      'scopeType': scopeType,
      'scopeValue': scopeValue,
    });
    return StudyNoteModel.fromCallable(Map<String, dynamic>.from(result.data as Map));
  }

  Future<StudyNoteModel> getNote({
    required String cohortId,
    String? noteId,
    String? sourceId,
    String? scopeType,
    Object? scopeValue,
  }) async {
    final result = await _functions
        .httpsCallable(
          'getStudyNote',
          options: HttpsCallableOptions(timeout: const Duration(seconds: 60)),
        )
        .call({
      'cohortId': cohortId,
      if (noteId != null) 'noteId': noteId,
      if (sourceId != null) 'sourceId': sourceId,
      if (scopeType != null) 'scopeType': scopeType,
      if (scopeValue != null) 'scopeValue': scopeValue,
    });
    return StudyNoteModel.fromCallable(Map<String, dynamic>.from(result.data as Map));
  }
}

class StudySourceTree {
  const StudySourceTree({
    required this.dates,
    required this.entries,
    required this.truncated,
  });

  final List<String> dates;
  final List<String> entries;
  final bool truncated;

  factory StudySourceTree.fromMap(Map<String, dynamic> data) {
    final rawDates = data['dates'] as List? ?? [];
    final rawEntries = data['entries'] as List? ?? [];
    return StudySourceTree(
      dates: rawDates.map((e) => e.toString()).toList(),
      entries: rawEntries
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e)['path']?.toString() ?? '')
          .where((path) => path.isNotEmpty)
          .toList(),
      truncated: data['truncated'] == true,
    );
  }

  List<String> folders() {
    final folders = <String>{};
    for (final path in entries) {
      final slash = path.lastIndexOf('/');
      if (slash > 0) folders.add(path.substring(0, slash));
    }
    return folders.toList()..sort();
  }

  List<String> filesUnder(String prefix) {
    final base = prefix.replaceAll(RegExp(r'/+$'), '');
    return entries
        .where((path) => path == base || path.startsWith('$base/'))
        .toList();
  }
}
