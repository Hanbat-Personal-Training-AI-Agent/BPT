# 📌 BPT (Kori) 백엔드 변경 사항 & API 연동 가이드

> **🌐 개발 서버 Swagger UI 주소:**  
> http://151.145.79.106:8080/api/v1/swagger-ui/index.html  
> *(인증이 필요한 API는 우측 상단 `[Authorize]` 버튼에 로그인 시 발급받은 Access Token을 입력하여 직접 테스트할 수 있습니다.)*  
>  
> - **Base URL**: `http://151.145.79.106:8080/api/v1` (배포 서버)  
> - **인증 헤더**: `Authorization: Bearer <accessToken>`  
> - **최종 갱신일**: 2026년 10월 15일  

---

## 1. 진행 상황 체크리스트

### 🟢 백엔드 완료 사항 (Done)

- [x] **회원가입 약관 단일화**: `privacyAgreed` 제거, `termsAgreed: true` 단일 필수 필드로 통합 완료
- [x] **프로필 수정 확장 (`PUT /users/me`)**: 아이디(`username`) 및 이메일(`email`) 수정 허용, 타 회원과 중복 시 `409 Conflict` 방어, `marketingConsent` 동의 여부 수정 반영
- [x] **프로필 조회 확장 (`GET /users/me`)**: 응답 DTO에 온보딩 목표 주간 운동 횟수(`weeklyFrequency`), 마케팅 동의(`marketingConsent`, `marketingConsentAt`) 필드 추가
- [x] **온보딩 간소화 (`PUT /users/me/onboarding`)**: `notificationTime` 삭제, 응답에서 BMI 자동 계산 필드(`bmi`, `bmiStatus`) 제거 (온보딩 완료 플래그만 반환)
- [x] **체형 측정일 분리 (`POST /users/me/body-scans`)**: 온보딩 시 `lastBodyScanDate`가 자동 갱신되지 않도록 수정하고, 4방향 체형 촬영 완료 시 명시적으로 오늘 날짜로 갱신하는 전용 API 구축
- [x] **User 엔티티 변경**: `phoneNumber`, `birthDate`, `lastBodyScanDate`, `notificationTime`, `marketingConsent`, `marketingConsentAt` 컬럼 추가
- [x] **기본 회원가입 (`POST /auth/signup`)**: `phoneNumber`(010-XXXX-XXXX), `birthDate`(YYYY-MM-DD) 유효성 검증 정규식 적용
- [x] **아이디 전용 로그인 (`POST /auth/login`)**: 이메일뿐만 아니라 사용자 아이디(`username`) 단독으로도 로그인 가능하도록 지원
- [x] **토큰 갱신 API (`POST /auth/refresh`)**: 리프레시 토큰(14일 유효) 기반 신규 Access Token 및 Refresh Token 재발급 구현
- [x] **실제 이메일 발송 연동 (SMTP)**: Mock 대신 `spring-boot-starter-mail`을 연동하여 6자리 실제 인증번호 발송 구현
- [x] **이메일 비동기 발송 (@Async)**: 이메일 전송 지연으로 인한 API 응답 지연(3~5초)을 제거하여 즉시 응답 반환 처리
- [x] **인증번호 보안 정책 강화**:
  - 인증번호 5분 유효시간 적용
  - 5회 이상 오입력 시 해당 인증번호 폐기 (`400 TOO_MANY_VERIFICATION_ATTEMPTS`)
  - 무차별 요청 방지를 위한 1분 재발송 간격 제한 (`429 RESEND_COOLDOWN_ACTIVE`)
  - 서버 로그에 평문 인증번호 미노출 처리
