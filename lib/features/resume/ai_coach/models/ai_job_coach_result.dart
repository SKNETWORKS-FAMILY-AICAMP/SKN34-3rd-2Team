class AiJobCoachResult {
  const AiJobCoachResult({
    required this.testMode,
    required this.notice,
    required this.recommendations,
    required this.selectedJob,
    required this.skillJudgements,
    required this.resumeFeedback,
    required this.learningRecommendations,
    required this.analysisId,
  });

  final bool testMode;
  final String notice;
  final List<JobRecommendation> recommendations;
  final SelectedJob? selectedJob;
  final List<SkillJudgement> skillJudgements;
  final List<String> resumeFeedback;
  final List<LearningRecommendation> learningRecommendations;
  final String analysisId;

  factory AiJobCoachResult.fromMap(Map<String, dynamic> map) {
    final skillAnalysis = _map(map['skillAnalysis']);
    return AiJobCoachResult(
      testMode: map['testMode'] as bool? ?? false,
      notice: map['recommendationNotice'] as String? ?? '',
      recommendations: _mapList(
        map['recommendations'],
      ).map(JobRecommendation.fromMap).toList(),
      selectedJob: map['selectedJob'] == null
          ? null
          : SelectedJob.fromMap(_map(map['selectedJob'])),
      skillJudgements: _mapList(
        skillAnalysis['judgements'],
      ).map(SkillJudgement.fromMap).toList(),
      resumeFeedback: _stringList(skillAnalysis['resumeFeedback']),
      learningRecommendations: _mapList(
        skillAnalysis['learningRecommendations'],
      ).map(LearningRecommendation.fromMap).toList(),
      analysisId: map['analysisId'] as String? ?? '',
    );
  }
}

class JobRecommendation {
  const JobRecommendation({
    required this.jobId,
    required this.source,
    required this.sourceUrl,
    required this.company,
    required this.title,
    required this.score,
    required this.grade,
    required this.hardFilterStatus,
    required this.unknownConditions,
    required this.evidence,
  });

  final String jobId;
  final String source;
  final String sourceUrl;
  final String company;
  final String title;
  final double score;
  final String grade;
  final String hardFilterStatus;
  final List<String> unknownConditions;
  final List<String> evidence;

  factory JobRecommendation.fromMap(Map<String, dynamic> map) {
    final hardFilter = _map(map['hardFilter']);
    final evidenceMap = _map(map['evidence']);
    return JobRecommendation(
      jobId: map['jobId'] as String? ?? '',
      source: map['source'] as String? ?? '',
      sourceUrl: map['sourceUrl'] as String? ?? '',
      company: map['company'] as String? ?? '',
      title: map['title'] as String? ?? '',
      score: (map['recommendationScore'] as num?)?.toDouble() ?? 0,
      grade: map['grade'] as String? ?? '낮음',
      hardFilterStatus: hardFilter['status'] as String? ?? '',
      unknownConditions: _stringList(hardFilter['unknown']),
      evidence: {
        ..._stringList(evidenceMap['roleTerms']),
        ..._stringList(evidenceMap['matchedSkills']),
        // 예전 응답 형식(필수/우대를 따로 채점하던 때)도 읽는다.
        ..._stringList(evidenceMap['requiredSkills']),
        ..._stringList(evidenceMap['preferredSkills']),
      }.toList(),
    );
  }
}

class SelectedJob {
  const SelectedJob({
    required this.jobId,
    required this.company,
    required this.title,
    required this.requiredSkills,
    required this.preferredSkills,
  });

  final String jobId;
  final String company;
  final String title;
  final List<String> requiredSkills;
  final List<String> preferredSkills;

  factory SelectedJob.fromMap(Map<String, dynamic> map) {
    return SelectedJob(
      jobId: map['jobId'] as String? ?? '',
      company: map['company'] as String? ?? '',
      title: map['title'] as String? ?? '',
      requiredSkills: _stringList(map['requiredSkills']),
      preferredSkills: _stringList(map['preferredSkills']),
    );
  }
}

class SkillJudgement {
  const SkillJudgement({
    required this.criterion,
    required this.requirementType,
    required this.judgement,
    required this.resumeEvidence,
    required this.jobEvidence,
    required this.confirmationQuestion,
  });

  final String criterion;
  final String requirementType;
  final String judgement;
  final List<String> resumeEvidence;
  final List<String> jobEvidence;
  final String? confirmationQuestion;

  factory SkillJudgement.fromMap(Map<String, dynamic> map) {
    return SkillJudgement(
      criterion: map['criterion'] as String? ?? '',
      requirementType: map['requirementType'] as String? ?? '',
      judgement: map['judgement'] as String? ?? '',
      resumeEvidence: _stringList(map['resumeEvidence']),
      jobEvidence: _stringList(map['jobEvidence']),
      confirmationQuestion: map['confirmationQuestion'] as String?,
    );
  }
}

class LearningRecommendation {
  const LearningRecommendation({
    required this.skill,
    required this.provider,
    required this.title,
    required this.url,
    required this.level,
    required this.estimatedDuration,
    required this.lastCheckedAt,
  });

  final String skill;
  final String provider;
  final String title;
  final String url;
  final String level;
  final String estimatedDuration;
  final String lastCheckedAt;

  factory LearningRecommendation.fromMap(Map<String, dynamic> map) {
    return LearningRecommendation(
      skill: map['skill'] as String? ?? '',
      provider: map['provider'] as String? ?? '',
      title: map['title'] as String? ?? '',
      url: map['url'] as String? ?? '',
      level: map['level'] as String? ?? '',
      estimatedDuration: map['estimatedDuration'] as String? ?? '',
      lastCheckedAt: map['lastCheckedAt'] as String? ?? '',
    );
  }
}

Map<String, dynamic> _map(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  return const {};
}

List<Map<String, dynamic>> _mapList(dynamic value) {
  if (value is! List) return const [];
  return value.map(_map).toList();
}

List<String> _stringList(dynamic value) {
  if (value is! List) return const [];
  return value.whereType<String>().toList();
}
