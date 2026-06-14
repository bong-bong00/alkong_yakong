from fastapi import APIRouter
from app.database import get_connection
from app.models.schemas import UserCreate

router = APIRouter(prefix="/users", tags=["Users"])

@router.post("/")
def create_user(user: UserCreate):
    conn = get_connection()
    cursor = conn.cursor()

    cursor.execute("""
        INSERT INTO users (name, birth_date, gender, phone)
        VALUES (?, ?, ?, ?)
    """, (user.name, user.birth_date, user.gender, user.phone))

    conn.commit()
    user_id = cursor.lastrowid
    conn.close()

    return {
        "message": "사용자 등록 완료",
        "user_id": user_id,
        "name": user.name
    }

@router.get("/")
def get_users():
    conn = get_connection()
    cursor = conn.cursor()

    cursor.execute("SELECT * FROM users ORDER BY id DESC")
    rows = cursor.fetchall()
    conn.close()

    return [dict(row) for row in rows]