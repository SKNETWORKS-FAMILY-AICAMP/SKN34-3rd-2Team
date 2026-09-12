import 'package:flutter_test/flutter_test.dart';

import 'package:playdata_lms/features/resume/ai_coach/data/chat_job_refs.dart';

/// "2번"이 무엇을 가리키는가.
///
/// 서버는 대화를 저장하지 않으므로 앱이 목록을 되돌려 준다. 그 목록을 언제 갈아
/// 끼울지가 여기서 갈린다. 잘못 끼우면 답은 멀쩡해 보이는데 **다른 공고 이야기**를
/// 한다. 사용자가 알아채기 어렵다.
void main() {
  group('번호가 가리킬 목록', () {
    const shown = ['J1', 'J2', 'J3', 'J4', 'J5'];

    test('찾아 준 목록이 기준이 된다', () {
      expect(
        nextShownJobIds(mode: '검색', jobsInAnswer: shown, previous: const []),
        shown,
      );
    });

    test('비교한 두 건은 목록을 갈아치우지 않는다', () {
      // 2번과 5번을 비교한 뒤 "아까 1번 3번 중에서도 보고 싶어"가 걸리는 자리다.
      expect(
        nextShownJobIds(
          mode: '비교',
          jobsInAnswer: const ['J2', 'J5'],
          previous: shown,
        ),
        shown,
      );
    });

    test('질문 답에 붙는 근거 공고도 목록이 아니다', () {
      // 근거는 "이 숫자를 센 공고들"이지 고르라고 보여 준 목록이 아니다.
      expect(
        nextShownJobIds(
          mode: '질문',
          jobsInAnswer: const ['J9', 'J8', 'J7'],
          previous: shown,
        ),
        shown,
      );
    });

    test('공고 하나에 답한 턴도 그대로 둔다', () {
      expect(
        nextShownJobIds(mode: '공고', jobsInAnswer: const ['J2'], previous: shown),
        shown,
      );
    });

    test('0건인 검색은 앞 목록을 지운다고 볼 이유가 없다', () {
      expect(
        nextShownJobIds(mode: '검색', jobsInAnswer: const [], previous: shown),
        shown,
      );
    });

    test('새로 찾으면 그때는 갈아치운다', () {
      expect(
        nextShownJobIds(
          mode: '검색',
          jobsInAnswer: const ['K1', 'K2'],
          previous: shown,
        ),
        const ['K1', 'K2'],
      );
    });
  });
}
