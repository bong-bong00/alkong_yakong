"""Cross-service deletion, authorized only by short-lived service credentials."""
from fastapi import APIRouter, Request, HTTPException, Response
from app.core.auth import verify_token, service_role
from app.database import get_connection

router = APIRouter(prefix="/api/v1/internal", tags=["Internal"])


@router.delete("/users/{user_id}", status_code=204)
def purge_user(user_id: str, request: Request):
    header = request.headers.get("authorization", "")
    claims = verify_token(header.removeprefix("Bearer "))
    if (service_role() != "medication" or claims.get("kind") != "service"
        or claims.get("scope") != "account_purge" or claims.get("sub") != "main"
        or claims.get("target") != user_id):
        raise HTTPException(403, "서버 전용 요청입니다.")
    conn = get_connection()
    try:
        conn.execute("DELETE FROM users WHERE id=?", (user_id,))
        conn.commit()
    finally:
        conn.close()
    return Response(status_code=204)
