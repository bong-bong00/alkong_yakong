# main 화면 반영 및 코다론정 자동 등록 제거

## 반영 기준

- 작업 브랜치: woong2. 받아온 main: 6444733.
- OCR 결과와 약 자세히는 기존 카드형 화면 및 기능 유지.
- 홈·내 약 목록·로그인·보호자·심박 등 나머지 화면은 main 변경 반영.
- OCR·상세 전용 색/글꼴/카드 파일을 분리하여 main 공통 디자인 변경의 영향을 제한.
- 기존 투약 단위 처리, 상세 설명, 공식 자료의 부분 갱신 시 정보 보존, 한국 날짜 처리 유지.
- main의 공식 원문 변경 감지 보완은 함께 반영: 변경된 원문의 과거 설명은 OUTDATED로 숨김.

## 코다론정 제거 범위

- 서버 시작 시 데모 약 등록을 실행하지 않음. DEMO_SEED_ENABLED=true여도 자동 등록하지 않음.
- 오늘 약/내 약/약 상세 조회 시 코다론정 자동 삽입을 실행하지 않음.
- 팀 인증 사용자 ID를 약 서버에 준비하는 기능은 약 없이 유지: medication_user_service.py.
- 실제로 등록한 코다론정, 약 품목 정보, 성분 및 DUR 기준은 그대로 유지.
- seed_mvp_medicines.py는 테스트에서 명시적으로 호출하는 예시 데이터로만 남음.
- 과거 자동 등록 행에는 출처 표시가 없어 실제 손 입력 약과 안전하게 구별할 수 없음. 기존 DB의 코다론정을 일괄 삭제하지 않음.

## 주요 파일

- lib/features/prescription/presentation/screens/prescription_screen.dart: 기존 OCR 결과 화면.
- lib/features/medicines/presentation/screens/drug_detail_screen.dart: 기존 상세 카드형 화면.
- lib/core/{constants,theme,widgets}/medicine_flow_*.dart: 보호된 화면 전용 디자인.
- app/main.py: 자동 데모 등록 제거, 운영 환경에서만 배경 동기화.
- app/services/{today_medication_service,user_medicines_service,medication_user_service}.py: 약 없는 사용자 조회, 기존 실제 약 보존.
- app/services/medicine_detail_service.py 및 drug_explain_service.py: 풍부한 상세 설명과 OUTDATED 차단 통합.
- app/services/medication_feature_dur_client.py: main의 AI 상담 호출에도 consultation 구분과 명시적 약 코드/제품명을 전송하여 홈 DUR 결과 저장과 분리.

## 검증 결과

- Python 전체: 486개 통과, 추가 하위 사례 90개 통과.
- Flutter 전체: 657개 통과.
- Flutter 코드 분석: 문제 없음.
- Git 파일 병합 충돌: 없음. 현재 병합 커밋 전 단계.

## 배포 상태

이 문서는 로컬 구현 기준. 원격 main/woong2 푸시 및 Render 배포는 아직 실행하지 않음.
서버 자동 등록 제거는 서버 배포 후 적용되며 기존 앱은 다시 실행/빌드해야 변경된 화면을 사용함.
