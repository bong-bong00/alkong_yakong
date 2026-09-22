# 개인 Render 분리 구성 보관 문서

- 작성일: 2026-09-22
- 목적: 기존 팀원 Render는 유지하면서, `woong2`에서 개발한 OCR·약·DUR·복약 기능을 별도의 개인 Render에서 시험하고 보관한다.
- 최종 원칙: 개발 중에는 서버를 분리할 수 있지만, 최종 배포 전에는 `main`과 기능 브랜치를 병합하고 서버 구성을 다시 하나로 정리한다.

---

## 1. 결론

개인 Render는 `woong2` 브랜치로 만든다. 이 서버에는 OCR 하나만 두지 않고, OCR로 등록한 약을 다시 보여 주는 데 필요한 약 관련 기능 전체를 함께 둔다.

```text
처방전 OCR
→ 인식 결과 확인
→ 등록 확정
→ 오늘 홈
→ 내 약 목록
→ 약 자세히
→ DUR 함께먹기 검사
→ 복약 완료 기록
→ 복약 기록·달력 조회
```

이 과정은 같은 DB에 연결되어야 한다. OCR 등록은 개인 Render에서 처리하면서 홈이나 내 약 목록은 기존 Render에서 조회하면, 등록한 약이 보이지 않는 문제가 생긴다.

---

## 2. 서버별 담당 범위

### 2.1 기존 팀원 Render에 유지할 기능

기존 팀원 Render와 기존 URL은 삭제하거나 덮어쓰지 않는다. 아래 기능은 기존 서버가 계속 담당한다.

1. 로그인과 회원가입
2. 사용자 계정 및 기본 정보
3. 보호자 연결과 보호자 화면
4. Polar 센서 연결
5. 심박수 측정·저장·조회
6. 푸시 알림과 보호자 알림
7. AI 약사 챗봇
8. 팀원이 관리 중인 기타 공통 기능

기존 Render의 코드를 개인 기능 테스트 때문에 직접 수정하거나, 개인 Render 주소로 교체하지 않는다.

### 2.2 새 개인 Render가 담당할 기능

새 개인 Render는 다음 기능을 한 묶음으로 담당한다.

1. 처방전 사진 업로드 및 CLOVA OCR 호출
2. OCR로 읽은 약 이름·복용량·횟수·일수 구조화
3. 식약처 공식 의약품 조회 및 제품 코드 매칭
4. `이렇게 읽었어요` 화면에 필요한 결과 제공
5. OCR 결과 수정 후 처방전·약·복용 일정 등록
6. 홈 화면의 오늘 복용약 조회
7. 내 약 목록 및 과거 약 조회
8. 약 자세히 정보 조회
9. DUR 함께먹기 분석 및 최근 분석 결과 조회
10. `먹었어요` 복약 완료 저장 및 취소
11. 복약 기록과 월별 복약 달력 조회
12. 처방 일정과 복용일 조회
13. 손으로 약 입력 및 공식 약 검색

대표 API 범위는 다음과 같다.

```text
POST /api/v1/prescriptions/ocr
POST /api/v1/prescriptions/confirm
GET  /api/v1/medicines/lookup

GET  /api/v1/users/{user_id}/today-medicines
GET  /api/v1/users/{user_id}/medicines
GET  /api/v1/users/{user_id}/medicines/{medicine_code}
GET  /api/v1/drug-explain/{medicine_code}

POST /api/v1/dur/analyze
GET  /api/v1/users/{user_id}/dur/latest

POST /api/v1/medication-logs
GET  /api/v1/users/{user_id}/medication-history
GET  /api/v1/users/{user_id}/medication-calendar
```

실제 경로가 변경되면 `/docs`에 표시된 현재 FastAPI 명세를 기준으로 확인한다.

---

## 3. 새 Render 생성 설정

Render에서 `New > Web Service`를 선택하고 GitHub의 `bong-bong00/alkong_yakong` 저장소를 연결한다.

### 기본 설정

| 항목 | 설정값 |
|---|---|
| Name | `alkong-yakong-medication` 등 기존 서비스와 겹치지 않는 이름 |
| Language | `Python 3` |
| Branch | `woong2` |
| Region | 기존 Render와 가능하면 같은 지역 |
| Root Directory | 비워 둠 |
| Build Command | `pip install -r requirements.txt` |
| Start Command | `uvicorn app.main:app --host 0.0.0.0 --port $PORT` |
| Health Check Path | `/health` |

