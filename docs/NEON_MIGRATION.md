# 하나의 Neon DB로 이전하기 (운영 적용 전 준비)

## 현재 구조를 유지하는 통합

- Render 서버 두 개는 유지한다. 앱 화면·약사·센서 API 흐름은 그대로다.
- 하나의 Neon 데이터베이스 안에 `alkong_main`, `alkong_medication` 두 스키마를 둔다.
- 같은 이름의 테이블·같은 숫자 ID가 서로 덮어써지지 않는다. 사용자를 임의 병합하지 않는다.
- 스키마 분리는 이름/ID 충돌을 막는 구조이지 자체적인 권한 격리는 아니다. 같은 DB 계정을
  양쪽 서버에 쓰면 그 계정의 DB 권한은 공유된다. 공개 Data API/Neon Auth를 활성화하지 않는다.
- 본인/보호자 인증과 두 서버 간 권한 확인은 기존 통합 코드 그대로 유지한다.
- 식약처 원본 및 쉬운 분류용 별도 SQLite 캐시는 사용자 DB가 아니므로 이번 이전에서 제외한다.
- 기본 저장소는 SQLite다. Neon URL을 넣었다는 이유만으로 운영 저장소를 전환하지 않는다.

## 먼저 필요한 것

1. 실제 메인·약 서버의 WAL 포함 SQLite 백업 두 개를 확보한다. 로컬 시연 DB로 대체하지 않는다.
2. Neon 무료 프로젝트를 만들고 DB 연결 URL을 로컬 `.env`의 `NEON_DATABASE_URL`에 저장한다.
   접속 비밀번호·인증 비밀값을 Git·채팅·스크린샷에 공개하지 않는다. 유료 전환은 하지 않는다.
3. 용량/무료 사용량, 환자 정보의 저장 위치·접근 권한을 담당자가 확인한다.
4. 이전 동안 두 서버의 쓰기를 중지하고 최신 백업을 확보한다.

## 안전한 검사와 이전

한쪽 백업만 확보된 단계에서는 아래 검사로 무결성, 신규 열, 유일성 제약 충돌과
미확인 테이블을 확인할 수 있다. 개인정보 행은 출력하지 않으며 네트워크에 접속하지 않는다.

```powershell
.venv/Scripts/python.exe scripts/audit_sqlite_backup.py C:/backups/main.db
```

2026-10-14 메인 운영 스냅샷 검사에서는 무결성/외래키 검사와 신규 유일성 제약 검사가 통과했다.
다만 `legacy_*_20260614222707` 테이블 6개가 존재한다. 기본 실행은 이를 버리지 않고 중단한다.
검토한 이 6개 테이블에 한해서 `--preserve-reviewed-legacy` 옵션으로 보존을 선택할 수 있다.
이 경우 `alkong_main_archive`/`alkong_medication_archive` 스키마의 `sqlite_tables`와
`sqlite_rows`에 원래 DDL·열 이름·행 순서·값을 보관한다. 원래 DDL은 실행하지 않는다.
INTEGER/TEXT/REAL/BLOB/NULL 자료형을 구분하고 실수는 hex, BLOB은 base64로 보존하여
복원 가능한 표현을 만든다. 전체 행과 메타데이터·건수·해시를 대조한 후에만 커밋한다.
현재 앱 테이블과 과거 사용자를 자동 병합하지 않는다. 새로 발견된 다른 테이블·뷰·활성
트리거는 여전히 이전을 중단한다. 보존 영역에 기존 테이블이 있으면 덮어쓰지 않는다.
누락 열은 `guardians.consent_verified_at`, `prescriptions.registration_revision`,
`heart_rate_logs.client_request_id`다. 과거 보호자 동의를 임의로 검증 완료 처리하지 않는다.
이 스냅샷은 서비스 쓰기를 중지하지 않은 시점 백업이며 최종 전환 시점 백업이 아니다.
약 서버 API 추출 자료는 전체 SQLite 스냅샷으로 간주하지 않는다. 누락 항목과 재구성 방식을
검토하기 전에는 빈 약 서버 DB를 대신 넣어 실제 통합을 수행하지 않는다.

가장 먼저 아래처럼 검사한다. 기본 실행은 로컬 백업 사본만 읽으며 Neon에 접속하지 않는다.
아래 경로는 예시이며 실제 운영 백업의 경로로 바꿔야 한다.

```powershell
.venv/Scripts/python.exe scripts/migrate_neon.py --main-backup C:/backups/main.db --medication-backup C:/backups/medication.db
```

