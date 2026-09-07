import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'curriculum_youtube_models.dart';

final curriculumYoutubeServiceProvider = Provider<CurriculumYoutubeService>((ref) {
  return CurriculumYoutubeService();
});

class CurriculumYoutubeService {
  CurriculumYoutubeService({FirebaseFunctions? functions})
      : _functions = functions ??
            FirebaseFunctions.instanceFor(region: 'asia-northeast3');

  final FirebaseFunctions _functions;

  Future<CurriculumYoutubeRecommendations> fetch({
    required String cohortId,
  }) async {
    final result = await _functions
        .httpsCallable(
          'getCurriculumYoutubeRecommendations',
          options: HttpsCallableOptions(timeout: const Duration(seconds: 60)),
        )
        .call({'cohortId': cohortId});

    final data = Map<String, dynamic>.from(result.data as Map);
    return CurriculumYoutubeRecommendations.fromMap(data);
  }
}
