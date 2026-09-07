/// 한글·영문이 섞인 채용공고 텍스트에서 키워드를 찾는 규칙.
///
/// 단순 `contains`를 쓰면 "ai"가 "maintain"·"email"에 걸리고, `\b` 경계를 쓰면
/// 한글도 단어 문자라 "REST API와"의 api를 놓친다. 그래서 영문 키워드는
/// 앞뒤가 ASCII 영숫자가 아닐 때만 인정한다.
///
/// 같은 규칙을 쓰는 곳:
/// - job_matching_bot/text_match.py
/// - functions/src/jobCoachScoring.ts
library;

final _asciiOnly = RegExp(r'^[\x20-\x7F]*$');

/// 키워드 하나를 정규식으로 만든다.
RegExp termPattern(String term) {
  final escaped = RegExp.escape(term.toLowerCase());
  final body = _asciiOnly.hasMatch(term)
      ? '(?<![a-z0-9])$escaped(?![a-z0-9])'
      : escaped;
  return RegExp(body, caseSensitive: false);
}

/// 텍스트에 키워드가 등장하는지.
bool matchesTerm(String text, String term) =>
    text.isNotEmpty && termPattern(term).hasMatch(text);

/// 텍스트에서 실제로 발견된 키워드만 돌려준다.
List<String> matchedTerms(String text, List<String> terms) {
  if (text.isEmpty) return const [];
  return terms.where((term) => matchesTerm(text, term)).toList();
}