현재 개인 기능은 `main`보다 `woong2`에 더 최신 상태로 들어가 있으므로, 개인 기능 확인용 Render에서 `main`을 선택하면 안 된다.

다만 개인 Render가 기존 Render 전체를 대체해야 하는 상황이라면 바로 `woong2`를 배포하지 않는다. 먼저 최신 `main`을 `woong2` 또는 별도의 배포 브랜치에 병합하고 로그인·Polar·알림 기능까지 검사한 뒤 배포한다.

---

## 4. Render 환경변수

비밀키는 코드나 문서에 실제 값을 적지 않고 Render의 `Environment` 메뉴에 등록한다.

### 현재 Render 화면에서 먼저 고칠 것

아래처럼 일반적인 소문자 이름으로 등록하면 현재 백엔드가 읽지 못한다.

```text
database_url
api_key
```

현재 코드는 `database_url` 또는 `api_key`라는 환경변수를 사용하지 않는다. Render의 환경변수 이름은 코드와 정확히 같아야 하므로 위 두 항목은 삭제하거나, 아래에 적힌 실제 변수 이름으로 다시 등록한다.

또한 현재 백엔드는 PostgreSQL의 `DATABASE_URL`을 사용하는 구조가 아니라 SQLite 파일을 직접 연다. 따라서 별도의 PostgreSQL 전환 작업을 하지 않았다면 `database_url` 값을 넣어도 DB 연결에는 반영되지 않는다.

### 필수

```text
APP_ENV=production
CLOVA_OCR_ENABLED=true
CLOVA_OCR_API_URL=<기존 서버 담당자에게 받은 CLOVA 호출 주소>
CLOVA_OCR_SECRET_KEY=<기존 서버 담당자에게 받은 CLOVA 비밀키>
MFDS_DRUG_PERMISSION_API_KEY=<식약처 의약품 허가정보 API 키>
DUR_API_KEY=<식약처 DUR API 키>
```

`E_DRUG_API_KEY` 또는 `MFDS_SERVICE_KEY`를 기존 환경에서 사용하고 있다면 같은 값을 새 Render에도 등록한다.

실제로 Render 화면에 추가해야 할 기본 목록은 다음과 같다.

| KEY | VALUE | 용도 |
|---|---|---|
| `APP_ENV` | `production` | 운영 서버 모드 |
| `CLOVA_OCR_ENABLED` | `true` | 처방전 OCR 사용 |
| `CLOVA_OCR_API_URL` | CLOVA Invoke URL | OCR 호출 주소 |
| `CLOVA_OCR_SECRET_KEY` | CLOVA Secret Key | OCR 인증 |
| `E_DRUG_API_KEY` | 공공데이터포털 서비스 키 | 의약품 쉬운 정보 조회 |
| `MFDS_DRUG_PERMISSION_API_KEY` | 공공데이터포털 서비스 키 | 식약처 제품 허가정보 조회 |
| `DUR_API_KEY` | 공공데이터포털 서비스 키 | 병용금기 등 DUR 조회 |
| `DUR_AUTO_SYNC` | `true` | 서버 시작 후 DUR 자료 동기화 |
| `DUR_BOOTSTRAP_MAX_PAGES` | `20` | 최초 DUR 동기화 범위 |
| `DEMO_SEED_ENABLED` | `false` | 운영 서버에 임의 데모 약 추가 방지 |

공공데이터포털에서 같은 서비스 키를 사용하도록 신청되어 있다면 `E_DRUG_API_KEY`, `MFDS_DRUG_PERMISSION_API_KEY`, `DUR_API_KEY`의 VALUE가 같을 수 있다. KEY 이름은 각각 따로 등록해야 한다.

최소한 OCR 촬영만 먼저 시험하려면 다음 네 항목은 반드시 필요하다.

```text
APP_ENV=production
CLOVA_OCR_ENABLED=true
CLOVA_OCR_API_URL=<CLOVA Invoke URL>
CLOVA_OCR_SECRET_KEY=<CLOVA Secret Key>
```

그러나 공식 약 매칭과 DUR까지 정상적으로 시험하려면 식약처 관련 키 세 개도 함께 등록해야 한다.

