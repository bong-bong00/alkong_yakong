from fastapi import APIRouter, Query
from app.services.external_api_service import (
    search_drug_info_by_name)

router = APIRouter(prefix="/external", tags=["External APIs"])


@router.get("/drug-info")
def drug_info(name: str = Query(..., description="약 이름")):
    return search_drug_info_by_name(name)