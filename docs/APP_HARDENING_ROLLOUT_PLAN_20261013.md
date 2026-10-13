# 알콩약콩 앱 보완: 코드 근거 기반 수정·배포 체크리스트

> **이 문서는 10월 13일의 착수 당시 계획/중간 기록이다.** 아래의 미구현 표시와 당시 테스트 수는 최신 상태가 아니다. 10월 14일 구현·전체 검증 결과와 실제 Render 배포 차단 조건은 [최신 인수인계](APP_HARDENING_ROLLOUT_HANDOFF_20261014.md)를 기준으로 확인한다.

기준: 2026-10-13, woong2에 origin/main 5319764 반영 후 코드

요구 출처: 팀원 전달 APP_HARDENING_ROLLOUT.md

상태: **로컬 1차 수정 진행 중. 운영 DB 변경·Render 배포는 하지 않음.**

표시 규칙: [x]는 해당 문장에 적힌 로컬 확인/작업만 완료했다는 뜻이다. [ ]는 구현 또는 검증 전이다. 운영 서버의 실제 설정·DB 상태는 코드를 읽는 것만으로 확인할 수 없다.

## 현재 진행 상태 (로컬 코드에만 적용)

- [x] 복약 완료/취소의 서버 일괄 처리 API와 CANCELLED 감사 기록, Flutter 취소의 서버 응답 확인을 추가했다. 임시 DB와 Flutter 대상 테스트에서 확인했다.
- [x] 심박 client_request_id 열·유일 인덱스·재시도 중복 방지와 앱 전송 ID를 추가했다. 기존 심박 행의 ID는 비워 둔다.
- [x] 처방전 재등록 시 과거 기록이 연결된 일정을 삭제하지 않도록 변경하고 보존 테스트를 추가했다. registration_revision 열은 추가했지만 **증가 정책은 아직 구현하지 않았다.**
- [x] 전화번호만 같은 보호자의 자동 연결을 제거했다. 기존 연락처로 연결을 요청하면 환자 재수락 전에는 조회되지 않는다. 사본 DB 마이그레이션에서는 과거 보호자 요청 후 환자가 수락한 행은 유지하고, 환자 등록 연락처가 나중에 전화번호만으로 자동 연결됐을 수 있는 행만 PENDING으로 전환한다. 운영 DB에서는 아직 실행하지 않았다.
- [x] 보호자 설정의 미지원 문자/푸시/야간 소리 스위치를 제거하고 현재 지원 범위를 안내한다. 돌보는 분 화면이 열려 있고 앱이 전경일 때만 30초 간격으로 다시 조회하며 화면을 닫으면 타이머를 해제한다.
- [x] Python 테스트 기본 DB를 임시 위치로 격리하고 식약처 전체 자료 테스트 2개를 별도 실행하도록 표시했다. 최종 선별 Python 60개와 Flutter 복약·Polar·프로필 테스트 43개가 통과했다. 한 약의 일정 ID가 빠졌을 때 일부만 복용 완료 처리되지 않는 테스트도 포함했다.
- [ ] 사용자 토큰, 두 Render의 인증 강제·권한 검증, Flutter의 안전한 세션 저장/재로그인, 오프라인 본인 캐시, 운영 DB 백업·배포·실기기 검증은 아직 하지 않았다. **현재 변경분은 운영 배포 금지.**

검증 참고: 전체 Python 테스트(test 및 tests)는 661개 통과, 전체 식약처 자료 2개 건너뜀, 약 상세/문자열 검사 4개 실패였다. 실패 4개의 기존 코드 대비 발생 시점은 확정하지 않았으며 배포 전 별도 조사 대상이다. 이후 최종 선별 Python 60개와 Flutter 43개는 통과했다. Flutter 전체 분석은 테스트 파일의 미사용 import 경고 2개를 보고했다.

