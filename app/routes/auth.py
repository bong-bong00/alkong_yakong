from fastapi import APIRouter

from app.core.auth import load_authority_identity

router = APIRouter(prefix="/api/v1/auth", tags=["Internal Authentication"])


@router.get("/identity/{user_id}")
def current_identity(user_id: str):
    # Only a purpose-bound service credential can reach this route. No phone,
    # password, allergy list or medical history is returned to the other server.
    return load_authority_identity(user_id)