- [x] **이메일 인증 확인 (`POST /auth/verify-email/confirm`)**: 인증 성공 시 계정 찾기/비밀번호 변경용 1회용 `verificationToken`(10분 유효) 발급
- [x] **아이디 찾기 API (`POST /auth/find-username`)**: 이메일 인증 완료 토큰(`verificationToken`)을 기반으로 마스킹 아이디(`ji***`) 및 원본 아이디 반환
- [x] **비밀번호 재설정 인증번호 발송 전 아이디-이메일 일치 검증 (`POST /auth/verify-email/request`)**: `purpose: RESET_PASSWORD`와 `username` 전달 시 동일 계정 여부를 사전에 검증하여 불일치 시 `404 USER_NOT_FOUND` 반환
- [x] **비밀번호 재설정 API (`POST /auth/reset-password`)**: 이메일 인증 완료 후 1회용 `verificationToken`을 검증하여 안전하게 비밀번호 재설정 처리
- [x] **회원 탈퇴 API (`DELETE /users/me`)**: 계정 및 연관된 모든 운동 기록, 체형 데이터를 영구 Cascade 삭제 처리
- [x] **5개 운동 종목 마스터 등록 (`GET /exercises`)**: 푸쉬업, 스쿼트, 바벨로우, 벤치프레스, 데드리프트 등록 및 앱 식별자(`appExerciseId`: `pushup`, `squat`, `barbell-row`, `benchpress`, `deadlift`) 매핑
- [x] **운동 세션 기록 구조 개선 (`POST /workouts/records`)**:
  - `postureScore` 제거, 기기 로컬 영상 경로 `videoLocalPath` 텍스트 저장
  - 순수 운동 시간(`durationSeconds`) 필드 적용
  - 세트별 `sets`, `reps`, `weightKg` 저장
  - 피드백 항목별 발생 횟수(`feedbackCounts`: Map 형태) 저장/조회 지원
- [x] **리포트 분석 및 통계 API (`GET /workouts/reports/analysis`)**: 주간/월별 총 볼륨, 완료 세트/반복수, 운동 종목별 비중(도넛 차트), 자주 발생한 자세 피드백 TOP 3 통계 제공
- [x] **홈 대시보드 API (`GET /users/me/dashboard`)**: `lastBodyScanDate` 기준 30일 경과 시 체형 재측정 알림 플래그(`needsBodyScan: true`) 반환
- [x] **서버 환경 보안 분리**: DB 접속정보, 메일 앱 비밀번호, JWT 시크릿을 `application-secret.yml`로 격리하고 `.gitignore` 등록
- [x] **오라클 클라우드 배포 및 Swagger 동기화**: OCI 프리티어 최적화 배포 (`-Xmx512m`) 및 Swagger UI 실시간 업데이트 완료

---

### 🟡 백엔드 향후 작업 예정 (To-Do)

- [ ] **클라우드 영상 스토리지 연동**: 현재 로컬 경로(`videoLocalPath`) 저장에서 향후 OCI Object Storage / AWS S3 업로드 파이프라인 연계
- [ ] **FCM 백그라운드 푸시 알림 스케줄러**: 30일 주기 체형 재측정 알림 및 주간 운동 독려 FCM 푸시 발송 배치 구축
- [ ] **브랜치 PR 및 머지**: `feat/detail-check` 브랜치 최종 검증 후 `develop`/`main` 브랜치 병합

---

### 🔵 프론트엔드(Flutter) 작업 체크리스트

- [x] **회원가입 화면 (`SignUpScreen`)**:
  - [x] `phoneNumber` 입력란 추가 (010-XXXX-XXXX 정규식 검증)
  - [x] `birthDate` 입력란 추가 (YYYY-MM-DD 형식 검증)
  - [x] 약관 동의 체크박스 단일화 (`termsAgreed: true` 전달)
- [x] **로그인 화면 (`LoginScreen`)**:
  - [x] 아이디 입력란 `@` 필수 검사 제거 (영문 아이디 및 이메일 모두 허용)
- [x] **내 프로필 화면 (`ProfileEditScreen`)**:
  - [x] 아이디(`username`) 및 이메일(`email`) 수정 필드 반영
  - [x] 중복 에러(`409 Conflict`) 시 사용자 안내 토스트/팝업 연동
