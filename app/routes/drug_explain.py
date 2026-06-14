from fastapi import APIRouter

from app.services.drug_explain_service import get_drug_explanation


router = APIRouter(prefix="/api/v1", tags=["Drug Explain"])


@router.get("/drug-explain/{medicine_code}")
def explain_drug(medicine_code: str):
    return get_drug_explanation(medicine_code)