로컬 DB 주의: 격리 전 기존 처방전 테스트가 프로젝트의 추적 DB 파일에 접근했고 손상 오류가 나타났다. 손상본은 임시 위치에 보관하고, 작업 시작 시 깨끗했던 Git 버전으로 **그 DB 파일 하나만** 복원했다. 복원본의 PRAGMA integrity_check는 ok이며 이후 테스트는 임시 DB에서만 실행했다. Render DB는 변경하지 않았다.

## 0. 작업 시작 전 코드 확인 결과

- [x] 원격 main의 최근 3개 커밋을 woong2에 fast-forward 반영했다. 홈의 뜻하지 않은 약 도착 화면 제거와 2026-10-06 시연 점심 상태 제한이 주요 변경이다. 앱 보완 요구는 이 커밋에 없다.
- [x] app/routes/users.py의 로그인은 사용자 정보만 반환한다. lib/core/session/auth_session.dart는 로그인 여부·역할·사용자 ID를 로컬에 저장하고, lib/core/network/api_client.dart는 Authorization 헤더를 보내지 않는다. 로컬 사용자 ID는 서버 접근 권한의 증거가 아니다.
- [x] app/main.py는 같은 라우트들을 모두 등록한다. app/core/config.py에는 MEDICATION_FEATURE_BASE_URL만 있고 AUTH_ENFORCED, SERVICE_ROLE, AUTH_AUTHORITY_BASE_URL, ALKONGYAKONG_AUTH_SECRET 구현은 없다.
- [x] app/services/medication_feature_dur_client.py의 메인→약 데이터 서버 GET/POST에는 현재 별도 인증이 없다. 새 인증을 켜면 이 내부 호출도 함께 바꿔야 AI 약사의 약 목록/DUR 조회가 유지된다.
- [x] app/services/medication_user_service.py는 오늘 약 조회 중 약 데이터 서버에 사용자 행을 INSERT OR IGNORE로 만들 수 있다. 새 인증에서는 임의의 URL 사용자 ID로 계정이 생기거나 다른 사용자 데이터를 조회하는 경로가 되지 않게 재설계해야 한다.
- [x] app/services/care_service.py는 보호자 전화번호가 같으면 기존 연결의 guardian_user_id를 조회 중 채운다. app/routes/guardians.py의 환자 직접 등록은 연결을 곧바로 ACCEPTED로 만든다. 요청 수락·해제 라우트에도 호출자 신원 검증이 없다.
- [x] init_db.py에는 registration_fingerprint는 있으나 registration_revision과 heart_rate_logs.client_request_id는 없다. initialize_database()는 열 추가 외에 구형 테이블 이름 변경, 시드/비활성화, OCR 임시 행 정리도 수행한다. 따라서 기존 DB 사본에서 **전체 기동 효과**를 먼저 검증해야 한다.
- [x] app/services/prescription_service.py는 정확히 같은 fingerprint면 기존 처방전 ID를 재사용한다. 그러나 중복 재등록과 동일 약의 새 등록에서 기존 medication_schedules를 삭제한다. 과거 일정이 사라지고 medication_logs.schedule_id가 NULL이 될 수 있으므로 “ID만 보존”으로 기록 보존을 완료했다고 볼 수 없다.
- [x] app/services/medication_service.py는 완료 시 TAKEN 로그를 추가한다. lib/features/medication/application/medication_controller.dart의 undo()는 서버 호출 없이 화면 상태만 되돌린다. 한 시간대 여러 약의 완료 요청도 약마다 따로 전송하므로 중간 실패 시 일부만 저장될 수 있다.
- [x] app/services/biosignal_service.py는 심박 저장 요청마다 새 행을 만든다. Flutter에서 heart_sensor.dart, biosignal_live_screen.dart, biosignal_screen.dart가 심박 저장을 호출한다.
- [x] lib/features/guardian/presentation/screens/guardian_alert_prefs_screen.dart에는 현재 미지원 범위인 문자·야간 소리 제어 스위치가 있다. 보호자 목록 화면에는 열린 동안의 주기 조회가 확인되지 않는다.
- [x] RUN_MFDS_DATASET_TESTS 분기 코드는 현재 검색 범위에 없다. 일부 Python 테스트는 임시 DB를 쓰지만 전체 테스트와 기동 부작용의 안전성은 별도 전수 확인이 필요하다.