- [x] **온보딩 화면 (`OnboardingScreen`)**:
  - [x] `gender`, `heightCm`, `weightKg`, `workoutGoal`, `weeklyFrequency` 전송
  - [x] 응답에서 BMI 계산 필드 제거에 따른 UI 플로우 정리
- [ ] **아이디/비밀번호 찾기 화면 (`AccountRecoveryScreen`)**:
  - [x] 서비스 인터페이스(`auth_service.dart`) 최신화 완료
  - [ ] **아이디 찾기**: `POST /auth/verify-email/request` (purpose: `FIND_USERNAME`) → `confirm`으로 `verificationToken` 획득 → `POST /auth/find-username` 호출하여 마스킹된 아이디 표시
  - [ ] **비밀번호 재설정**: `POST /auth/verify-email/request` 호출 시 `purpose: RESET_PASSWORD`, `username`을 함께 전달하여 404 발생 시 "가입된 정보와 일치하지 않습니다" 안내 → `confirm` 후 `POST /auth/reset-password`로 새 비밀번호 저장
- [ ] **체형 측정 완료 처리 (`BodyScanScreen`)**:
  - [ ] 4방향 체형 촬영 및 판정 완료 시 `POST /api/v1/users/me/body-scans` 호출하여 `lastBodyScanDate` 갱신
- [ ] **운동 결과 화면 & 전송 로직 (`WorkoutResultScreen`)**:
  - [ ] 기기 로컬 영상 저장 경로를 `videoLocalPath`로 전달
  - [ ] 휴식 시간을 제외한 순수 운동 진행 시간을 초 단위(`durationSeconds`)로 계산하여 전달
  - [ ] 자세 피드백 발생 카운트를 `feedbackCounts` 맵 형태로 전달 (예: `{"골반경사": 3, "무릎모임": 1}`)
- [ ] **홈 대시보드 (`HomeScreen`)**:
  - [ ] `GET /users/me/dashboard`의 `needsBodyScan == true`일 때 30일 주기 체형 재측정 배너 노출
- [ ] **리포트 화면 (`ReportScreen`)**:
  - [ ] `GET /workouts/reports/analysis?period=weekly|monthly`를 호출하여 5대 종목 도넛 차트 및 볼륨, 취약 피드백 TOP 3 표출
- [ ] **설정 화면 (`SettingsScreen`)**:
  - [ ] 회원 탈퇴 버튼 클릭 시 `DELETE /api/v1/users/me` 연동 및 로컬 토큰 삭제 후 로그인 화면으로 이동

---

## 2. API 상세 명세서

### [그룹 1] Auth (인증 / 회원관리)

| No | API명 | HTTP Method | Endpoint | 인증 필요 | 주요 설명 |
|:---:|:---|:---:|:---|:---:|:---|
| 1 | **로그인** | `POST` | `/api/v1/auth/login` | ❌ | 아이디(`username`) 또는 이메일과 비밀번호로 로그인, Access/Refresh Token 발급 |
| 2 | **기본 회원가입** | `POST` | `/api/v1/auth/signup` | ❌ | 아이디, 이메일, 비밀번호, 전화번호, 생년월일, 단일 약관 동의(`termsAgreed`) |
| 3 | **아이디 중복 확인** | `GET` | `/api/v1/auth/check-username` | ❌ | `?username=jihoon123` 사용 가능 여부 실시간 조회 |
| 4 | **이메일 인증번호 발송** | `POST` | `/api/v1/auth/verify-email/request` | ❌ | 6자리 난수 메일 비동기 발송, 1분 재발송 쿨다운, **비밀번호 재설정 시 아이디 사전 검증** |
| 5 | **이메일 인증번호 확인** | `POST` | `/api/v1/auth/verify-email/confirm` | ❌ | 5회 오입력 폐기, 성공 시 10분 유효 일회용 `verificationToken` 발급 |
| 6 | **토큰 갱신** | `POST` | `/api/v1/auth/refresh` | ❌ | Refresh Token(14일)으로 신규 Access Token 및 Refresh Token 발급 |
| 7 | **아이디 찾기** | `POST` | `/api/v1/auth/find-username` | ❌ | `verificationToken` 기반 마스킹(`ji***`) 및 원본 아이디 조회 |
| 8 | **비밀번호 재설정** | `POST` | `/api/v1/auth/reset-password` | ❌ | `verificationToken` + 아이디 + 새 비밀번호로 안전하게 재설정 |