- 두 백업의 무결성·외래키·테이블·메인 계정과 약 기록 사용자 ID 일치를 확인한다.
- 미확인 테이블/열은 임의로 버리지 않는다. 연결되지 않은 사용자 ID는 추측하지 않고 이전을 중단한다.
- 양쪽의 동일한 처방전 번호/숫자 ID는 각각의 스키마에 보존한다.
- 승인한 실제 백업이고 목적지 스키마가 비어 있는 경우에만 다음을 실행한다.

```powershell
.venv/Scripts/python.exe scripts/migrate_neon.py --main-backup C:/backups/main.db --medication-backup C:/backups/medication.db --apply --confirm-backups
```

검토한 과거 테이블을 포함하는 운영 백업에는 dry-run과 apply 명령 모두에
`--preserve-reviewed-legacy`를 추가한다. 이 옵션은 실제 이전 승인이나 누락된 약 서버
데이터를 대신하지 않는다. 현재 확보한 메인 백업은 과거 6개 테이블의 총 58행이
자료형 구분 직렬화·역직렬화 검사에서 원본과 같음을 확인했다. 실제 PostgreSQL
보존 영역으로 복사하는 검증은 별도 테스트 DB가 확보된 뒤 수행해야 한다.

두 스키마를 한 트랜잭션에서 복사하고 모든 원본 열의 건수·내용 해시를 비교한다.
중간 오류/불일치 시 전체 롤백한다. 기존 Neon 데이터는 덮어쓰거나 삭제하지 않는다.
동일 명령을 재실행해 중복 복사하지 않도록 이미 데이터가 있는 목적지는 거부한다.
기존 SQLite 백업은 별도로 계속 보관하고 이전 완료만으로 원본을 삭제하지 않는다.

## 두 Render 서버 설정

두 서버 모두 아래를 설정하되 같은 Neon DB를 가리켜야 한다.
Neon 접속은 TLS 인증서 검증을 사용한다. Neon 트랜잭션 풀러도 스키마를 혼동하지 않도록
매 트랜잭션에 역할별 search_path를 설정한다.

```text
ALKONGYAKONG_DATABASE_BACKEND=postgresql
NEON_DATABASE_URL=<비밀 연결 URL>
AUTH_ENFORCED=true
ALKONGYAKONG_AUTH_SECRET=<두 서버의 동일한 32자 이상 비밀값>
```

- 메인: `SERVICE_ROLE=main`, `MEDICATION_FEATURE_BASE_URL=<약 서버 URL>`
- 약 서버: `SERVICE_ROLE=medication`, `AUTH_AUTHORITY_BASE_URL=<메인 URL>`
- PostgreSQL 모드에서는 사용자 DB용 Render 영구 디스크/SQLite 경로가 필요하지 않다.
- 기존 동의 표식이 없던 보호자 연결은 보안 마이그레이션에 따라 재수락이 필요할 수 있다.
- 둘 다 같은 코드로 배포하고 새 앱 재로그인 후 처방전·복약 완료/취소·센서·보호자 조회를 확인한다.
- `/health`는 역할별 DB 이름만 표시하며 URL/비밀번호를 공개하지 않는다.

## 검증 구분

비밀번호를 출력하지 않는 연결·목적지 스키마 점검은 다음 명령으로 수행한다.
읽기 전용 트랜잭션을 사용하며 테이블을 생성하거나 데이터를 쓰지 않는다.

```powershell
.venv/Scripts/python.exe scripts/check_neon_readiness.py
```

SQLite 회귀 테스트, SQL 변환 및 백업 검사 테스트는 로컬에서 가능하다.
선택 검사에는 `pglast`(PostgreSQL 문법 파서)를 사용한다.
실제 PostgreSQL 검사는 별도의 검증 DB URL을 `NEON_TEST_DATABASE_URL`에 설정해야 한다.
검사마다 임의의 `alkong_test_<랜덤>` 스키마만 만들고 제거한다. 운영 스키마는 제거하지 않는다.
실제 Neon 검사를 건너뛴 결과를 운영 DB 통합/성능 검증 완료로 보고하지 않는다.

## 운영 롤백

실패 시 새 DB에서 계속 쓰지 않는다. 유지한 SQLite 백업과 이전 앱/서버 코드를 기준으로
담당자가 복구한다. Neon에서 새로 생긴 기록을 누락시키는 무조건적인 SQLite 복귀는 금지한다.
