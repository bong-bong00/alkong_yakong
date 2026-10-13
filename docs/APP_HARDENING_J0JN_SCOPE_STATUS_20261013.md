# APP_HARDENING_ROLLOUT — `j0jn` 담당 요구사항과 현재 상태

> **10월 13일 중간 기록 보관본.** 인증 미구현 등의 아래 표시는 당시 상태다. 두 서버 인증과 Flutter 세션 연결은 이후 구현했다. 현재 결과는 [10월 14일 인수인계](APP_HARDENING_ROLLOUT_HANDOFF_20261014.md)에 분리해 기록했다.

기준일: 2026-10-13

원본: 팀원 전달 `APP_HARDENING_ROLLOUT.md`

대상: 약 데이터 Render `https://alkong-yakong-j0jn.onrender.com`

상태: **로컬 코드 일부 수정. 커밋·푸시·Render 배포 및 운영 DB 변경 없음.**

## 먼저 바로잡을 점

- 원본 문서는 제목 그대로 **앱 전체와 두 Render 서버의 공동 배포 요구**다. 아래는 그중 `j0jn`이 담당하거나 `j0jn`에서 반드시 검증할 부분만 추렸다.
- 현 Flutter 코드의 `ApiConfig.localFeatureBaseUrl`은 `j0jn`, 기본 `ApiClient()`의 `ApiConfig.baseUrl`은 Android에서 `https://alkong-yakong.onrender.com`이다. 따라서 약·OCR·DUR·복약은 주로 `j0jn`에, 로그인·보호자 연결·심박 저장은 기본적으로 다른 Render에 요청한다. 실제 운영 배포 설정은 아직 확인하지 않았다.
- 내가 앞서 말한 **“메인 Render가 토큰을 발급한다”는 확정 요구가 아니다.** 원본은 같은 비밀값과 `AUTH_AUTHORITY_BASE_URL`을 요구하지만, 토큰 형식·발급/검증 계약은 적지 않았다. 현재 로그인 코드도 토큰을 발급하지 않는다. 이를 임의로 확정하지 않는다.
- 같은 저장소의 Python 코드가 두 Render에서 실행될 수 있다. **코드 파일을 수정했다고 그 변경이 `j0jn`에만 적용되는 것은 아니다.** 아래의 “로컬 완료”는 운영 서버 반영을 뜻하지 않는다.

## 1. `j0jn`에서 해야 할 일 — 원본 요구와 진행 상태

`[x]`는 **로컬 코드/테스트 수준에서만** 확인된 항목이다. `[ ]`는 미구현 또는 운영 미확인이다.

### A. 약 데이터 DB와 기록 보존 — 원본 「데이터 보존」

- [x] `prescriptions.registration_revision` 열을 기본값 1로 추가했다. 기존 처방전 행을 지우지 않는 열 추가 방식이다 (`init_db.py`).
- [ ] **정정 등록 시 revision을 언제 증가시킬지** 결정하고 구현한다. 지금은 열만 있으며 증가·충돌 방지 계약은 없다. 같은 요청의 재시도와 실제 정정을 구별해야 한다.
- [x] 정확히 같은 처방전 재등록 시 기존 처방전 ID를 재사용하고, 복약 로그가 연결된 과거 일정을 삭제하지 않도록 로컬 코드를 수정했다 (`app/services/prescription_service.py`).
- [ ] `j0jn` 운영 DB 사본에서 기존 처방전·처방 항목·일정·복약 로그의 ID/건수가 보존되는지, 마이그레이션을 두 번 돌려도 안전한지 검증한다. 현재 운영 DB 사본 검증은 하지 않았다.
- [ ] 실제 `j0jn` 영구 DB와 WAL을 일관되게 백업하고 복원 가능성을 확인한 뒤 적용한다. **운영 DB 백업·변경은 아직 없다.**

### B. `j0jn` 복약 완료·취소 — 원본 「데이터 보존」「배포와 확인」