---

#### 1) 로그인 (`POST /api/v1/auth/login`)
- **Request Body:**
```json
{
  "username": "jihoon_kim",
  "password": "password123!"
}
```
- **Response Body (200 OK):**
```json
{
  "token": "eyJhbGciOiJIUzUxMiJ9...",
  "accessToken": "eyJhbGciOiJIUzUxMiJ9...",
  "refreshToken": "eyJhbGciOiJIUzUxMiJ9...",
  "tokenType": "Bearer",
  "expiresIn": 3600,
  "user": {
    "id": "1",
    "username": "jihoon_kim",
    "name": "김지훈",
    "email": "jihoon@bpt.app",
    "phoneNumber": "010-1234-5678",
    "birthDate": "1998-05-15",
    "gender": "MALE",
    "heightCm": 178.5,
    "weightKg": 74.0,
    "workoutGoal": "근력 증량",
    "weeklyFrequency": 4,
    "lastBodyScanDate": "2026-10-12",
    "marketingConsent": false
  }
}
```

---

#### 2) 기본 회원가입 (`POST /api/v1/auth/signup`)
- **Request Body:**
```json
{
  "username": "jihoon_kim",
  "email": "jihoon@bpt.app",
  "password": "password123!",
  "name": "김지훈",
  "phoneNumber": "010-1234-5678",
  "birthDate": "1998-05-15",
  "termsAgreed": true
}
```
- **Response Body (201 Created):**
```json
{
  "accessToken": "eyJhbGciOiJIUzUxMiJ9...",
  "refreshToken": "eyJhbGciOiJIUzUxMiJ9...",
  "tokenType": "Bearer",
  "expiresIn": 3600,
  "user": {
    "id": "1",
    "username": "jihoon_kim",
    "email": "jihoon@bpt.app",
    "name": "김지훈",
    "phoneNumber": "010-1234-5678",
    "birthDate": "1998-05-15"
  }
}
```

---

#### 3) 아이디 중복 확인 (`GET /api/v1/auth/check-username?username={username}`)
- **Response Body (200 OK):**
```json
{
  "available": true,
  "message": "사용 가능한 아이디입니다."
}
```

---

#### 4) 이메일 인증번호 발송 요청 (`POST /api/v1/auth/verify-email/request`)
- **설명**: 
  - 6자리 인증번호 비동기 발송 (유효시간: 5분, 재발송 쿨다운: 1분)
  - `purpose`: `"SIGN_UP"`, `"FIND_ACCOUNT"`, `"FIND_USERNAME"`, `"RESET_PASSWORD"`
  - **비밀번호 재설정 시**: `purpose: RESET_PASSWORD`와 `username`을 전달하면, 아이디가 존재하고 등록된 이메일과 일치할 때만 발송하며 불일치 시 `404 USER_NOT_FOUND`를 반환합니다.
- **Request Body (비밀번호 재설정 시):**
```json
{
  "email": "jihoon@bpt.app",
  "purpose": "RESET_PASSWORD",
  "username": "jihoon_kim"
}
```
- **Response Body (200 OK):**
```json
{
  "success": true,
  "message": "인증번호가 이메일로 발송되었습니다. (5분 내 입력)"
}
```
- **Error Response (404 Not Found - 계정 불일치 또는 없는 아이디):**
```json
{
  "success": false,
  "error": {
    "code": "USER_NOT_FOUND",
    "message": "사용자를 찾을 수 없습니다."
  }
}
```

---

