import uuid

from fastapi import APIRouter, HTTPException

from app.database import get_connection
from app.models.schemas import UserCreate


router = APIRouter(prefix="/api/v1/users", tags=["Users"])


def _pregnancy_flag(user: UserCreate) -> tuple[int, str | None]:
    status = (user.pregnancy_status or "").strip() or None
    if user.is_pregnant is True:
        return 1, status or "임신 중"
    if user.is_pregnant is False:
        return 0, status
    if status == "임신 중":
        return 1, status
    return 0, status


@router.post("")
def create_user(user: UserCreate):
    conn = get_connection()
    try:
        user_id = str(uuid.uuid4())
        is_pregnant, pregnancy_status = _pregnancy_flag(user)
        conn.execute(
            """
            INSERT INTO users (
                id, name, birth_date, gender, phone, role,
                is_pregnant, pregnancy_status
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                user_id,
                user.name,
                user.birth_date,
                user.gender,
                user.phone,
                user.role,
                is_pregnant,
                pregnancy_status,
            ),
        )
        conn.commit()
        payload = user.model_dump()
        payload["is_pregnant"] = bool(is_pregnant)
        payload["pregnancy_status"] = pregnancy_status
        return {"id": user_id, **payload}
    finally:
        conn.close()


@router.get("")
def get_users():
    conn = get_connection()
    try:
        return [
            dict(row)
            for row in conn.execute(
                "SELECT * FROM users ORDER BY created_at DESC"
            ).fetchall()
        ]
    finally:
        conn.close()


@router.get("/{user_id}")
def get_user(user_id: str):
    conn = get_connection()
    try:
        row = conn.execute("SELECT * FROM users WHERE id = ?", (user_id,)).fetchone()
        if not row:
            raise HTTPException(status_code=404, detail="사용자가 없습니다.")
        return dict(row)
    finally:
        conn.close()
