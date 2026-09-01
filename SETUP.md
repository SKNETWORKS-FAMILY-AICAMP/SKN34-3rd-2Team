# PLAYDATA All-in-One LMS — 팀원 실행 가이드

Flutter + Firebase 기반 LMS입니다.  
**Firebase 설정 파일은 저장소에 포함**되어 있어, 클론 후 바로 앱을 실행할 수 있습니다.

---

## 빠른 시작 (5분)

```powershell
# 1. 저장소 클론 (develop 브랜치)
git clone <저장소 URL>
cd SKN34-3rd-2Team
git checkout develop

# 2. Flutter 패키지 설치
flutter pub get

# 3. Chrome에서 실행
flutter run -d chrome
```

로그인 계정이 없다면 → 아래 [계정 시드](#계정-시드-최초-1회) 참고.

---

## 사전 준비 (설치 목록)

| 도구 | 버전 | 확인 명령 |
|------|------|-----------|
| **Flutter** | SDK `^3.12` | `flutter --version` |
| **Chrome** | 최신 | 웹 실행용 |
| **Git** | 최신 | `git --version` |
| **Node.js** | 20.x | `node --version` (Functions/시드 스크립트용) |
| **Firebase CLI** | 최신 | `firebase --version` (시드·배포용) |

### Flutter 설치가 안 되어 있다면

1. https://docs.flutter.dev/get-started/install/windows
2. 설치 후 `flutter doctor` 실행 → 경고 없는지 확인

### Firebase CLI 설치

```powershell
npm install -g firebase-tools
firebase login
```

> Firebase 프로젝트(`skn34-3rd-2team`)에 **팀원 계정이 초대**되어 있어야 시드·배포가 가능합니다.  
> 초대가 안 되어 있으면 팀 리더에게 요청하세요.

---

## 프로젝트 정보

| 항목 | 값 |
|------|-----|
| Firebase Project ID | `skn34-3rd-2team` |
| 기본 기수 ID | `cohort_34` |
| 지원 플랫폼 | **Web (Chrome)**, Android, Windows |
| 작업 브랜치 | `develop` (`main`은 배포용, 직접 푸시 금지) |

---

## 앱 실행

### Web (권장 — 개발 시)

```powershell
flutter run -d chrome
```

실행 중 단축키:
- `r` — Hot reload
- `R` — Hot restart
- `q` — 종료

### Android

```powershell
flutter devices          # 연결된 기기 확인
flutter run -d <deviceId>
```

### Windows 데스크톱

```powershell
flutter run -d windows
```

---

## 로그인 계정

시드 실행 후 아래 계정으로 로그인합니다.

| 역할 | 이메일 | 비밀번호 |
|------|--------|----------|
| 관리자 | `admin@playdata.co.kr` | `Playdata123!` |
| 학생 | `student@playdata.co.kr` | `Playdata123!` |

> 최초 로그인 시 비밀번호 변경 화면이 나올 수 있습니다.

---

## 계정 시드 (최초 1회)

Firebase에 테스트 계정이 **아직 없을 때** 한 번만 실행합니다.

### 사전 조건

Firebase Console에서 아래를 먼저 켜야 합니다.

1. **Authentication → 이메일/비밀번호** 사용 설정  
   https://console.firebase.google.com/project/skn34-3rd-2team/authentication/providers

2. **Firestore** 데이터베이스 생성 (이미 되어 있으면 생략)

3. **Storage** 시작하기 (파일 업로드 기능용, 선택)  
   https://console.firebase.google.com/project/skn34-3rd-2team/storage

### 시드 실행

```powershell
cd scripts
npm install
cd ..
.\scripts\run-seed.ps1
```

스크립트가 자동으로:
1. 임시 Firestore Rules 배포
2. 관리자·학생 계정 + 기수 데이터 생성
3. Production Rules 복원·재배포

완료 후 `flutter run -d chrome`으로 로그인하세요.

---

## Functions 로컬 개발 (선택)

Cloud Functions 코드를 수정할 때만 필요합니다.

```powershell
cd functions
npm install
npm run build
cd ..
```

### 환경 변수 설정

```powershell
copy functions\.env.example functions\.env
# functions\.env 에서 DISCORD_COHORT_ID 등 수정
```

> `.env` 파일은 Git에 올라가지 않습니다. 팀 리더에게 값을 받으세요.

### Functions 배포 (Blaze 플랜 필요)

```powershell
cd functions
npm run build
cd ..
firebase deploy --only functions
```

---

## 자주 겪는 문제

### `flutter pub get` 실패

```powershell
flutter clean
flutter pub get
```

### Chrome 디버그 연결 끊김 (`Cannot find context with specified id`)

1. 터미널에서 `q`로 종료
2. Chrome localhost 탭 전부 닫기
3. `flutter run -d chrome` 다시 실행

### 로그인 안 됨 / `user-not-found`

→ [계정 시드](#계정-시드-최초-1회)를 아직 안 했을 가능성이 큽니다.

### Firebase 권한 오류 (`permission-denied`)

- Firebase Console에서 본인 계정이 프로젝트 멤버인지 확인
- 시드 후에도 안 되면 `firebase login` 다시 실행

### `flutterfire configure` 해야 하나요?

**아니요.** `lib/firebase_options.dart`와 `android/app/google-services.json`이 이미 저장소에 있습니다.  
새 플랫폼(iOS 등)을 추가할 때만 필요합니다.

---

## Git 작업 규칙

| 항목 | 규칙 |
|------|------|
| 작업 브랜치 | `develop` |
| 커밋 메시지 | `S32-XX) 작업 설명` (Jira 이슈 키 + 설명) |
| `main` 브랜치 | 직접 푸시하지 않음 |

```powershell
git checkout develop
git pull origin develop
# 작업 후
git add .
git commit -m "S32-XX) 작업 설명"
git push origin develop
```

---

## 선택 기능 (나중에 필요할 때)

<details>
<summary><b>Discord 공지 연동</b></summary>

디스코드 `#매니저-공지사항`, `#캠퍼스-질문주세요` 채널 글을 5분마다 Firestore `notices`에 동기화합니다.

### 1. Bot Token Secret 등록

```powershell
firebase functions:secrets:set DISCORD_BOT_TOKEN
```

### 2. 기수 ID 설정

`functions/.env.example` → `functions/.env` 복사 후:

```
DISCORD_COHORT_ID=cohort_34
```

### 3. 배포

```powershell
cd functions
npm run build
cd ..
firebase deploy --only functions:syncDiscordNotices,functions:syncDiscordNoticesNow
```

### 채널 매핑

| 채널 | ID | 라벨 |
|------|-----|------|
| #매니저-공지사항 | 1505777394886246501 | 매니저 공지 |
| #캠퍼스-질문주세요 | 1505777394886246502 | 캠퍼스 Q&A |

</details>

<details>
<summary><b>구글폼 설문 연동</b></summary>

구글폼 제출을 LMS에 자동 반영합니다.

### 1. Webhook Secret 등록

```powershell
firebase functions:secrets:set GOOGLE_FORM_WEBHOOK_SECRET
```

### 2. 배포

```powershell
firebase deploy --only functions:googleFormWebhook
```

Webhook URL:
`https://asia-northeast3-skn34-3rd-2team.cloudfunctions.net/googleFormWebhook`

### 3. LMS에서 설문 등록

1. 관리자 로그인 → **설문 · 제출**
2. **설문 등록** → 제목, 구글폼 URL, 마감일 입력
3. 상세 화면에서 `cohortId`, `taskId` 확인 → **Apps Script 코드 복사**

### 4. Google Apps Script 연결

1. 구글폼 → ⋮ → **스크립트 편집기**
2. `scripts/google-form-webhook.gs` 내용 붙여넣기
3. `WEBHOOK_SECRET`, `COHORT_ID`, `TASK_ID` 수정
4. **트리거** → `onFormSubmit` → **폼 제출 시**

> 구글폼에 **이메일 수집**을 켜거나, "이메일" 질문을 추가해야 학생 매칭이 됩니다.

</details>

<details>
<summary><b>국가자격 시험일정 API</b></summary>

`functions/.env`에 공공데이터포털 인증키 설정:

```
DATA_GO_KR_SERVICE_KEY=발급받은_키
```

</details>

---

## 프로젝트 구조 (참고)

```
SKN34-3rd-2Team/
├── lib/              # Flutter 앱 소스
├── functions/        # Firebase Cloud Functions (TypeScript)
├── scripts/          # 시드·설정 스크립트
├── android/          # Android 빌드
├── ios/              # iOS 빌드
├── web/              # Web 빌드
├── firebase.json     # Firebase 설정
├── firestore.rules   # Firestore 보안 규칙
└── storage.rules     # Storage 보안 규칙
```

---

## 도움이 필요할 때

1. 이 문서의 [자주 겪는 문제](#자주-겪는-문제) 확인
2. 팀 Jira 이슈에 `S32-XX` 키로 질문 등록
3. Firebase Console 로그 확인: https://console.firebase.google.com/project/skn34-3rd-2team