#### 5) 이메일 인증번호 확인 (`POST /api/v1/auth/verify-email/confirm`)
- **설명**: 6자리 번호 검증. 5회 틀릴 시 번호 자동 폐기. 성공 시 10분 유효 일회용 `verificationToken` 발급.
- **Request Body:**
```json
{
  "email": "jihoon@bpt.app",
  "code": "418320"
}
```
- **Response Body (200 OK):**
```json
{
  "verified": true,
  "success": true,
  "verificationToken": "vt_c0ca4d413517427a",
  "message": "이메일 인증이 완료되었습니다."
}
```

---

#### 6) 토큰 갱신 (`POST /api/v1/auth/refresh`)
- **Request Body:**
```json
{
  "refreshToken": "eyJhbGciOiJIUzUxMiJ9..."
}
```
- **Response Body (200 OK):**
```json
{
  "accessToken": "eyJhbGciOiJIUzUxMiJ9...",
  "refreshToken": "eyJhbGciOiJIUzUxMiJ9...",
  "tokenType": "Bearer",
  "expiresIn": 3600,
  "user": {
    "id": "1",
    "username": "jihoon_kim",
    "email": "jihoon@bpt.app"
  }
}
```

---

#### 7) 아이디 찾기 (`POST /api/v1/auth/find-username`)
- **Request Body:**
```json
{
  "verificationToken": "vt_c0ca4d413517427a"
}
```
- **Response Body (200 OK):**
```json
{
  "success": true,
  "username": "jihoon_kim",
  "maskedUsername": "jih*******",
  "message": "아이디 조회가 완료되었습니다."
}
```

---

#### 8) 비밀번호 재설정 (`POST /api/v1/auth/reset-password`)
- **Request Body:**
```json
{
  "username": "jihoon_kim",
  "email": "jihoon@bpt.app",
  "verificationToken": "vt_c0ca4d413517427a",
  "newPassword": "newPassword456!"
}
```
- **Response Body (200 OK):**
```json
{
  "success": true,
  "message": "비밀번호가 변경되었습니다."
}
```

---

### [그룹 2] User & Onboarding (온보딩 및 프로필)

| No | API명 | HTTP Method | Endpoint | 인증 필요 | 주요 설명 |
|:---:|:---|:---:|:---|:---:|:---|
| 9 | **온보딩 정보 등록** | `PUT` | `/api/v1/users/me/onboarding` | 🔒 Bearer | 신체스펙, 주간목표(`weeklyFrequency`), 목표 등록 |
| 10 | **내 프로필 조회** | `GET` | `/api/v1/users/me` | 🔒 Bearer | 프로필 전체 및 마케팅 동의, 측정일 포함 |
| 11 | **내 프로필 수정** | `PUT` | `/api/v1/users/me` | 🔒 Bearer | 아이디, 이메일 변경 가능 (중복 시 409 반환) |
| 12 | **체형 측정일 갱신** | `POST` | `/api/v1/users/me/body-scans` | 🔒 Bearer | 4장 촬영 완료 후 `lastBodyScanDate` 오늘로 갱신 |
| 13 | **홈 대시보드 요약** | `GET` | `/api/v1/users/me/dashboard` | 🔒 Bearer | 주간 목표 달성도, 오늘 운동 요약, 30일 경과 알림 |
| 14 | **회원 탈퇴** | `DELETE` | `/api/v1/users/me` | 🔒 Bearer | 계정 및 모든 운동 데이터 영구 삭제 |

---

#### 1) 온보딩 정보 등록 (`PUT /api/v1/users/me/onboarding`)
- **Request Body:**
```json
{
  "gender": "MALE",
  "heightCm": 178.5,
  "weightKg": 74.0,
  "workoutGoal": "근력 증량",
  "weeklyFrequency": 4
}
```
- **Response Body (200 OK):**
```json
{
  "userId": 1,
  "isOnboardingCompleted": true
}
```

---

