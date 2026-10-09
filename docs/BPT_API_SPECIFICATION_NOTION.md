# 📋 BPT (Body Posture Training) API 명세서

> **Base URL**: `http://151.145.79.106:8080/api/v1` (배포 서버)  
> **로컬 개발**: `http://localhost:8080/api/v1` (또는 `8081`)  
> **Swagger UI**: `http://151.145.79.106:8080/api/v1/swagger-ui/index.html`  
> **인증 방식**: HTTP Bearer JWT (`Authorization: Bearer <access_token>`)  
> **최종 갱신일**: 2026년 10월 9일  

---

## 📌 목차
1. [공통 사항 및 인증 헤더](#1-공통-사항-및-인증-헤더)
2. [인증 및 회원가입 (Auth)](#2-인증-및-회원가입-auth)
3. [사용자 및 체형 관리 (Users)](#3-사용자-및-체형-관리-users)
4. [운동 종목 마스터 (Exercises)](#4-운동-종목-마스터-exercises)
5. [운동 기록 및 동기화 (Workouts)](#5-운동-기록-및-동기화-workouts)
6. [리포트 분석 및 통계 (Reports)](#6-리포트-분석-및-통계-reports)
7. [공통 에러 응답 규격](#7-공통-에러-응답-규격)

---

## 1. 공통 사항 및 인증 헤더

- 모든 API 요청 및 응답 본문은 **UTF-8 인코딩된 JSON(`application/json`)** 형식입니다.
- 인증이 필요한 모든 API는 요청 Header에 아래 형식으로 토큰을 전달해야 합니다.
  ```http
  Authorization: Bearer <accessToken>
  ```
- 클라이언트(앱)에서는 코리 멘트(`coachMessage`, `coachFeedback` 등)를 자체 관리하므로, 서버 응답에서 관련 텍스트 필드는 제외되어 있습니다.

---

## 2. 인증 및 회원가입 (Auth)

### 2.1 아이디 로그인
- **Method / URL**: `POST /auth/login`
- **인증 필요 여부**: ❌ 비인증
- **설명**: 아이디(`username`)와 비밀번호로 로그인하여 JWT Access Token을 발급받습니다.

#### Request Body
```json
{
  "username": "user123",
  "password": "password123!"
}
```

#### Response Body (200 OK)
```json
{
  "token": "eyJhbGciOiJIUzUxMiJ9...",
  "accessToken": "eyJhbGciOiJIUzUxMiJ9...",
  "refreshToken": "eyJhbGciOiJIUzUxMiJ9...",
  "tokenType": "Bearer",
  "expiresIn": 3600,
  "user": {
    "id": "1",
    "username": "user123",
    "name": "홍길동",
    "email": "user123@bpt.app",
    "avatarInitials": "홍",
    "phoneNumber": "010-1234-5678",
    "birthDate": "1998-05-15",
    "weightKg": 70.0,
    "heightCm": 175.0,
    "gender": "MALE",
    "workoutGoal": "근력 증량",
    "weeklyFrequency": 3,
    "notificationTime": "18:00",
    "notificationEnabled": true,
    "bodyScanLocalPath": null,
    "lastBodyScanDate": "2026-10-09",
    "totalWorkouts": 12,
    "streakDays": 3,
    "joinedAt": "2026-09-30T16:30:00"
  }
}
```

---

### 2.2 회원가입
- **Method / URL**: `POST /auth/signup`
- **인증 필요 여부**: ❌ 비인증
- **설명**: 새 계정을 생성하고 최초 JWT 토큰을 발급합니다.

#### Request Body
```json
{
  "username": "user123",
  "password": "password123!",
  "email": "user123@bpt.app",
  "name": "홍길동",
  "phoneNumber": "010-1234-5678",
  "birthDate": "1998-05-15",
  "termsAgreed": true
}
```

#### Response Body (201 Created)
- 로그인(`POST /auth/login`) 응답 규격과 동일

---

### 2.3 아이디 중복 확인
- **Method / URL**: `GET /auth/check-username?username={username}`
- **인증 필요 여부**: ❌ 비인증
- **설명**: 회원가입 시 아이디 중복 여부를 실시간 조회합니다.

#### Response Body (200 OK)
```json
{
  "available": true,
  "message": "사용 가능한 아이디입니다."
}
```

---

### 2.4 이메일 인증번호 발송 (Real SMTP)
- **Method / URL**: `POST /auth/verify-email/request`
- **인증 필요 여부**: ❌ 비인증
- **설명**: 가입 또는 본인인증용으로 6자리 난수 코드를 실제 사용자의 이메일로 발송합니다 (유효시간: 5분).

#### Request Body
```json
{
  "email": "user123@edu.hanbat.ac.kr"
}
```

#### Response Body (200 OK)
```json
{
  "success": true,
  "message": "인증번호가 이메일로 발송되었습니다. (5분 내 입력)"
}
```

---

### 2.5 이메일 인증번호 확인
- **Method / URL**: `POST /auth/verify-email/confirm`
- **인증 필요 여부**: ❌ 비인증
- **설명**: 전송된 6자리 인증번호의 유효성을 검증합니다.

#### Request Body
```json
{
  "email": "user123@edu.hanbat.ac.kr",
  "code": "842109"
}
```

#### Response Body (200 OK)
```json
{
  "success": true,
  "message": "이메일 인증이 완료되었습니다."
}
```

---

## 3. 사용자 및 체형 관리 (Users)

### 3.1 내 프로필 조회
- **Method / URL**: `GET /users/me`
- **인증 필요 여부**: 🔒 Bearer Token
- **설명**: 로그인된 사용자의 상세 프로필, 알림 설정, 체형 측정일, 주간 목표 횟수를 조회합니다.

#### Response Body (200 OK)
```json
{
  "id": "1",
  "username": "user123",
  "name": "홍길동",
  "email": "user123@bpt.app",
  "phoneNumber": "010-1234-5678",
  "birthDate": "1998-05-15",
  "weightKg": 70.0,
  "heightCm": 175.0,
  "gender": "MALE",
  "workoutGoal": "근력 증량",
  "weeklyFrequency": 4,
  "notificationTime": "18:00",
  "notificationEnabled": true,
  "bodyScanLocalPath": "/var/mobile/Containers/Data/scan_01.dat",
  "lastBodyScanDate": "2026-10-09",
  "totalWorkouts": 12,
  "streakDays": 3,
  "joinedAt": "2026-09-30T16:30:00"
}
```
> **Tip**: 한 번도 체형 측정을 진행하지 않은 신규 회원은 `lastBodyScanDate: null`로 내려옵니다.

---

### 3.2 내 프로필 수정
- **Method / URL**: `PUT /users/me`
- **인증 필요 여부**: 🔒 Bearer Token
- **설명**: 프로필 정보, 주간 목표 운동 횟수(`weeklyFrequency`), 알림 설정, 체형 측정일(`lastBodyScanDate`)을 수정합니다.

#### Request Body
```json
{
  "name": "홍길동",
  "weeklyFrequency": 4,
  "notificationEnabled": true,
  "notificationTime": "19:00",
  "lastBodyScanDate": "2026-10-09",
  "weightKg": 72.5
}
```
#### Response Body (200 OK)
- 수정된 `UserDto` 객체 반환

---

### 3.3 체형 측정 완료 기록 (전용 API)
- **Method / URL**: `POST /users/me/body-scans` (또는 `/users/me/body-scan`)
- **인증 필요 여부**: 🔒 Bearer Token
- **설명**: 체형 촬영(사진 4장)을 완료했을 때 호출하여 서버의 `lastBodyScanDate`를 즉시 오늘 날짜로 갱신합니다.

#### Request Body (생략 가능 / 빈 객체 `{}` 전송 가능)
```json
{
  "scanDate": "2026-10-09",
  "bodyScanLocalPath": "/var/mobile/Containers/Data/Application/scan_01.dat"
}
```
*(`scanDate`를 생략하거나 보내지 않으면 서버가 오늘 날짜로 자동 설정합니다.)*

#### Response Body (200 OK)
- 갱신된 `UserDto` 객체 반환 (`lastBodyScanDate` 반영 완료)

---

### 3.4 회원 탈퇴
- **Method / URL**: `DELETE /users/me`
- **인증 필요 여부**: 🔒 Bearer Token
- **설명**: 회원의 계정, 운동 기록(세트/피드백 포함), 체형 측정 데이터를 모두 영구 삭제합니다.

#### Response Body (200 OK)
```json
{
  "success": true,
  "message": "회원 탈퇴가 성공적으로 완료되었습니다."
}
```

---

### 3.5 메인 홈 대시보드 요약
- **Method / URL**: `GET /users/me/dashboard`
- **인증 필요 여부**: 🔒 Bearer Token
- **설명**: 주간 목표 달성률, 오늘 운동 시간/세트수, 체형 재측정(30일 주기) 필요 여부 및 최근 운동 기록 2건을 반환합니다.

#### Response Body (200 OK)
```json
{
  "userName": "홍길동",
  "date": "2026-10-09",
  "achievementRate": 75.0,
  "todayWorkoutMinutes": 42,
  "todayCompletedSets": 4,
  "todayTotalReps": 45,
  "weeklyGoalCount": 4,
  "weeklyCompletedCount": 3,
  "weeklyActiveDays": ["MON", "WED", "FRI"],
  "needsBodyScan": false,
  "daysSinceLastScan": 0,
  "recentWorkouts": [
    {
      "exerciseName": "스쿼트",
      "weightKg": 60.0,
      "sets": 3,
      "reps": 30,
      "relativeTime": "오늘"
    }
  ]
}
```
> **체형 재측정 알림(`needsBodyScan`) 판별 기준**:  
> - `needsBodyScan: true`: 한 번도 측정하지 않았거나(`lastBodyScanDate == null`), 마지막 측정일로부터 30일 이상 경과했을 때(`daysSinceLastScan >= 30`).  
> - `needsBodyScan: false`: 마지막 측정 후 30일 미만일 때.

---

### 3.6 온보딩 정보 등록
- **Method / URL**: `PUT /users/me/onboarding`
- **인증 필요 여부**: 🔒 Bearer Token
- **설명**: 가입 후 온보딩 화면에서 입력한 신체 스펙 및 목표를 저장하고 오늘 날짜를 체형 스캔일로 기록합니다.

#### Request Body
```json
{
  "gender": "MALE",
  "heightCm": 178.5,
  "weightKg": 74.0,
  "workoutGoal": "근력 증량",
  "weeklyFrequency": 4,
  "bodyScanLocalPath": "/var/mobile/Containers/Data/scan_01.dat"
}
```

---

## 4. 운동 종목 마스터 (Exercises)

현재 서버에 등록된 공식 운동 종목은 **5대 핵심 운동**입니다.

| ID | 코드 (`exerciseCode`) | 운동명 (`exerciseName`) | 타겟 부위 (`category`) | 표준 가동범위 (ROM) |
| :---: | :---: | :---: | :---: | :---: |
| **1** | `SQUAT` | 스쿼트 | `LEGS` | 80° ~ 110° |
| **2** | `BENCH_PRESS` | 벤치프레스 | `CHEST` | 75° ~ 95° |
| **3** | `DEADLIFT` | 데드리프트 | `BACK` | 60° ~ 100° |
| **4** | `PUSH_UP` | 푸쉬업 | `CHEST` | 70° ~ 90° |
| **5** | `BARBELL_ROW` | 바벨로우 | `BACK` | 60° ~ 100° |

### 4.1 전체 운동 종목 목록 조회
- **Method / URL**: `GET /exercises` (또는 `GET /exercises?category=CHEST`)
- **인증 필요 여부**: ❌ 비인증

#### Response Body (200 OK)
```json
[
  {
    "id": 1,
    "exerciseCode": "SQUAT",
    "exerciseName": "스쿼트",
    "category": "LEGS",
    "standardRomMin": 80.0,
    "standardRomMax": 110.0
  },
  {
    "id": 2,
    "exerciseCode": "BENCH_PRESS",
    "exerciseName": "벤치프레스",
    "category": "CHEST",
    "standardRomMin": 75.0,
    "standardRomMax": 95.0
  },
  {
    "id": 3,
    "exerciseCode": "DEADLIFT",
    "exerciseName": "데드리프트",
    "category": "BACK",
    "standardRomMin": 60.0,
    "standardRomMax": 100.0
  },
  {
    "id": 4,
    "exerciseCode": "PUSH_UP",
    "exerciseName": "푸쉬업",
    "category": "CHEST",
    "standardRomMin": 70.0,
    "standardRomMax": 90.0
  },
  {
    "id": 5,
    "exerciseCode": "BARBELL_ROW",
    "exerciseName": "바벨로우",
    "category": "BACK",
    "standardRomMin": 60.0,
    "standardRomMax": 100.0
  }
]
```

---

## 5. 운동 기록 및 동기화 (Workouts)

### 5.1 운동 세션 기록 저장
- **Method / URL**: `POST /workouts/records`
- **인증 필요 여부**: 🔒 Bearer Token
- **설명**: 운동 완료 후 세트수, 볼륨, 영상 경로, 세트별 상세 기록 및 **자세 피드백 횟수(`feedbackCounts`)**를 저장합니다.

#### Request Body
```json
{
  "clientRecordId": "c-20261009-001",
  "exerciseId": "squat",
  "exerciseName": "스쿼트",
  "date": "2026-10-09T16:00:00",
  "weightKg": 60.0,
  "totalSets": 3,
  "targetSets": 3,
  "totalReps": 36,
  "correctReps": 32,
  "incorrectReps": 4,
  "durationSeconds": 1200,
  "totalVolume": 2160,
  "isGoalAchieved": true,
  "videoLocalPath": "/var/mobile/Containers/Data/Application/workout_rec_01.mp4",
  "feedbackCounts": {
    "squat_knee_valgus": 3,
    "squat_shallow": 1
  },
  "feedbackNotes": [
    "무릎이 안쪽으로 모이지 않게 주의하세요"
  ],
  "setsDetail": [
    { "setNumber": 1, "reps": 12, "weightKg": 60.0, "postureStatus": "안정" },
    { "setNumber": 2, "reps": 12, "weightKg": 60.0, "postureStatus": "안정" },
    { "setNumber": 3, "reps": 12, "weightKg": 60.0, "postureStatus": "주의" }
  ]
}
```

#### Response Body (201 Created)
```json
{
  "serverRecordId": "101",
  "clientRecordId": "c-20261009-001",
  "videoLocalPath": "/var/mobile/Containers/Data/Application/workout_rec_01.mp4",
  "success": true,
  "message": "Record synced successfully",
  "syncedAt": "2026-10-09T16:00:05"
}
```

---

### 5.2 운동 기록 오프라인 동기화
- **Method / URL**: `POST /workouts/records/sync`
- **인증 필요 여부**: 🔒 Bearer Token
- **설명**: 네트워크 재연결 시 `clientRecordId` 기준으로 중복 없이 안전하게 멱등 동기화합니다. 요청/응답 형식은 `POST /workouts/records`와 동일합니다.

---

### 5.3 전체 운동 기록 목록 조회
- **Method / URL**: `GET /workouts/records`
- **인증 필요 여부**: 🔒 Bearer Token
- **설명**: 최신순으로 운동 기록 목록을 조회합니다. 각 기록마다 `feedbackCounts`와 `setsDetail`이 포함됩니다.

#### Response Body (200 OK)
```json
[
  {
    "id": "101",
    "clientRecordId": "c-20261009-001",
    "exerciseId": "squat",
    "exerciseName": "스쿼트",
    "date": "2026-10-09T16:00:00",
    "weightKg": 60.0,
    "sets": 3,
    "targetSets": 3,
    "totalSets": 3,
    "reps": 12,
    "totalReps": 36,
    "correctReps": 32,
    "incorrectReps": 4,
    "durationSeconds": 1200,
    "isGoalAchieved": true,
    "totalVolume": 2160,
    "videoLocalPath": "/var/mobile/Containers/Data/Application/workout_rec_01.mp4",
    "feedbackCounts": {
      "squat_knee_valgus": 3,
      "squat_shallow": 1
    },
    "feedbackNotes": [
      "무릎이 안쪽으로 모이지 않게 주의하세요"
    ],
    "setsDetail": [
      { "setNumber": 1, "reps": 12, "weightKg": 60.0, "postureStatus": "안정" }
    ],
    "poseMetricsSummary": null
  }
]
```

---

### 5.4 월별 운동 캘린더 요약 조회
- **Method / URL**: `GET /workouts/calendar?year=2026&month=10`
- **인증 필요 여부**: 🔒 Bearer Token
- **설명**: 특정 연/월에 운동을 수행한 날짜 목록 및 일별 요약 리스트를 반환합니다.

#### Response Body (200 OK)
```json
{
  "year": 2026,
  "month": 10,
  "monthlyWorkoutCount": 3,
  "workoutDates": [
    "2026-10-05",
    "2026-10-07",
    "2026-10-09"
  ],
  "dailySummaries": [
    {
      "date": "2026-10-09",
      "records": [
        {
          "exerciseName": "스쿼트",
          "weightKg": 60.0,
          "sets": 3,
          "reps": 36
        }
      ]
    }
  ]
}
```

---

## 6. 리포트 분석 및 통계 (Reports)

### 6.1 리포트 분석 집계 조회
- **Method / URL**: `GET /reports/analysis?from={YYYY-MM-DD}&to={YYYY-MM-DD}`
- **인증 필요 여부**: 🔒 Bearer Token
- **Query Parameters**:
  - `from` *(선택)*: 조회 시작일 (예: `2026-09-01`)
  - `to` *(선택)*: 조회 종료일 (예: `2026-09-30`)
  - *(파라미터가 없으면 회원의 전체 기간 기록을 집계합니다)*
- **정렬 기준**:
  - `exercises`: 세션 수(`sessions`)가 많은 순 내림차순
  - `mistakes`: 발생 횟수(`count`)가 많은 순 내림차순

#### Response Body (200 OK)
```json
{
  "totalSessions": 42,
  "exercises": [
    { "exerciseId": "squat", "sessions": 13 },
    { "exerciseId": "benchpress", "sessions": 9 },
    { "exerciseId": "deadlift", "sessions": 8 },
    { "exerciseId": "pushup", "sessions": 7 },
    { "exerciseId": "barbell-row", "sessions": 5 }
  ],
  "mistakes": [
    { "key": "squat_knee_valgus", "count": 24 },
    { "key": "squat_lean_drift", "count": 17 },
    { "key": "pushup_hip_sag", "count": 12 },
    { "key": "benchpress_elbow_flare", "count": 9 }
  ]
}
```
> **Tip**: 해당 기간에 기록이 없을 때는 `{"totalSessions": 0, "exercises": [], "mistakes": []}` 빈 배열 형태로 안전하게 반환됩니다.

---

## 7. 공통 에러 응답 규격

HTTP 상태 코드가 `4xx` 또는 `5xx`일 때 아래 형식의 공통 JSON 에러 본문이 반환됩니다.

```json
{
  "success": false,
  "error": {
    "code": "INVALID_INPUT_VALUE",
    "message": "입력값이 올바르지 않습니다."
  }
}
```

### 주요 에러 코드 목록
| HTTP Status | Error Code | 설명 |
| :---: | :--- | :--- |
| `400` | `INVALID_INPUT_VALUE` | 필수 필드 누락 또는 형식 오류 (전화번호, 날짜 등) |
| `401` | `INVALID_TOKEN` / `EXPIRED_TOKEN` | 인증 토큰 만료 또는 유효하지 않은 토큰 |
| `403` | `FORBIDDEN` | 접근 권한 부족 |
| `404` | `USER_NOT_FOUND` | 사용자를 찾을 수 없음 (탈퇴 계정 포함) |
| `404` | `EXERCISE_NOT_FOUND` | 요청한 운동 종목이 존재하지 않음 |
| `409` | `USERNAME_ALREADY_EXISTS` | 이미 사용 중인 아이디 |
| `409` | `EMAIL_ALREADY_EXISTS` | 이미 사용 중인 이메일 |
| `500` | `INTERNAL_SERVER_ERROR` | 서버 내부 처리 오류 |
