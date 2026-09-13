// PDF에 들어갈 화면 목록. 순서가 곧 PDF의 순서다.
// route: 이동할 hash 경로, id: 이미지 파일 이름, title/desc/tips: PDF 본문.
// 설명 문구는 앱 안 온보딩 투어(lib/features/onboarding/*_steps.dart)와 뜻을 맞춘다.

export const roles = [
  {
    role: 'student',
    label: '학생',
    intro: '출석 확인부터 이력서, 학습, 마일리지까지 수강 생활에 필요한 기능을 한곳에서 씁니다.',
    scenes: [
      {
        id: 'dashboard',
        route: '/',
        title: '대시보드',
        desc: '로그인하면 가장 먼저 보이는 홈입니다. 출석 캘린더, 시스템 공지, 이번 주 학습 추천, 설문·제출, 다가오는 자격 시험을 한 화면에서 확인합니다.',
        tips: [
          '오른쪽 위 「출결 폼」은 지각·조퇴 같은 예외 출결을 내는 구글 폼을 새 창으로 엽니다.',
          '캘린더 아래 색 점은 출석·지각·결석·공가·조퇴·외출을 뜻합니다.',
        ],
      },
      {
        id: 'resume',
        route: '/resume',
        title: '이력서 관리',
        desc: '이력서를 작성하고 강사·매니저에게 피드백을 요청합니다. 피드백이 오면 여기서 확인하고 답글을 남깁니다.',
        tips: ['이력서 편집 화면의 AI 코치로 문장 첨삭과 맞춤 공고 추천을 받을 수 있습니다.'],
      },
      {
        id: 'study-room',
        route: '/study-room',
        title: '학습실',
        desc: '배정된 인프런 강의 패키지와 이번 주 커리큘럼에 맞춘 YouTube 추천 영상을 확인합니다.',
      },
      {
        id: 'board',
        route: '/board',
        title: '게시판',
        desc: '중요 공지와 전체 공지, 소통 피드를 확인합니다.',
      },
      {
        id: 'seating',
        route: '/seating',
        title: '자리 배치',
        desc: '매니저가 게시한 좌석 배치에서 내 자리를 확인합니다.',
      },
      {
        id: 'forms',
        route: '/forms',
        title: '설문 · 제출',
        desc: '진행 중인 설문과 제출 과제를 확인하고 응답합니다. 마감일과 제출 여부가 함께 표시됩니다.',
      },
      {
        id: 'qual-exams',
        route: '/qual-exams',
        title: '자격 시험 일정',
        desc: '국가자격 시험의 접수·시험 일정을 확인합니다.',
      },
      {
        id: 'records',
        route: '/records',
        title: '기록실',
        desc: '자격증 취득, 스터디, 블로그 기록을 제출하고 승인 상태를 확인합니다. 승인되면 마일리지가 자동으로 적립됩니다.',
      },
      {
        id: 'records-create',
        route: '/records/create',
        title: '기록 제출하기',
        desc: '제출할 기록의 종류를 고르면 그에 맞는 입력 양식이 열립니다.',
      },
      {
        id: 'mileage',
        route: '/mileage',
        title: '마일리지',
        desc: '적립·사용 내역과 남은 포인트를 확인합니다.',
      },
      {
        id: 'mileage-shop',
        route: '/mileage/shop',
        title: '마일리지 상점',
        desc: '마일리지로 교환할 상품을 고르고 장바구니에 담아 구매를 요청합니다. 매니저가 승인하면 포인트가 차감됩니다.',
      },
      {
        id: 'assessments',
        route: '/assessments',
        title: '성취도평가',
        desc: '공개된 평가에 응시하고, 제출한 평가의 점수와 해설을 확인합니다.',
      },
      {
        id: 'my-page',
        route: '/my-page',
        title: '마이페이지',
        desc: '프로필 사진과 비밀번호를 관리합니다. 앱 이용 안내(온보딩 투어)도 여기서 다시 볼 수 있습니다.',
      },
    ],
  },
  {
    role: 'instructor',
    label: '강사',
    intro: '출석 확인, 이력서 피드백, 공지 작성, 성취도평가 출제와 채점을 합니다.',
    scenes: [
      {
        id: 'attendance',
        route: '/instructor',
        title: '자리 확인',
        desc: '날짜와 교시를 고르고, 호명한 학생이 자리에 있으면 「확인」, 없으면 「보류」를 누릅니다. 확인·보류 현황이 위에 요약됩니다.',
      },
      {
        id: 'resumes',
        route: '/instructor/resumes',
        title: '이력서 관리',
        desc: '학생이 피드백을 요청한 이력서를 열어 피드백을 남깁니다. 「피드백 요청」을 누르면 요청이 들어온 이력서만 추려 볼 수 있습니다.',
      },
      {
        id: 'board',
        route: '/instructor/board',
        title: '게시물 관리',
        desc: '공지를 등록하고 수정합니다. 「공지 작성」으로 새 공지를 올립니다.',
      },
      {
        id: 'assessments',
        route: '/instructor/assessments',
        title: '성취도평가',
        desc: '평가를 만들고 발행한 뒤, 제출된 답안을 채점합니다.',
      },
      {
        id: 'assessment-create',
        route: '/instructor/assessments/create',
        title: '평가 만들기',
        desc: '제목·기간·문항을 구성합니다. 커리큘럼을 등록해 두면 「커리큘럼 AI」로 일수 구간을 골라 객관식·단답 문항 초안을 만들 수 있습니다.',
      },
      {
        id: 'curriculum',
        route: '/instructor/curriculum',
        title: '커리큘럼',
        desc: '구글 시트를 CSV로 내려받아 「CSV 등록/교체」로 올립니다. 등록한 커리큘럼은 학습 추천과 평가 초안 생성에 쓰입니다.',
        tips: ['구글 시트 → 파일 → 다운로드 → 쉼표로 구분된 값(.csv)'],
      },
      {
        id: 'my-page',
        route: '/instructor/my-page',
        title: '마이페이지',
        desc: '프로필과 비밀번호를 관리하고, 이용 안내를 다시 볼 수 있습니다.',
      },
    ],
  },
  {
    role: 'admin',
    label: '관리자',
    intro: '기수·계정·출석·좌석·평가·게시판·마일리지 등 기수 운영 전반을 관리합니다.',
    scenes: [
      {
        id: 'dashboard',
        route: '/admin',
        title: '대시보드',
        desc: '기수 운영 현황을 한눈에 보는 관리자 홈입니다.',
      },
      {
        id: 'cohorts',
        route: '/admin/cohorts',
        title: '기수 관리',
        desc: '기수를 만들고 교육 기간과 설정을 관리합니다.',
      },
      {
        id: 'students',
        route: '/admin/students',
        title: '학생 관리',
        desc: '학생 계정을 등록·조회·수정합니다.',
      },
      {
        id: 'instructors',
        route: '/admin/instructors',
        title: '강사 관리',
        desc: '강사 계정을 등록하고 정보 수정과 비밀번호 재발급을 합니다.',
      },
      {
        id: 'attendance',
        route: '/admin/attendance',
        title: '출석 관리',
        desc: '기수별 당일 출석을 조회·수정하고 출결 폼 반영 여부를 확인합니다. 매일 08:30 출결 폼 공지도 여기서 등록합니다.',
      },
      {
        id: 'seat-presence',
        route: '/admin/seat-presence',
        title: '자리 확인',
        desc: '오늘 좌석에 앉은 학생을 확인하고 확인·보류를 남깁니다.',
      },
      {
        id: 'seating',
        route: '/admin/seating',
        title: '좌석 배치',
        desc: '좌석 레이아웃을 만들고 학생을 배정한 뒤 게시합니다. 게시하면 학생 화면의 「자리 배치」에 나타납니다.',
      },
      {
        id: 'assessments',
        route: '/admin/assessments',
        title: '성취도평가',
        desc: '강사가 만든 평가 목록과 발행 상태, 제출 현황을 확인합니다.',
      },
      {
        id: 'records',
        route: '/admin/records',
        title: '기록실',
        desc: '학생이 올린 자격증·스터디·블로그 기록을 승인하거나 반려합니다. 승인하면 설정한 규칙대로 마일리지가 적립됩니다.',
      },
      {
        id: 'resumes',
        route: '/admin/resumes',
        title: '이력서',
        desc: '피드백 요청이 들어온 이력서를 열어 피드백을 남기고 승인합니다.',
      },
      {
        id: 'form-tasks',
        route: '/admin/form-tasks',
        title: '설문 · 제출',
        desc: '구글 폼 설문을 등록하고 마감 일시와 제출 현황을 관리합니다.',
      },
      {
        id: 'study-room',
        route: '/admin/study-room',
        title: '학습실',
        desc: '인프런 강의 패키지를 등록하고 기수에 공개합니다.',
      },
      {
        id: 'board',
        route: '/admin/board',
        title: '게시판',
        desc: '공지, 예약 공지, 알림 팝업을 관리합니다.',
      },
      {
        id: 'mileage',
        route: '/admin/mileage',
        title: '마일리지',
        desc: '교환 상품, 구매 요청 승인·반려, 수동 지급·차감, 기수별 적립 규칙을 관리합니다.',
      },
      {
        id: 'ai-quality',
        route: '/admin/ai-quality',
        title: 'AI 품질',
        desc: 'AI 기능의 품질 지표와 로그를 점검하는 시스템 메뉴입니다.',
      },
    ],
  },
];