#### 2) 내 프로필 조회 (`GET /api/v1/users/me`)
- **Response Body (200 OK):**
```json
{
  "id": "1",
  "username": "jihoon_kim",
  "name": "김지훈",
  "email": "jihoon@bpt.app",
  "avatarInitials": "김",
  "phoneNumber": "010-1234-5678",
  "birthDate": "1998-05-15",
  "gender": "MALE",
  "heightCm": 178.5,
  "weightKg": 74.0,
  "workoutGoal": "근력 증량",
  "weeklyFrequency": 4,
  "notificationTime": "18:00",
  "notificationEnabled": true,
  "lastBodyScanDate": "2026-10-15",
  "totalWorkouts": 12,
  "streakDays": 3,
  "joinedAt": "2026-09-30T16:30:00",
  "marketingConsent": false,
  "marketingConsentAt": null
}
```

---

#### 3) 내 프로필 수정 (`PUT /api/v1/users/me`)
- **Request Body:**
```json
{
  "username": "new_jihoon",
  "email": "new_jihoon@bpt.app",
  "name": "김지훈",
  "phoneNumber": "010-9876-5432",
  "gender": "MALE",
  "birthDate": "1998-05-15",
  "heightCm": 180.0,
  "weightKg": 75.0,
  "workoutGoal": "체형 교정",
  "weeklyFrequency": 5,
  "marketingConsent": true
}
```
- **Response Body (200 OK):**
```json
{
  "id": "1",
  "username": "new_jihoon",
  "email": "new_jihoon@bpt.app",
  "name": "김지훈",
  "phoneNumber": "010-9876-5432",
  "weeklyFrequency": 5,
  "marketingConsent": true,
  "marketingConsentAt": "2026-10-15T14:00:00"
}
```

---

#### 4) 체형 측정일 갱신 (`POST /api/v1/users/me/body-scans`)
- **Request Body (선택, 빈 객체 전송 시 오늘 날짜로 자동 갱신):**
```json
{
  "bodyScanDate": "2026-10-15"
}
```
- **Response Body (200 OK):**
```json
{
  "userId": 1,
  "lastBodyScanDate": "2026-10-15",
  "message": "체형 측정일이 성공적으로 기록되었습니다."
}
```

---

#### 5) 홈 대시보드 요약 (`GET /api/v1/users/me/dashboard`)
- **Response Body (200 OK):**
```json
{
  "userName": "김지훈",
  "date": "2026-10-15",
  "achievementRate": 75.0,
  "todayWorkoutMinutes": 42,
  "todayCompletedSets": 4,
  "todayTotalReps": 45,
  "weeklyGoalCount": 4,
  "weeklyCompletedCount": 3,
  "weeklyActiveDays": ["MON", "WED", "FRI"],
  "needsBodyScan": true,
  "daysSinceLastScan": 31,
  "recentWorkouts": [
    {
      "exerciseName": "스쿼트",
      "weightKg": 60.0,
      "sets": 3,
      "reps": 12,
      "relativeTime": "오늘"
    }
  ]
}
```

---

#### 6) 회원 탈퇴 (`DELETE /api/v1/users/me`)
- **Response Body (200 OK):**
```json
{
  "success": true,
  "message": "회원 탈퇴 및 모든 데이터 삭제가 정상적으로 처리되었습니다."
}
```

---

### [그룹 3] Exercise (운동 종목 마스터)

| No | API명 | HTTP Method | Endpoint | 인증 필요 | 주요 설명 |
|:---:|:---|:---:|:---|:---:|:---|
| 15 | **운동 종목 목록 조회** | `GET` | `/api/v1/exercises` | ❌ | 전체 5개 종목(푸쉬업, 스쿼트, 바벨로우, 벤치프레스, 데드리프트) 및 앱 식별자(`appExerciseId`) 제공 |
| 16 | **운동 종목 가이드 조회** | `GET` | `/api/v1/exercises/{exerciseId}` | ❌ | 특정 종목 가이드 노트, 표준 ROM 범위 조회 |

---

