import uuid

from fastapi import APIRouter, HTTPException

from app.database import get_connection
from app.models.schemas import UserCreate
from app.models.response_schemas import UserCreateResponse, UserResponse


router = APIRouter(prefix="/api/v1/users", tags=["Users"])


@router.post("", response_model=UserCreateResponse)
def create_user(user: UserCreate):
    conn = get_connection()
    try:
        user_id = str(uuid.uuid4())
        conn.execute(
            """
            INSERT INTO users (id, name, birth_date, gender, phone, role)
            VALUES (?, ?, ?, ?, ?, ?)
            """,
            (user_id, user.name, user.birth_date, user.gender, user.phone, user.role),
        )
        conn.commit()
        return {"id": user_id, **user.model_dump()}
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
