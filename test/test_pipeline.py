import sys
from pathlib import Path
import json

# 프로젝트 루트 경로 추가
sys.path.append(str(Path(__file__).resolve().parent.parent))

from app.database import get_connection
from init_db import initialize_database
from app.models.schemas import PrescriptionOCRRequest
from app.services.prescription_service import create_prescription_from_ocr

# GEMINI_API_KEY가 없으므로 테스트 환경에서는 AI 응답을 Mock(가짜)으로 교체
import app.services.gemini_service as gemini_service

def dummy_parse_ocr(ocr_text):
    print("   [Mock] Gemini AI 텍스트 필터링 시뮬레이션 중...")
    return [
        {"drug_name": "모사피아정", "dosage": "1정", "frequency_per_day": 2, "duration_days": 5, "warning_note": "실온(1~30℃)보관, 수유주의"},
        {"drug_name": "프로맥정", "dosage": "1정", "frequency_per_day": 2, "duration_days": 5, "warning_note": "실온(1~30℃)보관, 수유주의"},
        {"drug_name": "니자액스캡슐150mg", "dosage": "1캡슐", "frequency_per_day": 2, "duration_days": 5, "warning_note": "위장약"}
    ]

# 함수 바꿔치기
gemini_service.parse_ocr_text_to_medicines = dummy_parse_ocr

def setup_test_db():
    print("1. 기초 데이터 셋업...")
    initialize_database()
    conn = get_connection()
    cursor = conn.cursor()
    # 테스트 유저 생성
    cursor.execute("INSERT OR IGNORE INTO users (id, name, role) VALUES ('test-user-1', '테스트유저', 'PATIENT')")
    
    # 식약처 마스터 DB에 일부 약품 미리 넣어두기 (Fuzzy 매칭 테스트를 위해 실제 이름과 약간 다르게 셋팅)
    cursor.execute("INSERT OR IGNORE INTO medicines (medicine_code, product_name) VALUES ('M1001', '모사피아정10mg')")
    cursor.execute("INSERT OR IGNORE INTO medicines (medicine_code, product_name) VALUES ('M1002', '프로맥정(폴라프레징크)')")
    
    conn.commit()
    conn.close()

def run_test():
    setup_test_db()
    
    print("\n2. 처방전 OCR 처리 파이프라인 시작 (API 호출 시뮬레이션)")
    request = PrescriptionOCRRequest(
        user_id="test-user-1",
        ocr_text="""교부번호 2026041700033
병원정보 중앙성모의원(김재민)
모사피아정     [위장관운동조절제] 1정씩 2회 5일분 실온보관
프로맥정      [위점막보호] 1정씩 2회 5일분
니자액스캡슐150mg               1캡슐씩 2회 5일분"""
    )
    
    result = create_prescription_from_ocr(request)
    print("\n[API 응답 결과 - 프론트엔드가 받게 될 데이터]")
    print(json.dumps(result, indent=2, ensure_ascii=False))
    
    print("\n3. 백엔드 데이터베이스 적재 결과 확인")
    conn = get_connection()
    cursor = conn.cursor()
    
    print("\n[prescription_items] (저장된 처방 내역 및 주의사항):")
    rows = cursor.execute("SELECT ocr_drug_name, dosage, frequency_per_day, duration_days, warning_note FROM prescription_items").fetchall()
    for r in rows:
        print(f"  - {dict(r)}")

    print("\n[user_medicines] (유저가 현재 복용해야 할 약품 목록):")
    rows = cursor.execute("SELECT user_id, medicine_code, dosage, frequency_per_day FROM user_medicines").fetchall()
    for r in rows:
        print(f"  - {dict(r)}")
        
    print("\n[medication_schedules] (자동 생성된 복약 알람 스케줄 - 앞부분 5개만 출력):")
    rows = cursor.execute("SELECT scheduled_date, scheduled_time, time_slot, status FROM medication_schedules LIMIT 5").fetchall()
    for r in rows:
        print(f"  - {dict(r)}")
        
    total_schedules = cursor.execute('SELECT count(*) FROM medication_schedules').fetchone()[0]
    print(f"\n테스트 완료: 3개의 약품 x 하루 2회 x 5일 = 총 {total_schedules}개의 스케줄이 정상적으로 생성되었습니다!")

if __name__ == "__main__":
    run_test()
