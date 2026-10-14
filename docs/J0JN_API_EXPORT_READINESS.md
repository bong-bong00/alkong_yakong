# j0jn 기존 API 자료 추출 가능성 확인 (2026-10-14)

동료가 전달한 실제 추출 자료의 후속 검증은
[J0JN_HANDOFF_AUDIT_20261014.md](J0JN_HANDOFF_AUDIT_20261014.md)를 참고한다.
아래 내용은 자료 수령 전의 API 목록 점검 기록이다.

재배포/재시작/플랜 변경 없이 기존 `/openapi.json`만 GET으로 확인했다(HTTP 200).
환자 행을 조회·저장하거나 서버 데이터를 변경하지 않았다.

## 문서에 존재하는 조회 경로

- GET `/api/v1/users/{user_id}/prescriptions`: 처방전 조회
- GET `/api/v1/users/{user_id}/medicines`: 등록 약 조회
- GET `/api/v1/users/{user_id}/medicines/{medicine_code}`: 개별 등록 약 상세
- GET `/api/v1/users/{user_id}/prescriptions/{prescription_id}/schedule-days`: 처방전 복용일 조회
- GET `/api/v1/users/{user_id}/medication-history`: 복용 기록 조회
- GET `/api/v1/users/{user_id}/medication-calendar`: 달력 조회
- GET `/api/v1/users/{user_id}/today-medicines`: 오늘 약 조회
- GET `/api/v1/users/{user_id}/dur/latest`: 최근 DUR 결과 조회

위 API 존재는 문서로 확인했지만, 전체 원본 열·ID·과거 기간·삭제/취소 이력 등을
모두 반환하는지는 아직 검증하지 않았다. 요약 응답을 원본 테이블 백업으로 간주하지 않는다.
인증 스키마가 OpenAPI에 없다는 이유로 접근 권한이 없다고/있다고 단정하지 않는다.

## 담당자에게 필요한 확인

1. 권한 있는 담당자의 정상 인증으로 추출 가능한 사용자 범위를 확인한다.
   다른 환자 ID를 추측하거나 인증을 우회하지 않는다.
2. 날짜 범위·페이지 제한·응답 열·대상 사용자 수·처방전/복약 건수를 확인한다.
3. API 호출이 데이터를 생성/정리하는 부수 효과가 없는지 배포 코드에서 확인한다.
4. 추출한 JSON을 비공개 로컬 파일로 보관하고 원본 파일 해시와 추출 시점을 기록한다.
5. 원본 DB 테이블과 대조하여 누락된 열, 과거 기록, 이미지 파일, 사용자 매핑을 명시한다.

현재 SQLite 이전 도구에는 API JSON을 그대로 입력할 수 없다. 담당자 자료와 누락 범위가
확인된 뒤 별도 검증 가능한 재구성 절차를 만들어야 한다. 로컬 샘플 DB나 빈 DB로
운영 약 데이터를 대체하지 않는다. 원본 DB 전체를 확보하지 못한 상태의 결과는
"부분 API 추출"로 표시하며 전체 백업/무손실 이전 완료라고 보고하지 않는다.