## 1. 작업 착수 전에 합의할 설계

- [ ] **두 DB의 소유권을 확정:** 메인 Render가 계정·인증의 기준인지, 약 데이터 Render가 환자 약·일정의 기준인지, 동일 UUID를 어떻게 검증/동기화하는지 문서화한다. 현재 Flutter는 ApiConfig.baseUrl과 localFeatureBaseUrl로 두 서버를 직접 호출한다.
- [ ] **권한표를 확정:** 환자 본인, 수락된 보호자, 미수락 보호자, 내부 서버, 운영자, 미로그인 사용자별로 읽기/쓰기 가능한 API를 표로 작성한다. health, 가입·로그인과 공개 약 검색을 제외할지 명시한다. 보호자의 대리 처방전 등록·복약 수정 허용 여부를 특히 정한다.
- [ ] **세션 정책을 확정:** 토큰 발급 서버, 수명, 만료/재발급, 로그아웃 후 폐기, 계정 탈퇴·보호자 연결 해제 시 권한 반영 시간, 앱 업데이트·재로그인 안내를 정한다. 구버전 앱은 토큰을 보내지 못하므로 새 운영 서버와 동시에 계속 사용될 수 없다.
- [ ] **처방전 ‘동일’의 정의를 확정:** 현재 fingerprint는 내용이 조금만 바뀌어도 새 처방전으로 본다. OCR 정정·재시도·진짜 재처방을 구별할 안정적인 처방전 ID/요청 ID와 revision 증가 규칙을 정한다. 다른 처방전을 이름·날짜가 비슷하다는 이유로 합치지 않는다.
- [ ] **복약 상태의 단일 기준을 확정:** medication_schedules.status를 현재 상태로, medication_logs를 변경 불가능한 사건 기록으로 사용할지 합의한다. TAKEN → CANCELLED → TAKEN 및 MISSED → TAKEN의 허용 범위와 알림/통계 처리 규칙을 정한다.
- [ ] **오프라인 보관 정책을 확정:** 어떤 건강정보를 사용자별로 저장할지, 보관 기간·기기 내 보호 방식·계정 전환/로그아웃/세션 만료 시 삭제 규칙을 정한다. 현재 시작 시 restorePersistedSession()이 서버 사용자 조회를 요구하므로 오프라인 동작은 별도 구현이 필요하다.

## 2. 운영 데이터 보존과 마이그레이션

- [ ] 두 Render의 실제 배포 커밋, 영구 디스크 마운트, ALKONGYAKONG_DB_PATH, DB 파일과 WAL 존재 여부를 **각각** 확인한다. 저장 경로가 영구 디스크인지 Render 설정에서 확인한다. 비밀값과 환자 데이터는 문서·채팅·로그에 남기지 않는다.
- [ ] 각 SQLite DB를 일관된 방법으로 별도 백업하고 복원 연습을 한다. 파일만 급히 복사해 WAL 변경분을 누락하지 않도록 SQLite 백업 절차를 사용한다. 사본에서 PRAGMA integrity_check, PRAGMA foreign_key_check, 주요 테이블 행 수·기존 ID를 확인한다.
- [ ] init_db.py의 TABLE_DEFINITIONS, ADDITIVE_COLUMNS, 인덱스에 기존 행을 유지하는 열 추가를 구현한다. prescriptions.registration_revision은 구행의 초기값과 증가 규칙을 정하고, heart_rate_logs.client_request_id는 과거 행에서 NULL을 허용한다.
- [ ] 심박 중복 방지는 (user_id, client_request_id)의 **NULL 제외 유일 인덱스**로 설계한다. 과거 데이터의 NULL은 건드리지 않고, 동일 ID·동일 내용 재시도는 기존 결과를 반환하며 동일 ID·상이한 내용은 충돌로 처리한다.
- [ ] 현재 initialize_database() 전체를 두 DB의 **복사본**에서 실행해 열 추가 외의 테이블 이름 변경, 시드, demo 비활성화, OCR 임시 행 정리가 실제 기존 데이터에 미치는 영향을 확인한다. 영향이 있으면 이번 보완과 분리하거나 무해한 마이그레이션 경로를 만든 뒤 배포한다.
- [ ] 마이그레이션 2회 실행, 배포 중 프로세스 재시작, 새 코드 후 구 코드 복귀 상황을 사본에서 시험한다. 실패 시 DB 백업 복구 기준과 코드 롤백 가능 범위를 미리 기록한다.

