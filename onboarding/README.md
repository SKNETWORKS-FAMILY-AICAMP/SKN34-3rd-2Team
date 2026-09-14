# LMS 사용자 온보딩 자료

## 결과물

| 파일 | 내용 |
|---|---|
| [output/PLAYDATA_LMS_사용자_가이드.pdf](output/PLAYDATA_LMS_사용자_가이드.pdf) | A4 안내서. 시작하기(화면 설정·테마 비교 포함) → 학생·강사·관리자 화면 안내 → 자주 묻는 질문 |
| [output/videos/1_학생_시연.mp4](output/videos/1_학생_시연.mp4) | 로그인 → 이용 안내 투어 → 대시보드 → 이력서 작성 → 기록실 블로그 제출 → 성취도평가 결과 → 게시판 소통 피드 → 학습실 → 마일리지 상점 → 마이페이지·화면 설정 |
| [output/videos/2_강사_시연.mp4](output/videos/2_강사_시연.mp4) | 로그인 → 투어 → 자리 확인(확인·보류) → 이력서 피드백 → 공지 작성 → 채점 확인 → 평가 만들기(문제 생성 AI 범위 설정·수동 문항 추가) → 커리큘럼 |
| [output/videos/3_관리자_시연.mp4](output/videos/3_관리자_시연.mp4) | 로그인 → 투어 → 대시보드 → 기록실 승인 → 이력서 피드백 → 공지 작성 → 출석 관리 → 설문·제출 → 마일리지 상품 → 기수 관리 |

모든 화면은 **데모 모드**(Firebase 없이 메모리의 예시 데이터)로 찍었다. 실제 Firestore를 읽지 않으므로 수강생 개인정보가 나오지 않는다.

영상 자막은 앱 화면을 가리지 않도록 화면 아래 자막 바(1440×1000 중 아래 100px)에 입힌다. 왼쪽에 역할, 가운데에 지금 하는 일, 오른쪽에 단계 번호가 나오고, 자막은 다음 자막이 나올 때까지 유지된다.

데모 모드에서 AI 초안 만들기와 좌석 강의실 만들기는 실제 서버를 불러 실패하므로 영상에서 누르지 않는다.

## 다시 만들기

### 준비 (최초 1회)

```powershell
cd onboarding
npm install
npx playwright install chromium
```

영상을 mp4로 바꾸려면 `ffmpeg`가 PATH에 있어야 한다.

### 실행

```powershell
cd onboarding
npm run build:web   # 데모 모드 웹 빌드 → build/onboarding_web
npm run capture     # 화면 캡처 → build/onboarding/shots/
npm run pdf         # PDF → onboarding/output/
npm run record      # 영상 → onboarding/output/videos/
```

한 역할만 다시 찍으려면 `node capture.mjs student`, `node record.mjs admin` 처럼 역할을 붙인다.

## 고칠 곳

| 바꾸고 싶은 것 | 파일 |
|---|---|
| PDF에 넣을 화면, 제목·설명 문구 | `scenes.mjs` |
| 표지·시작하기·FAQ·디자인 | `pdf.mjs` |
| 영상 시나리오와 자막 | `record.mjs` |
| 로그인·이동 같은 공통 동작 | `lib/app.mjs` |
| 예시 데이터 | `lib/shared/demo/demo_lms_repository.dart` (앱 코드) |

- 설명 문구는 앱 안 이용 안내 투어(`lib/features/onboarding/*_steps.dart`)와 뜻을 맞춘다.
- 버튼 이름이 헷갈리면 `node probe.mjs student /board` 로 그 화면의 접근성 라벨 목록을 본다.
- 새 화면이 데모 모드에서 로딩에 멈추면, 그 provider가 Firestore를 바로 읽고 있는 것이다. `DemoConfig.enabled`일 때 빈 값을 돌려주게 한다.