- [x] 복약 취소 시 기존 TAKEN 로그를 지우지 않고 `CANCELLED` 로그를 추가하며, 일정 상태를 `PENDING`으로 돌리는 서버 경로를 로컬에서 구현했다 (`app/routes/medication_logs.py`, `app/services/medication_service.py`).
- [x] 취소 후 재복용 가능하게 하고, 오늘 홈·복약 이력 등에서 과거 TAKEN을 현재 완료 상태로 오인하지 않도록 관련 조회를 수정했다. 여러 약의 일괄 완료/취소는 추가 안전장치이며 원본 문서가 명시한 별도 기능은 아니다.
- [x] 임시 DB에서 완료→취소→재복용, 중복 취소, 일괄 요청의 부분 실패 방지를 테스트했다 (`test/test_hardening_records.py`).
- [ ] **로그인한 본인만** 자신의 일정을 완료·취소하도록 요청자 인증/권한을 붙인다. 지금 API는 `user_id`만 받으며 인증이 없다. 인증 전에는 운영 배포하지 않는다.
- [ ] 실제 두 계정·실기기에서 완료→취소→재조회와 기존 기록 보존을 확인한다.

### C. `j0jn` 접근 제한과 필수 설정 — 원본 「두 서버의 필수 설정」「배포와 확인」

- [ ] `j0jn` Render에 `SERVICE_ROLE=medication`, `AUTH_AUTHORITY_BASE_URL=https://alkong-yakong.onrender.com`, `AUTH_ENFORCED=true`, 영구 디스크의 `ALKONGYAKONG_DB_PATH`를 설정/검증한다.
- [ ] 두 Render가 공유하는 **32자 이상 비밀값** `ALKONGYAKONG_AUTH_SECRET`을 Render 환경변수로만 설정한다. 값은 코드·문서·채팅·로그에 넣지 않는다. 현재 설정 여부도 확인하지 않았다.
- [ ] 필수 설정 누락 시 `j0jn`이 무인증으로 요청을 받지 않도록 기동/요청 차단을 구현한다. 현재 `app/core/config.py`·`app/main.py`에는 이 인증 강제가 없다.
- [ ] `j0jn`의 약 목록·상세·OCR/처방전·DUR·복약/기록 API에서 **요청한 사용자 ID가 허용된 대상인지** 검증한다. URL이나 본문 ID만 바꿔 타인 기록을 볼 수 없어야 한다.
- [ ] 메인 서버가 `j0jn`에 보내는 AI 약사 약 목록/DUR 요청도 인증한다 (`app/services/medication_feature_dur_client.py`의 호출 경로). 환자 앱 요청과 서버 간 요청의 허용 범위를 구별한다.
- [ ] 보호자의 `j0jn` 약 조회는 **환자가 수락한 연결에만** 허용한다. 현재 보호자 연결은 앱에서 기본적으로 다른 Render에 요청하므로, `j0jn`이 수락 상태를 어떻게 검증할지 두 서버 간 계약이 필요하다. 전화번호 일치만으로 허용하지 않는다.
- [ ] 메인 서버/앱과 인증 형식을 먼저 합의한 뒤 함께 전환한다. `j0jn`만 먼저 `AUTH_ENFORCED=true`로 배포하면 현재 앱의 무인증 요청이 막힌다.

### D. `j0jn` 테스트와 배포 — 원본 「테스트」「배포와 확인」

- [x] Python 테스트가 프로젝트 원본 DB 대신 임시 DB를 쓰도록 공통 격리를 추가했다 (`conftest.py`). 식약처 전체 자료가 필요한 테스트 2개는 자료와 `RUN_MFDS_DATASET_TESTS=1`이 있을 때만 실행하도록 표시했다 (`test/test_mfds_drug_permission.py`). 건너뛴 검사는 통과로 세지 않는다.
- [x] 최종 선별 서버 테스트 60개가 통과했다. 전체 Python 실행은 **661개 통과·2개 건너뜀·4개 실패**였고, 4개 실패의 기존 코드 대비 발생 시점은 아직 확정하지 않았다.
- [ ] `j0jn` 실제 DB 사본에서 초기화 전후의 행 수·ID·무결성과, 인증 실패/타인 조회/보호자 미수락의 거부 동작을 검증한다.
- [ ] 두 서버와 새 앱의 전환 시점을 맞춰 배포하고 `j0jn`의 실제 배포 커밋·health·핵심 API 응답을 확인한다. **현재 `j0jn` 배포 없음.**

## 2. 원본에는 있지만 `j0jn` 단독 작업으로 완료할 수 없는 항목