**통과 기준:** 계정·처방전·처방 항목·과거 일정·복약 로그·심박 로그의 기존 ID와 행이 유지되고, 두 번째 마이그레이션에서 중복/손상이 없다.

## 3. 두 서버의 인증과 접근 권한

- [ ] app/core/config.py에서 두 역할의 필수 환경변수를 읽고 유효성을 검사한다. 운영 환경은 빠진 secret·역할·필수 URL·영구 DB 경로에서 조용히 무인증으로 기동하지 않게 한다. 키 값은 코드, 응답, health, 로그에 넣지 않는다.
- [ ] app/routes/users.py 가입/로그인 응답을 세션 발급 계약에 맞춘다. 현재 로그인 응답은 UserResponse 하나이므로 Flutter의 UserRepository·가입 직후 startSession()도 함께 수정한다. 기존 비밀번호 없는/중복 전화번호 계정의 재로그인 방안은 별도 확인한다.
- [ ] app/main.py에 공통 신원 검증을 도입하되 라우트별 권한까지 확인한다. URL/body의 user_id가 토큰 주체와 같은지, 다른 환자에 접근한다면 수락된 보호자·허용 동작인지 검사한다. 인증 없이 접근 가능한 예외 라우트는 좁게 명시한다.
- [ ] app/routes/users.py, guardians.py, prescription.py, medication_logs.py, biosignal.py, dashboard.py, notifications.py, dur_analysis.py, drug_explain.py의 사용자 데이터/변경 경로를 전수 점검한다. /dur/sync, 테스트용 biosignal 라우트, 발표용 약 등록 라우트는 운영에서 내부/관리자 권한 또는 비노출 여부를 별도로 정한다.
- [ ] 약 데이터 서버는 메인 서버가 발급한 환자 신원을 검증하되, 임의 user_id만으로 ensure_medication_user()가 계정 행을 만들지 못하도록 한다. 필요한 신규 사용자 준비는 인증된 동기화 또는 명시적 provisioning 절차로 분리한다.
- [ ] 메인→약 데이터 서버의 load_remote_current_medicines()와 load_remote_combination_context()에도 서비스 전용 인증을 붙인다. 내부 서비스 권한은 환자 토큰과 구별하고 대상 사용자·허용 경로·만료를 제한한다. 팀원이 준 “같은 secret” 요구를 따르더라도 토큰의 목적/대상(audience)/권한(scope)을 섞지 않는다.
- [ ] 운영 역할별 라우트 노출과 실제 Flutter 호출 위치를 맞춘다. 단순히 SERVICE_ROLE만 추가해 라우트를 무조건 끄면 현재 두 서버를 직접 사용하는 화면이 깨질 수 있으므로, 호출 목록과 보호 대상을 확인하며 변경한다.
- [ ] 인증 실패 401, 권한 실패 403, 없는 자원 404의 응답을 일관되게 하고, 다른 환자 데이터의 존재 자체가 불필요하게 새지 않도록 한다. 같은 ID를 URL/body만 바꿔 조회·수정·삭제하는 음성 테스트를 모든 민감 라우트에 둔다.