### 필요할 때만 등록

```text
GEMINI_API_KEY=<새 서버에서도 AI 설명·챗 기능을 사용할 경우>
GEMINI_MODEL=gemini-2.5-flash
DEMO_SEED_ENABLED=false
DUR_AUTO_SYNC=true
DUR_BOOTSTRAP_MAX_PAGES=20
```

다음 값은 Render가 자동으로 제공하므로 직접 추가하지 않는다.

```text
PORT
RENDER
```

`LOCAL_API_BASE_URL`도 Render 환경변수로 넣는 값이 아니다. 이 값은 Flutter 앱을 실행하거나 APK를 만들 때 `--dart-define`으로 전달한다.

### Persistent Disk를 사용할 때만 추가할 DB 경로

Render에 `/var/data` Persistent Disk를 실제로 추가한 경우에만 다음 값을 등록한다.

```text
ALKONGYAKONG_DB_PATH=/var/data/alkongyakong.db
MFDS_DRUG_PERMISSION_DB_PATH=/var/data/mfds_drug_permission.db
EASY_CATEGORY_MAP_DB_PATH=/var/data/easy_category_map.db
```

Persistent Disk를 추가하지 않은 무료 Render에서 위 경로만 먼저 등록하면 `/var/data` 사용 조건이 맞지 않을 수 있으므로 넣지 않는다. 무료 테스트에서는 DB 경로 변수를 생략하고 기본 SQLite 경로를 사용한다.

기존 Render의 키를 복사해야 한다면 팀원에게 값 자체를 채팅이나 Git으로 보내 달라고 하지 말고, Render 환경변수에 직접 등록하도록 요청한다.

---

## 5. DB 저장 방식

현재 백엔드는 SQLite를 사용한다. 새 Render를 만들면 기존 팀원 Render의 SQLite와 자동으로 연결되지 않는다.

```text
기존 Render DB ≠ 개인 Render DB
```

따라서 두 서버에 같은 사용자가 있어도 약 등록 내용은 서로 자동 공유되지 않는다.

### 단순 테스트만 할 경우

무료 Render로 실행할 수 있다. 다만 재배포·재시작·휴면 복구 과정에서 서버에서 새로 저장한 SQLite 데이터가 사라질 수 있다. 이 방식은 기능 동작 확인용으로만 사용한다.

### 데이터를 계속 보관해야 할 경우

Persistent Disk를 지원하는 Render 요금제를 사용하고 다음과 같이 구성한다.

```text
Disk mount path: /var/data

ALKONGYAKONG_DB_PATH=/var/data/alkongyakong.db
MFDS_DRUG_PERMISSION_DB_PATH=/var/data/mfds_drug_permission.db
EASY_CATEGORY_MAP_DB_PATH=/var/data/easy_category_map.db
```

주의사항:

1. 하나의 Persistent Disk를 기존 Render와 개인 Render가 동시에 공유할 수 없다.
2. 두 Render의 SQLite 파일을 억지로 복사하며 동시에 운영하지 않는다.
3. 운영 단계에서 여러 서버가 같은 데이터를 써야 한다면 SQLite가 아니라 공용 DB 전환을 별도 설계해야 한다.
4. `mfds_drug_permission.db`는 현재 Git에서 전달되는 파일이 아니므로 식약처 API 키와 초기 동기화가 필요하다.

---

## 6. Flutter 앱에서 새 Render 연결

새 Render를 생성하면 다음과 같은 고유 주소가 생긴다.

```text
https://alkong-yakong-medication.onrender.com
```

기본 동작 확인:

```text
https://alkong-yakong-medication.onrender.com/health
https://alkong-yakong-medication.onrender.com/docs
```

현재 기본 약 기능 서버 주소는 새 Render로 설정되어 있으므로 일반 실행을 사용한다.

```powershell
flutter run
```

APK도 일반 명령으로 만든다.

```powershell
flutter build apk
```

로컬 FastAPI를 다시 사용해야 할 때만 다음과 같이 주소를 덮어쓴다.

```powershell
flutter run --dart-define=LOCAL_API_BASE_URL=http://로컬PC주소:8000
```

앱 연결 결과는 다음과 같아야 한다.

```text
로그인·회원가입·Polar·알림·공통 기능
→ 기존 팀원 Render

OCR·약 등록·오늘 약·내 약·약 상세·DUR·복약 기록·달력
→ 새 개인 Render
```

