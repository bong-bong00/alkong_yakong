import os
from pathlib import Path

from dotenv import load_dotenv


PROJECT_ROOT = Path(__file__).resolve().parents[2]
load_dotenv(PROJECT_ROOT / ".env")

E_DRUG_API_KEY = os.getenv("E_DRUG_API_KEY") or os.getenv("MFDS_SERVICE_KEY")
DUR_API_KEY = os.getenv("DUR_API_KEY") or E_DRUG_API_KEY
GEMINI_API_KEY = os.getenv("GEMINI_API_KEY")
GEMINI_MODEL = os.getenv("GEMINI_MODEL", "gemini-2.5-flash")

E_DRUG_BASE_URL = (
    "https://apis.data.go.kr/1471000/DrbEasyDrugInfoService/getDrbEasyDrugList"
)
DUR_API_BASE_URL = (
    "https://apis.data.go.kr/1471000/DURIrdntInfoService03"
)

# 식약처 의약품 제품 허가정보 (e약은요 보조)
MFDS_DRUG_PERMISSION_API_KEY = (
    os.getenv("MFDS_DRUG_PERMISSION_API_KEY") or E_DRUG_API_KEY
)
MFDS_DRUG_PERMISSION_BASE_URL = os.getenv(
    "MFDS_DRUG_PERMISSION_BASE_URL",
    "https://apis.data.go.kr/1471000/DrugPrdtPrmsnInfoService07",
).rstrip("/")
MFDS_DRUG_PERMISSION_LIST_PATH = os.getenv(
    "MFDS_DRUG_PERMISSION_LIST_PATH",
    "/getDrugPrdtPrmsnInq07",
)
MFDS_DRUG_PERMISSION_DETAIL_PATH = os.getenv(
    "MFDS_DRUG_PERMISSION_DETAIL_PATH",
    "/getDrugPrdtPrmsnDtlInq06",
)
MFDS_DRUG_PERMISSION_DB_PATH = os.getenv(
    "MFDS_DRUG_PERMISSION_DB_PATH",
    str(PROJECT_ROOT / "mfds_drug_permission.db"),
)

# 공식 표현 → 쉬운 분류(괄호) 대응표
EASY_CATEGORY_MAP_DB_PATH = os.getenv(
    "EASY_CATEGORY_MAP_DB_PATH",
    str(PROJECT_ROOT / "easy_category_map.db"),
)

# Backward-compatible names used by the existing external route.
MFDS_SERVICE_KEY = E_DRUG_API_KEY
MFDS_E_DRUG_BASE_URL = E_DRUG_BASE_URL