**통과 기준:** 본인 허용 요청과 인증된 내부 호출만 성공하며, 미로그인·타인·미수락 보호자·잘못된 서버 토큰은 환자 약·심박·처방전·알림을 읽거나 바꾸지 못한다.

## 4. 보호자 연결의 동의 기반 전환

- [ ] app/services/care_service.py:linked_rows()의 전화번호 자동 연결/조회 중 DB 수정을 제거한다. 조회는 연결 상태를 바꾸지 않도록 한다.
- [ ] app/routes/guardians.py의 생성·요청·수락·삭제·목록·환자 현황에서 호출자 신원과 환자 소유권을 확인한다. 연결 수락은 **해당 환자 계정만** 가능하게 하고, 보호자에게는 수락된 환자의 허용된 범위만 보인다.
- [ ] 기존 guardian_user_id IS NULL인 전화번호-only 연결은 새 보호자 계정에 자동 공개하지 않는다. 현재 ACCEPTED로 저장된 과거 행도 안전한 재수락 대상으로 구분할 마이그레이션/표식이 필요한지 사본 DB에서 결정한다. 기존 연락처 기록은 지우지 않는다.
- [ ] app/services/medication_service.py:_store_guardian_missed_notifications()처럼 guardians.user_id만 보고 보호자 알림을 만드는 경로에도 수락된 연결·알림 동의 필터를 적용한다. 과거 알림의 노출/보존 정책도 확인한다.
- [ ] 두 실계정으로 요청→환자 수락→조회→연결 해제→즉시 조회 거부를 검증하고, 전화번호 재사용·같은 번호의 다른 계정·보호자 탈퇴 후 재가입 사례를 시험한다.

## 5. 처방전 재등록과 이력 보존

- [ ] app/services/prescription_service.py:_reactivate_duplicate_prescription()의 기존 일정 전체 삭제와 신규 등록 중 같은 약의 기존 일정 삭제를 먼저 재검토한다. 과거 TAKEN/MISSED 일정 및 연결된 로그는 지우지 않고, 새 처방의 현재/미래 일정과 중복되지 않도록 범위를 나눈다.
- [ ] 기존 medication_logs.schedule_id가 재등록 때문에 이미 NULL인 행의 개수를 사본에서 조사한다. 임의 복구하지 말고 원래 일정과 확실하게 연결할 수 있는지 검토한다.
- [ ] 같은 요청의 네트워크 재시도는 기존 처방전 ID/항목을 반환하고 일정·DUR 결과를 중복 생성하지 않게 한다. 수정 재등록은 명시된 기존 처방전 ID와 revision을 사용해 추적하고, 완전히 다른 처방은 새 ID로 둔다.
- [ ] fingerprint 유일 인덱스와 revision 갱신이 충돌하지 않도록 트랜잭션/경쟁 요청을 시험한다. OCR 인식 후 등록, 수동 등록, 기존 처방전 기록, 약 있는 날, 복약 달력, 내 약 목록이 모두 유지되는지 확인한다.

**통과 기준:** 동일 처방전 재시도·정정 후에도 기존 처방전 ID를 정책에 맞게 유지하고, 과거 복약 기록과 심박 연계가 줄거나 사라지지 않는다.

## 6. 복약 완료·취소의 서버 정합성

