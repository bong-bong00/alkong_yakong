# AI 약사 DUR 연결 수정 — 팀원 인수인계

작성일: 2026-10-01. 작업 브랜치: `woong2`.

## 현재 상태

우리 작업 폴더에서 코드 구현·자동 테스트 완료. 아직 커밋·푸시·main 병합·Render 배포는 하지 않음.

실제 Render 두 서버를 연결한 운영 테스트는 아직 하지 않음. 아래 팀 서버 변경과 양쪽 배포가 끝나야 전체 연동 완료로 볼 수 있음.

## 구현한 내용

| 파일 | 변경 |
| --- | --- |
| `app/models/schemas.py` | DUR 요청에 `medicine_names_by_code`, `analysis_purpose` 추가 |
| `app/services/dur_service.py` | 팀 최소 커밋 `0d52751`의 공식 약 캐시·저장 함수를 필요한 부분만 이식. 기존 캐시도 공식 이름 확인. 코드·이름·성분 검증 후 카탈로그에만 저장. 요청 약 누락은 미완료로 처리하며 확인된 금기·중복은 유지 |
| `app/routes/dur_analysis.py` | 상담 요청은 결과 저장 없이 최신 기준 조회. 기존 요청은 기존 저장·조회 방식 유지 |
| `app/services/external_api_service.py` | 조회 실패 로그의 실제 약 이름·코드를 입력 유무 표시로 대체 |
| `lib/features/drug_explain/drug_explain_screen.dart` | 팀의 복수 선택 시트를 필요한 부분만 이식. `selected_medicines`, `temporary_medicines` 전달. 임시 약은 실제 등록약 목록과 분리 관리 |
| `test/test_dur_consultation_scope.py` | 공식 조회·식별 실패·부분 경고·저장 분리 등 14개 테스트 |
| `test/drug_explain_scope_test.dart` | 선택한 두 약만 전달 / 단일·약 전체에서 임시 약 전달 테스트 |

특정 약 하드코딩 아님. 임의 사용자 약 추가나 DB 구조 변경 없음.

## 팀 AI 약사 서버에서 추가해야 하는 필수 전달값

대상: `polar-dataset-v2`의 `app/services/medication_feature_dur_client.py`.

`load_remote_combination_context`가 j0jn `/api/v1/dur/analyze`로 보내는 JSON에 아래 값을 추가해야 함.

```json
{
  "user_id": "사용자 ID",
  "medicine_codes": ["공식코드1", "공식코드2"],
  "medicine_names_by_code": {
    "공식코드1": "공식 제품명1",
    "공식코드2": "공식 제품명2"
  },
  "analysis_purpose": "consultation"
}
```

- `analysis_purpose` 생략 시 기본은 `medication`이며 기존처럼 결과 저장. **팀 서버가 새 값을 보내기 전에는 상담 결과 저장 분리가 적용되지 않음.**
- `consultation` 요청은 대상 코드 목록과 각 코드의 공식 이름이 필요. 비어 있으면 422 반환.
- 상담 요청은 `persist=False, refresh=True`: 최신 기준 조회는 하되 `risk_results`에는 저장하지 않음.
- 공식 약 정보·DUR 기준 카탈로그 캐시는 갱신될 수 있음. 사용자 `user_medicines`나 기존 홈의 최신 결과는 변경하지 않음.
- 기존 OCR 후 DUR와 일반 `/dur/analyze`의 저장 동작은 바꾸지 않음.
- 배포 순서는 j0jn 수신 기능을 먼저 반영·확인한 뒤 팀 서버에서 상담용 필드를 보내는 순서 권장. 이전 서버가 새 필드를 무시할 수 있으므로 실제 저장 분리 검증 필수.

## 팀 서버에서 추가 확인할 경고 처리

검토한 팀 연결 코드에는 범위 누락 또는 관련 검사 미완료 시 `items=[]`, `has_risk=None`으로 반환하는 경로가 있음.

j0jn은 일부 약 조회 실패 중에도 이미 확인된 금기·중복을 응답 `matches`에 유지하도록 구현·테스트했음. **팀 서버에서도 이 경고를 버리지 않아야 함.** 미완료 표시와 확인된 경고를 함께 답변하도록 연결 코드와 답변 생성 경로를 검증해야 함. 이는 아직 우리 작업 브랜치에서 수정한 팀 서버 기능이 아님.

검사 대상 수 일치만으로 정상 완료를 판단하지 말 것. 성분과 필요한 기준 조회 실패는 미완료 상태를 유지해야 함.

## 앱 화면 변화

- 기존 약 선택창에 `여러 약 선택` 항목 추가.
- 선택 시 팀 구현을 참고한 체크 목록에서 두 개 이상 선택 가능.
- 선택한 약 이름을 상단에 표시하고 선택 범위만 전달.
- `약 전체`는 등록약 + 대화의 임시 검색약 범위로 요청. 임시 검색약은 홈·내 약에 자동 등록되지 않음.
- OCR·홈·약 자세히 디자인 변경 없음.

## 실제 실행한 검증

```text
Python: 65 passed, 31 subtests passed
Flutter 기존 AI 약사 테스트: 22 passed
Flutter 추가 범위 테스트: 2 passed
Flutter 변경 화면·추가 테스트 분석: No issues found
Python 구문 검사 통과
```

Python 실행 대상:

```text
test/test_dur_consultation_scope.py
test/test_dur_assessment_status.py
test/test_chat_context.py
test/test_drug_explain_current_medicines.py
```

테스트는 임시 DB·가짜 API 응답 사용. 실제 사용자 정보나 운영 서버 DB는 변경하지 않음. 자동 테스트는 실제 식약처의 특정 품목 응답이나 Render 배포 성공을 증명하지 않음.

## 운영 반영 후 확인

- [ ] j0jn OpenAPI에 `medicine_names_by_code`, `analysis_purpose` 표시.
- [ ] 팀 서버에서 상담 요청에 `analysis_purpose=consultation` 전달.
- [ ] 최신 앱으로 임시 검색약·복수 선택 요청 전달.
- [ ] 약 전체 / 직접 두 약 선택 각각 함께먹기·같은 성분 질문 검증.
- [ ] 요청한 약 두 개가 실제 동일한 두 개로 분석되고 기준 조회도 완료.
- [ ] 누락·조회 실패는 정상 0건으로 안내하지 않음.
- [ ] 일부 실패 중 확인된 경고는 AI 답변에도 유지.
- [ ] 상담 후 홈의 최신 DUR 결과와 실제 복용약 목록 유지.
- [ ] 기존 OCR 등록 후 DUR 결과 저장 정상.

원본 역할 유지: 약 데이터·DUR는 `https://alkong-yakong-j0jn.onrender.com`, AI 답변은 `https://alkong-yakong.onrender.com`.