#### 1) 운동 종목 목록 조회 (`GET /api/v1/exercises`)
- **Response Body (200 OK):**
```json
[
  {
    "id": 1,
    "exerciseCode": "SQUAT",
    "exerciseName": "스쿼트",
    "category": "LEGS",
    "standardRomMin": 80.00,
    "standardRomMax": 110.00,
    "appExerciseId": "squat"
  },
  {
    "id": 2,
    "exerciseCode": "BENCH_PRESS",
    "exerciseName": "벤치프레스",
    "category": "CHEST",
    "standardRomMin": 75.00,
    "standardRomMax": 95.00,
    "appExerciseId": "benchpress"
  },
  {
    "id": 3,
    "exerciseCode": "DEADLIFT",
    "exerciseName": "데드리프트",
    "category": "BACK",
    "standardRomMin": 60.00,
    "standardRomMax": 100.00,
    "appExerciseId": "deadlift"
  },
  {
    "id": 4,
    "exerciseCode": "PUSH_UP",
    "exerciseName": "푸쉬업",
    "category": "CHEST",
    "standardRomMin": 70.00,
    "standardRomMax": 90.00,
    "appExerciseId": "pushup"
  },
  {
    "id": 5,
    "exerciseCode": "BARBELL_ROW",
    "exerciseName": "바벨로우",
    "category": "BACK",
    "standardRomMin": 60.00,
    "standardRomMax": 100.00,
    "appExerciseId": "barbell-row"
  }
]
```

---

### [그룹 4] Workouts (운동 기록 및 캘린더)

| No | API명 | HTTP Method | Endpoint | 인증 필요 | 주요 설명 |
|:---:|:---|:---:|:---|:---:|:---|
| 17 | **운동 세션 기록 저장** | `POST` | `/api/v1/workouts/records` | 🔒 Bearer | `videoLocalPath`, 순수 운동 시간(`durationSeconds`), `feedbackCounts` 저장 |
| 18 | **오프라인 동기화** | `POST` | `/api/v1/workouts/records/sync` | 🔒 Bearer | `clientRecordId` 기준 멱등성 보장 벌크 동기화 |
| 19 | **전체 운동 기록 목록** | `GET` | `/api/v1/workouts/records` | 🔒 Bearer | 최신순 운동 기록 전체 페이징/목록 조회 |
| 20 | **월별 운동 캘린더** | `GET` | `/api/v1/workouts/calendar` | 🔒 Bearer | `?year=2026&month=10` 월별 일자별 운동 요약 |

---

#### 1) 운동 세션 기록 저장 (`POST /api/v1/workouts/records`)
- **Request Body:**
```json
{
  "clientRecordId": "550e8400-e29b-41d4-a716-446655440000",
  "exerciseId": "SQUAT",
  "exerciseName": "스쿼트",
  "date": "2026-10-15T15:30:00",
  "weightKg": 60.0,
  "sets": 3,
  "reps": 12,
  "totalReps": 36,
  "correctReps": 32,
  "incorrectReps": 4,
  "durationSeconds": 1200,
  "videoLocalPath": "/var/mobile/Containers/Data/Application/workout_rec_01.mp4",
  "feedbackCounts": {
    "무릎이 안쪽으로 모이지 않게 주의하세요": 3,
    "상체가 과도하게 앞으로 숙여졌습니다": 1
  },
  "feedbackNotes": [
    "무릎이 안쪽으로 모이지 않게 주의하세요",
    "상체가 과도하게 앞으로 숙여졌습니다"
  ],
  "poseMetricsSummary": {
    "avgKneeAngle": 88.5,
    "avgTorsoAngle": 35.2
  }
}
```
- **Response Body (201 Created):**
```json
{
  "serverRecordId": "101",
  "clientRecordId": "550e8400-e29b-41d4-a716-446655440000",
  "videoLocalPath": "/var/mobile/Containers/Data/Application/workout_rec_01.mp4",
  "success": true,
  "message": "Record synced successfully",
  "syncedAt": "2026-10-15T15:30:05"
}
```

---

