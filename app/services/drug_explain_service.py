import json

from fastapi import HTTPException

from app.database import get_connection


def get_drug_explanation(medicine_code: str) -> dict:
    conn = get_connection()
    try:
        cursor = conn.cursor()
        medicine = cursor.execute(
            "SELECT * FROM medicines WHERE medicine_code = ?",
            (medicine_code,),
        ).fetchone()
        if not medicine:
            raise HTTPException(status_code=404, detail="의약품이 없습니다.")

        card = cursor.execute(
            """
            SELECT * FROM ai_explanation_cards
            WHERE medicine_code = ?
            ORDER BY created_at DESC, id DESC
            LIMIT 1
            """,
            (medicine_code,),
        ).fetchone()
        if not card:
            documents = cursor.execute(
                "SELECT id FROM medicine_documents WHERE medicine_code = ?",
                (medicine_code,),
            ).fetchall()
            summary = (
                f"{medicine['product_name']}은(는) {medicine['ingredient']} 성분의 약입니다. "
                f"{medicine['efficacy'] or '효능 정보는 확인 중입니다.'}"
            )
            cursor.execute(
                """
                INSERT INTO ai_explanation_cards (
                    medicine_code, summary, how_to_take, warnings,
                    source_document_ids, model_name
                ) VALUES (?, ?, ?, ?, ?, 'mock')
                """,
                (
                    medicine_code,
                    summary,
                    medicine["usage"] or "처방 지시에 따라 복용하세요.",
                    medicine["precautions"] or "이상 반응이 있으면 전문가와 상담하세요.",
                    json.dumps([row["id"] for row in documents]),
                ),
            )
            conn.commit()
            card = cursor.execute(
                "SELECT * FROM ai_explanation_cards WHERE id = ?",
                (cursor.lastrowid,),
            ).fetchone()

        return {"medicine": dict(medicine), "explanation": dict(card)}
    finally:
        conn.close()