- [ ] app/models/schemas.py, app/routes/medication_logs.py, app/services/medication_service.py에 취소 계약을 추가한다. 인증된 사용자 소유 일정만 취소할 수 있고, 한 트랜잭션에서 CANCELLED 사건을 남긴 뒤 medication_schedules.status=PENDING으로 되돌린다. 이미 취소된 요청은 중복 로그를 만들지 않는다.
- [ ] mark_medication_taken()의 “과거 TAKEN 하나라도 있으면 중복” 판정을 최신 유효 상태 기준으로 바꾼다. 그래야 취소 후 재복용을 기록할 수 있다. mark_missed_medications()도 과거 TAKEN만 보고 영구 제외하지 않게 한다.
- [ ] 완료/취소/미복용 사건의 순서는 혼합 시간대 문자열 taken_at만 믿지 말고 단조 증가하는 로그 ID 또는 확정된 사건 순서로 판정한다. 감사 로그는 삭제하거나 TAKEN 행을 CANCELLED로 덮어쓰지 않는다.
- [ ] 현재 상태 소비처를 전수 수정한다: dashboard_service.py(최신 로그 CANCELLED를 현재 복용 상태로 오해하지 않기), medication_history_service.py, today_medication_service.py, care_service.py의 활동, biosignal_service.py의 복약-심박 연결, user_medicines_service.py의 마지막 복용 시각, 알림/달력/통계. 취소된 과거 TAKEN이 완료로 재계산되지 않아야 한다.
- [ ] Flutter medication_controller.dart:undo()를 비동기 서버 요청으로 바꾸고 성공 후에만 화면·알림 상태를 바꾼다. 호출하는 일반 홈, 쉬운 화면, 복약 완료 화면, 테스트의 undo() 호출부를 모두 await/오류 안내에 맞춘다.
- [ ] 한 시간대에 약이 여러 개인 _postTakenLogs()의 부분 성공 문제를 해결한다. 원자적 일괄 완료 API를 쓰거나 부분 성공 시 서버 재조회로 약별 상태를 그대로 표시하고 재시도만 수행한다. 화면이 “전부 완료”라고 거짓 표시하지 않게 한다.
- [ ] 복약 완료→취소→새로고침→재복용, 다른 기기 조회, 네트워크 타임아웃 뒤 재시도, 완료/취소 동시 요청을 시험한다. 보호자 화면과 9월 시연 기록 등 기존 과거 이력도 비교한다.

**화면 예시:** 취소가 서버에 저장되면 오늘 홈과 기록에서 해당 약은 “아직 복용하지 않았어요”로 보인다. 저장 실패면 “취소하지 못했어요. 다시 시도해 주세요”를 보여주고 완료 상태를 유지한다.

## 7. 심박 저장 재시도 중복 방지

- [ ] HeartRateCreate와 save_heart_rate()에 client_request_id를 연결한다. 서버는 저장 후 응답이 끊겨 같은 ID로 재시도해도 같은 heart_rate_log_id를 돌려준다. 같은 ID인데 BPM/측정시각/문맥이 다르면 조용히 기존 값으로 덮지 않는다.
- [ ] Flutter의 세 심박 전송 경로(heart_sensor.dart, biosignal_live_screen.dart, biosignal_screen.dart)에서 **측정 1회당 ID 1개**를 만들고 재시도 동안 유지한다. 새 측정일 때만 새 ID를 만든다.
- [ ] 심박 사전·사후 비교와 보호자 최신 심박 화면의 개수/시각이 재시도 때문에 달라지지 않는지 시험한다. 과거 로그의 NULL ID는 그대로 유지한다.

## 8. 앱 세션·오프라인·알림 표시