#### 2) 월별 운동 캘린더 조회 (`GET /api/v1/workouts/calendar?year=2026&month=10`)
- **Response Body (200 OK):**
```json
{
  "year": 2026,
  "month": 10,
  "totalWorkoutDays": 5,
  "days": [
    {
      "date": "2026-10-15",
      "workoutCount": 1,
      "records": [
        {
          "recordId": "101",
          "exerciseName": "스쿼트",
          "weightKg": 60.0,
          "sets": 3,
          "reps": 12
        }
      ]
    }
  ]
}
```

---

### [그룹 5] Reports (리포트 분석 및 통계)

| No | API명 | HTTP Method | Endpoint | 인증 필요 | 주요 설명 |
|:---:|:---|:---:|:---|:---:|:---|
| 21 | **리포트 통계 분석** | `GET` | `/api/v1/workouts/reports/analysis` | 🔒 Bearer | `?period=weekly` 또는 `monthly` 기준 종목별 비중 도넛 차트, 총 볼륨, 빈발 피드백 TOP 3 |

---

#### 1) 리포트 통계 분석 (`GET /api/v1/workouts/reports/analysis?period=weekly`)
- **Response Body (200 OK):**
```json
{
  "period": "weekly",
  "startDate": "2026-10-12",
  "endDate": "2026-10-18",
  "totalVolumeKg": 3240.0,
  "totalWorkoutSessions": 3,
  "totalCompletedSets": 9,
  "totalReps": 108,
  "exerciseDistributions": [
    {
      "exerciseName": "스쿼트",
      "appExerciseId": "squat",
      "volumeKg": 2160.0,
      "percentage": 66.7
    },
    {
      "exerciseName": "벤치프레스",
      "appExerciseId": "benchpress",
      "volumeKg": 1080.0,
      "percentage": 33.3
    }
  ],
  "frequentFeedbacks": [
    {
      "feedbackMessage": "무릎이 안쪽으로 모이지 않게 주의하세요",
      "count": 5
    },
    {
      "feedbackMessage": "상체가 과도하게 앞으로 숙여졌습니다",
      "count": 2
    }
  ]
}
```

---

## 3. 공통 에러 규격 & HTTP 상태 코드

모든 실패 응답은 일관된 JSON 규격을 따릅니다.

```json
{
  "success": false,
  "error": {
    "code": "USER_NOT_FOUND",
    "message": "사용자를 찾을 수 없습니다."
  }
}
```

| HTTP Status | Error Code | 설명 |
|:---:|:---|:---|
| `400 Bad Request` | `INVALID_INPUT_VALUE` | 입력 필드 유효성 검증 실패 (이메일, 비밀번호 길이 등) |
| `400 Bad Request` | `EMAIL_NOT_VERIFIED` | 이메일 인증이 완료되지 않았거나 일회용 토큰 만료 |
| `400 Bad Request` | `TOO_MANY_VERIFICATION_ATTEMPTS` | 인증번호 5회 오입력으로 인증번호 폐기 |
| `400 Bad Request` | `INVALID_VERIFICATION_TOKEN` | 유효하지 않거나 이미 사용된 일회용 검증 토큰 |
| `401 Unauthorized` | `INVALID_CREDENTIALS` | 아이디/이메일 또는 비밀번호 불일치 |
| `401 Unauthorized` | `TOKEN_EXPIRED` | JWT 토큰 만료 (로그인 필요 또는 토큰 갱신 필요) |
| `404 Not Found` | `USER_NOT_FOUND` | 사용자를 찾을 수 없음 (비밀번호 재설정 시 아이디-이메일 불일치 포함) |
| `409 Conflict` | `USERNAME_ALREADY_EXISTS` | 이미 사용 중인 아이디 |
| `409 Conflict` | `EMAIL_ALREADY_EXISTS` | 이미 가입된 이메일 주소 |
| `429 Too Many Requests`| `RESEND_COOLDOWN_ACTIVE` | 인증번호 재발송 1분 쿨다운 미경과 |
| `503 Service Unavailable`| `EMAIL_SEND_FAILED` | SMTP 메일 서버 발송 일시 장애 |
