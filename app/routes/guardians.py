import uuid

from fastapi import APIRouter, HTTPException

from app.database import get_connection
from app.models.schemas import GuardianCreate
from app.models.response_schemas import GuardianCreateResponse, GuardianResponse


router = APIRouter(prefix="/api/v1/guardians", tags=["Guardians"])


@router.post("", response_model=GuardianCreateResponse)
def create_guardian(guardian: GuardianCreate):
    conn = get_connection()
    try:
        if not conn.execute(
            "SELECT 1 FROM users WHERE id = ?", (guardian.user_id,)
        ).fetchone():
            raise HTTPException(status_code=404, detail="사용자가 없습니다.")
        guardian_id = str(uuid.uuid4())
        conn.execute(
            """
            INSERT INTO guardians (
                id, user_id, guardian_name, relationship, phone,
                fcm_token, notification_enabled
            ) VALUES (?, ?, ?, ?, ?, ?, ?)
            """,
            (
                guardian_id,
                guardian.user_id,
                guardian.guardian_name,
                guardian.relationship,
                guardian.phone,
                guardian.fcm_token,
                int(guardian.notification_enabled),
            ),
        )
        conn.commit()
        return {"id": guardian_id, **guardian.model_dump()}
    finally:
        conn.close()


@router.get("/users/{user_id}", response_model=list[GuardianResponse])
def get_user_guardians(user_id: str):
    conn = get_connection()
    try:
        rows = conn.execute(
            "SELECT * FROM guardians WHERE user_id = ? ORDER BY created_at",
            (user_id,),
        ).fetchall()
        return [dict(row) for row in rows]
    finally:
        conn.close()