- [ ] ApiClient에서 메인/약 데이터 서버 모두에 유효 토큰을 보내되 가입·로그인 같은 예외 요청은 분리한다. 401/403/네트워크 실패를 구별한다. 비밀 토큰을 SharedPreferences 평문·디버그 로그에 남기지 않는 기기 저장 방식을 사용한다.
- [ ] AuthSession, UserRepository, session_actions.dart, 가입/로그인 화면을 새 응답 계약에 맞춘다. 현재 저장된 isLoggedIn=true만으로 새 서버의 보호 화면에 진입시키지 않는다. 구 세션은 재로그인을 안내하고 계정 전환 시 약·보호자·OCR 임시 상태·캐시를 지운다.
- [ ] 오프라인에서 유효한 저장 세션의 본인 캐시만 볼 수 있게 하며, 만료·로그아웃·계정 전환 후 다른 사람 데이터가 남지 않게 한다. 현재 서버 확인에 실패하면 세션 복원이 중단되는 동작과 구분해 설계한다. 저장/취소/등록 요청은 응답이 없으면 완료로 표시하지 않는다.
- [ ] 보호자 화면이 열린 동안만 제한된 간격으로 재조회하고 닫히면 타이머를 해제한다. 백그라운드 푸시·문자·야간 소리 제어를 구현한 것처럼 약속하지 않는다.
- [ ] guardian_alert_prefs_screen.dart의 미지원 문자·야간 소리·보호자 소리/푸시 약속을 실제 기능에 맞게 정리한다. 환자 휴대폰의 로컬 복약 알림은 유지한다.
- [ ] 심박 60 미만/100 초과 안내는 측정 범위 이탈 기록으로 표현하고, 진단·응급 판정처럼 보이는 문구가 앱·서버에 없는지 점검한다.

## 9. 안전 검증과 배포 순서

- [ ] 먼저 테스트 전수 목록을 만들고 모든 Python 테스트의 DB 사용 경로를 감사한다. app.database.DB_PATH, init_db.DB_PATH 및 별도 식약처 캐시 DB가 운영/프로젝트 원본을 가리키지 않도록 임시 사본으로 고정한다. 실제 공식 데이터가 필요한 테스트 2개는 정확히 식별한 뒤 RUN_MFDS_DATASET_TESTS=1 분기를 만든다. 미실행은 SKIP으로 기록한다.
- [ ] 자동 테스트: 마이그레이션 2회, 기존 데이터 보존, 인증·인가 경계, 보호자 재수락, 처방전 재시도/정정, 복약 완료→취소→재복용, 여러 약의 부분 실패, 심박 동일 요청 재시도, Flutter 401/403·오프라인·계정 전환을 추가한다. 기존 OCR·약 자세히·DUR·오늘 홈·Polar 테스트도 회귀 검사한다.
- [ ] 운영과 분리된 환경에서 **두 서버와 새 Flutter 앱을 함께** 시험한다. 한쪽만 새 인증 코드/설정인 상황에서 어떤 요청이 실패하는지 확인한다. 운영 배포 시에는 두 DB 백업과 복구 준비 후 짧은 점검 창에서 두 서버를 호환 버전으로 전환하고, 필수 환경변수를 각 역할에 맞게 설정한다. secret 값은 Render 환경에만 저장한다.
- [ ] 실제 기기 두 계정으로 환자/수락된 보호자 허용 조회, 미연결·미로그인 거부, 복약 완료→취소→재조회, 동일 처방전 재등록, 심박 중복 방지, 오프라인을 확인한다. 각 서버의 배포 커밋·health·실제 API 응답을 기록한다.
- [ ] 실패 시 앱/서버 코드 롤백이 새 DB 열과 호환되는지 먼저 확인한다. 운영 DB를 무조건 덮어쓰거나 기존 기록을 삭제하지 않는다. 배포 결과와 남은 미실행 검사·위험을 따로 보고한다.

**최종 통과 기준:** 기존 계정·처방전·복약·심박 데이터가 유지되고, 새 앱과 두 Render 서버에서 핵심 흐름이 작동하며, 무인증·타인·미수락 보호자의 데이터 접근이 거부된다. 로컬 테스트만으로 운영 반영 완료라고 쓰지 않는다.

## 10. 아직 하지 않은 일

- [x] 현재 코드와 main 반영 상태를 읽고 수정 대상·연쇄 영향을 정리했으며 위의 로컬 1차 구현과 선별 테스트를 수행했다.
- [ ] 인증·인가 전체 구현, 실제 Render 설정 확인, 운영 DB 백업·마이그레이션, 커밋·푸시·서버 배포는 아직 하지 않았다.
