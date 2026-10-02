# main → polar-dataset-v2 통합

- 기준 Polar: `5ba6dec76a7861f8ed58c1221e6e831bfa2a2789`
- 반영 main: `2db6eb99f138e200b64126ccbdd7f113a13d991d`

## 영역별 기준

- main: 기본 사용자 흐름, OCR, 일반 약 정보, 일반 함께먹기 분석, 기타 화면.
- Polar: AI 약사 분류·대화·답변 생성·UI, Polar 센서·측정·재연결·저장·심박 해석·UI.
- 공유 연결부: main 상담용 DUR 계약을 우리 AI 약사 요청과 연결. 서버 주소·환경 설정·DB 스키마는 기존 Polar 유지.
- main의 일반 약 정보 구현에 필요한 서비스 변경은 수용하며, 앱 전체 API 서비스를 이전 구현으로 일괄 덮어쓰지 않음.

## 연결 변경

- main 쉬운 복약 흐름의 별도 측정 구현 대신 기존 MeasureScreen/SavedScreen 사용.
- 내부 returnToCaller 인자로 저장 확인 후 시작한 복약 흐름에 복귀. 기존 심박수 관리 경로는 기본 동작 유지.
- 쉬운 복약 흐름의 AI 약사 진입은 /drug-explain으로 통일.
- AI 약사·Polar 공용 디자인 의존성은 core/polar_pharmacist_ui에 기존 기준을 보존하여 main 공용 디자인과 분리.
- 일반 DUR 요청은 main 처리 유지. 상담용 요청은 analysis_purpose=consultation, persist=False, refresh=True 사용.

## 검증 및 제한

- Flutter 전체 테스트 692개 통과. 추가 연결 테스트는 실제 화면 전환과 운영 HeartSensor 타이머를 사용하며 하드웨어·네트워크 경계만 모킹.
- Python 테스트 553개와 하위 검사 109개 통과(로컬 전체 허가 DB 의존 검사 2개 제외).
- 전체 Python 실행 시 DB products 테이블이 없는 로컬 허가 DB 검사 2개는 실패. 해당 원본 약 DB가 없어 미검증이며 운영 조회 실패라고 해석하지 않음.
- flutter analyze lib test, Python 구문 검사, git diff --check 확인.
- 루트 flutter analyze는 별도 polarbetty 하위 프로젝트 의존성이 준비되지 않아 오류 발생. 앱 lib/test analyzer와 구분.
- BLE 실기기, 운영 Gemini 응답, Render 배포 후 동작은 별도 확인 필요.
- 기존 작업 폴더 dirty lockfile/generated/symlink/전달 문서는 통합 커밋에서 제외하고 그대로 보존.
