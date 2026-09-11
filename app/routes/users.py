import uuid

from fastapi import APIRouter, HTTPException

from app.database import get_connection
from app.models.schemas import UserCreate
from app.models.response_schemas import UserCreateResponse, UserResponse
from app.services.user_medicines_service import get_user_medicine, get_user_medicines


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


@router.post("", response_model=UserCreateResponse)
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


@router.get("", response_model=list[UserResponse])
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


@router.get("/{user_id}/medicines")
def user_medicines(user_id: str):
    """현재·과거 내 약 보관 목록 (약 종류당 1행). 오늘 차는 /today-medicines."""
    return get_user_medicines(user_id)


@router.get("/{user_id}/medicines/{medicine_code}")
def user_medicine_detail(user_id: str, medicine_code: str):
    """내 약 한 종류 상세 (쉬운말·주의 포함)."""
    return get_user_medicine(user_id, medicine_code)


@router.get("/{user_id}", response_model=UserResponse)
def get_user(user_id: str):
    conn = get_connection()
    try:
        row = conn.execute("SELECT * FROM users WHERE id = ?", (user_id,)).fetchone()
        if not row:
            raise HTTPException(status_code=404, detail="사용자가 없습니다.")
        return dict(row)
    finally:
        conn.close()