---

## 7. 반드시 피해야 할 연결

다음처럼 등록과 조회를 서로 다른 Render로 나누면 안 된다.

```text
OCR 및 등록       → 개인 Render
홈·내 약 목록 조회 → 기존 Render
```

이 경우 개인 Render DB에는 약이 있지만 기존 Render DB에는 없으므로, 사용자 입장에서는 등록한 약이 사라진 것처럼 보인다.

다음 방식으로 연결해야 한다.

```text
OCR 및 등록       → 개인 Render
홈·내 약 목록 조회 → 개인 Render
약 자세히         → 개인 Render
DUR 검사          → 개인 Render
복약 기록         → 개인 Render
```

로그인 후 앱이 가지고 있는 `user_id`는 개인 Render의 약 API 요청에도 동일하게 전달한다. 신규 개인 DB에서 사용자 기본 행이 필요한지 `/docs`와 서버 로그로 확인한다.

---

## 8. 생성 후 확인 순서

- [ ] 새 Render의 브랜치가 `woong2`인지 확인
- [ ] 빌드와 시작 명령 확인
- [ ] CLOVA·식약처·DUR 환경변수 등록
- [ ] `/health`가 `status: ok`를 반환하는지 확인
- [ ] `/health`에서 `ocr_configured: true`인지 확인
- [ ] `/docs`에서 OCR·확정·약 목록·DUR·복약 API 확인
- [ ] Flutter 실행 시 `LOCAL_API_BASE_URL`에 새 주소 전달
- [ ] 처방전 사진을 찍으면 `이렇게 읽었어요` 화면이 나오는지 확인
- [ ] 등록 후 홈에 약이 나타나는지 확인
- [ ] 같은 약이 내 약 목록에도 나타나는지 확인
- [ ] 약 자세히 화면이 열리는지 확인
- [ ] 실제 충돌이 있는 약에서만 함께먹기 경고가 나오는지 확인
- [ ] `먹었어요` 기록 후 홈과 복약 기록 화면이 함께 바뀌는지 확인
- [ ] 서버 재시작 후 데이터 유지 여부 확인

OCR 성공만 보고 작업 완료로 판단하지 않는다. `OCR → 등록 → 홈 → 내 약 → 상세 → DUR → 복약 기록` 전체 흐름을 같은 사용자 ID로 확인해야 한다.

---

## 9. 기존 Render와의 충돌 여부

서비스 이름과 URL이 다르면 Render 서비스 자체가 직접 충돌하지 않는다.

발생할 수 있는 문제는 다음 두 가지다.

1. 앱의 일부 약 요청이 기존 Render로 남아 데이터가 갈라지는 문제
2. 서로 다른 브랜치의 응답 필드가 달라 Flutter 화면이 기대한 값을 받지 못하는 문제

따라서 개인 Render 주소를 적용한 뒤에는 Flutter 코드에서 약 관련 요청이 모두 `ApiConfig.localFeatureBaseUrl`을 사용하는지 확인한다. 기존 Render 주소 자체를 바꾸는 `API_BASE_URL`은 건드리지 않는다.

---

## 10. 최종 통합 시 방향

개인 Render는 개인 기능 보관과 테스트를 위한 임시 서버다. 최종 제출 또는 팀 배포 전에는 다음 순서로 통합한다.

1. 최신 `main`을 받아 로그인·Polar·알림 변경을 확인한다.
2. `woong2`의 OCR·약 상세·DUR·복약 변경을 병합한다.
3. 충돌 시 약 관련 코드는 `woong2` 동작을 유지하고, 로그인·사용자·Polar·알림은 팀원 변경을 유지한다.
4. 전체 테스트 후 통합 배포 브랜치를 만든다.
5. 최종 Render 하나를 통합 배포 브랜치에 연결한다.
6. 앱의 임시 `LOCAL_API_BASE_URL` 분기를 제거하거나 최종 서버 주소로 통일한다.
7. 개인 Render는 테스트 종료 후 자동 배포를 끄거나 서비스를 정리한다.

최종 목표는 서버 두 개를 계속 운영하는 것이 아니라, 개인 Render에서 기능을 안전하게 확인한 뒤 검증된 코드를 팀의 최종 서버로 옮기는 것이다.
