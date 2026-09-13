# LMS 사용자 온보딩 자료

## 결과물

| 파일 | 내용 |
|---|---|
| [output/PLAYDATA_LMS_사용자_가이드.pdf](output/PLAYDATA_LMS_사용자_가이드.pdf) | A4 안내서. 시작하기 → 학생·강사·관리자 화면 안내 → 자주 묻는 질문 |
| [output/videos/1_학생_시연.mp4](output/videos/1_학생_시연.mp4) | 로그인 → 이용 안내 투어 → 성취도평가 응시 → 기록실 → 마일리지 상점 → 마이페이지 |
| [output/videos/2_강사_시연.mp4](output/videos/2_강사_시연.mp4) | 로그인 → 투어 → 평가 만들기 → 커리큘럼 |
| [output/videos/3_관리자_시연.mp4](output/videos/3_관리자_시연.mp4) | 로그인 → 투어 → 기수·출석·마일리지 관리 |

모든 화면은 **데모 모드**(Firebase 없이 메모리의 예시 데이터)로 찍었다. 실제 Firestore를 읽지 않으므로 수강생 개인정보가 나오지 않는다.

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