| 원본 요구 | 현재 코드에서 확인한 주 요청 경로 | `j0jn` 담당 범위 |
|---|---|---|
| 심박 `client_request_id` 중복 방지 | Flutter의 심박 전송은 기본 `ApiClient()`를 사용하므로 기본 URL은 다른 Render | 공용 Python DB/저장 코드는 로컬 수정했지만, 실제 심박 저장 서버의 적용·검증은 별개다. `j0jn` 완료로 세지 않는다. |
| 보호자 전화번호 자동 연결 금지·환자 재수락 | `GuardianRepository`는 기본 `ApiClient()`를 사용하므로 기본 URL은 다른 Render | `j0jn`의 **약 데이터 공개 권한**은 수락된 보호자에게만 허용해야 한다. 연결 생성·수락 자체의 배포는 다른 서버와 조율한다. |
| 새 Flutter 설치·재로그인·오프라인 본인 캐시 | Flutter 앱 | `j0jn`에서 구현하는 화면 기능이 아니다. 인증 전환이 앱과 호환되는지만 함께 검증한다. |
| 보호자 화면 열린 동안 재조회, 푸시·문자·야간 소리 설정 제거 | Flutter 화면 | `j0jn` 서버 작업이 아니다. |
| 심박 60 미만/100 초과의 비진단적 안내 | 심박 저장/표시 경로 | `j0jn` 담당 여부를 서버별 실제 호출로 확인해야 한다. 응급 진단 기능을 새로 만드는 요구는 아니다. |

로컬에서 이미 수정한 공용 Python 파일 중 `app/services/biosignal_service.py`는 심박 저장, `app/routes/guardians.py`·`app/services/care_service.py`는 보호자 연결/조회에 해당한다. 이 파일들은 같은 저장소에 있지만 **현재 Flutter 기본 호출 경로상 다른 Render에서 주로 쓰인다.** `init_db.py`도 두 서버가 공유할 수 있으므로 어느 운영 DB에 반영됐다고 간주하면 안 된다. 이 변경은 아직 어느 Render에도 배포되지 않았다.

## 3. 내가 이미 손댄 Flutter 파일 — `j0jn` 작업과 분리

아래 변경은 **모두 로컬 작업 트리에만 있고 커밋·푸시되지 않았다.** 이를 `j0jn` 서버 완료 항목으로 세지 않는다. 범위 정리 전 임의로 삭제하지 않는다.

- 복약 서버 API 연결·화면 오류 처리: `lib/features/medication/application/medication_controller.dart`, `lib/features/dashboard/presentation/screens/patient_home_screen.dart`, `lib/features/easy_flow/presentation/easy_dose_flow.dart`, `lib/features/medication/presentation/screens/dose_done_screen.dart`, `lib/features/medication/presentation/widgets/dose_guard_sheets.dart`, `test/medication_flow_test.dart`.
- 심박 요청 ID 전송: `lib/core/network/client_request_id.dart`, `lib/features/biosignal/application/heart_sensor.dart`, `lib/features/biosignal/presentation/screens/biosignal_screen.dart`, `lib/features/dashboard/presentation/screens/biosignal_live_screen.dart`. 이 경로는 기본적으로 다른 Render로 요청한다.
- 보호자 화면 동작·문구: `lib/features/dashboard/presentation/screens/guardian_home_screen.dart`, `lib/features/guardian/presentation/screens/guardian_alert_prefs_screen.dart`. `j0jn` 서버의 직접 수정 사항이 아니다.
- 로컬 선별 Flutter 테스트 43개 통과. **인증 토큰 저장·전송, 재로그인, 오프라인 본인 캐시는 아직 구현하지 않았다.**

## 4. 현재 작업물의 결론

- `j0jn`에서 필요한 **DB/복약 보존의 일부**만 로컬에서 구현·검증했다.
- `j0jn`의 가장 중요한 **인증 강제·타인 데이터 차단·서버 간 인증·운영 DB 백업·Render 배포는 아직 하지 않았다.** 지금 변경분을 배포 가능한 완성본으로 부르지 않는다.
- 원본 문서의 다른 서버/Flutter 요구까지 내가 앞서 한꺼번에 진행한 것은 범위 판단의 오류였다. 이후 `j0jn` 작업과 타 담당 작업을 분리하고, 두 서버의 인증 계약이 확정되기 전에는 운영 인증을 한쪽에만 켜지 않는다.
