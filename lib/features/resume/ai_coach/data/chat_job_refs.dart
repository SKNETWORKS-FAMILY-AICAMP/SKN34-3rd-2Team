/// "2번"이 가리킬 목록을 고르는 규칙.
///
/// 서버는 대화를 저장하지 않는다. 직전에 무엇을 보여 줬는지는 앱이 `last_job_ids`로
/// 되돌려 줘야 안다. 그러니 **무엇을 기억할지는 앱이 정한다.**
library;

/// 이번 답을 받은 뒤 번호가 가리킬 목록.
///
/// 번호는 **찾아 준 목록**을 가리킨다. 비교한 두 건이나 질문 답에 붙는 근거 공고는
/// 그 목록이 아니다.
///
/// 답에 공고가 들어 있다고 다 갈아치우던 때에는 이런 일이 있었다. 2번과 5번을
/// 비교하면 목록이 그 두 건으로 바뀌어, 이어서 "아까 1번 3번 중에서도 보고 싶어"라고
/// 하면 비교했던 두 건에서 골랐다. 사용자가 말한 1번과 3번은 화면을 올리면 그대로
/// 보이는데도 그랬다.
///
/// 검색이 0건이어도 앞 목록은 지킨다. 보여 준 것이 없으니 바꿀 것도 없다.
List<String> nextShownJobIds({
  required String mode,
  required List<String> jobsInAnswer,
  required List<String> previous,
}) =>
    mode == '검색' && jobsInAnswer.isNotEmpty ? jobsInAnswer : previous;
