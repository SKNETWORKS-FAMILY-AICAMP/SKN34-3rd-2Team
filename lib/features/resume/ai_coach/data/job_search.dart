import '../models/collected_job.dart';
import 'generated/collected_jobs.g.dart';
import 'text_match.dart';

/// 자연어 질문에서 뽑아낸 검색 조건.
///
/// 모델을 쓰지 않고 키워드만 본다. 사용자가 무엇으로 걸러졌는지 그대로
/// 보여줄 수 있어야 하기 때문이다.
class JobSearchQuery {
  const JobSearchQuery({
    required this.keywords,
    required this.entryLevelOnly,
    required this.regions,
  });

  final List<String> keywords;
  final bool entryLevelOnly;
  final List<String> regions;

  bool get isEmpty => keywords.isEmpty && !entryLevelOnly && regions.isEmpty;

  /// 어떤 조건으로 걸렀는지 사용자에게 그대로 보여주기 위한 요약.
  /// 검색 결과가 예상과 다를 때 무엇이 잘못 해석됐는지 알 수 있어야 한다.
  String get summary {
    final parts = <String>[
      if (keywords.isNotEmpty) '직무 ${keywords.join(', ')}',
      if (entryLevelOnly) '경력 신입',
      if (regions.isNotEmpty) '지역 ${regions.join(', ')}',
    ];
    return parts.isEmpty ? '조건 없음' : parts.join(' · ');
  }
}

class JobSearchResult {
  const JobSearchResult({required this.query, required this.jobs});

  final JobSearchQuery query;
  final List<CollectedJob> jobs;
}

/// 질문에서 걸러낼 조사·군더더기. 검색어로 쓰면 아무 공고나 걸린다.
const _stopWords = <String>[
  '채용공고',
  '공고',
  '채용',
  '찾아줘',
  '찾아',
  '알려줘',
  '추천',
  '있어',
  '있나요',
  '싶은데',
  '하고',
  '으로',
  '취업',
  '무슨',
  '어떤',
  '관련',
  '해줘',
  '주세요',
  '나한테',
  '맞는',
];

const _regionTokens = <String>[
  '서울',
  '경기',
  '인천',
  '대전',
  '대구',
  '부산',
  '광주',
  '울산',
  '세종',
  '강원',
  '충북',
  '충남',
  '전북',
  '전남',
  '경북',
  '경남',
  '제주',
];

const _entryLevelTokens = <String>['신입', '주니어', '경력무관', '초봉'];

JobSearchQuery parseJobSearchQuery(String input) {
  final lower = input.toLowerCase();
  final regions = _regionTokens.where(lower.contains).toList();
  final entryLevelOnly = _entryLevelTokens.any(lower.contains);

  // 이미 조건으로 해석한 말(지역·신입)과 군더더기는 직무 키워드에서 뺀다.
  // 남겨두면 "서울 신입"의 요약이 '직무 서울 · 지역 서울'처럼 중복된다.
  var cleaned = lower;
  for (final word in [..._stopWords, ..._entryLevelTokens, ...regions]) {
    cleaned = cleaned.replaceAll(word.toLowerCase(), ' ');
  }
  final keywords = cleaned
      .split(RegExp(r'[\s,./|·]+'))
      .map((token) => token.trim())
      .where((token) => token.length >= 2)
      .toSet()
      .toList();

  return JobSearchQuery(
    keywords: keywords,
    entryLevelOnly: entryLevelOnly,
    regions: regions,
  );
}

/// 수집된 IT 공고에서 조건에 맞는 공고를 찾는다.
///
/// 이력서와 무관하게 동작한다. 조건을 확인할 수 없는 공고는 제외하지 않고
/// 뒤로 밀어둔다. 명시되지 않은 것을 불일치로 단정하지 않기 위해서다.
JobSearchResult searchJobs(String input, {int limit = 5}) {
  final query = parseJobSearchQuery(input);
  final scored = <({CollectedJob job, int score})>[];

  for (final job in collectedJobs) {
    final text = job.searchText;

    if (query.regions.isNotEmpty &&
        !query.regions.any((region) => job.region.contains(region))) {
      continue;
    }
    // 신입 조건은 '경력직'이 확실한 공고만 제외한다. 미기재는 남긴다.
    if (query.entryLevelOnly && job.isEntryFriendly == false) continue;

    // 직무 키워드는 점수가 아니라 필터다. 키워드를 하나도 만족하지 못한 공고는
    // 신입·지역 조건이 맞더라도 내보내지 않는다. ("프론트엔드 신입"에
    // 백엔드 신입 공고가 섞여 나오던 원인)
    final hits = matchedTerms(text, query.keywords);
    if (query.keywords.isNotEmpty && hits.isEmpty) continue;

    // 조건만 준 질문(예: "서울 신입")은 키워드가 없어도 결과를 보여준다.
    var score = hits.length * 2;
    if (query.entryLevelOnly && job.isEntryFriendly == true) score += 1;
    if (query.regions.isNotEmpty) score += 1;
    scored.add((job: job, score: score));
  }

  scored.sort((a, b) => b.score.compareTo(a.score));
  return JobSearchResult(
    query: query,
    jobs: scored.take(limit).map((entry) => entry.job).toList(),
  );
}
