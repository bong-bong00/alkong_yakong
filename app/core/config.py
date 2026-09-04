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

# 식약처 의약품 제품 허가정보
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

# 네이버 CLOVA OCR
# - 기본: Gemini 우선, 할당량/키 실패 시 CLOVA로 자동 폴백(URL·SECRET 있으면)
# - CLOVA_OCR_ENABLED=true 이면 CLOVA를 먼저 시도
CLOVA_OCR_API_URL = os.getenv("CLOVA_OCR_API_URL", "").strip()
CLOVA_OCR_SECRET_KEY = os.getenv("CLOVA_OCR_SECRET_KEY", "").strip()
CLOVA_OCR_ENABLED = os.getenv("CLOVA_OCR_ENABLED", "false").lower() == "true"

# 식약처 DUR: 서버 기동·검사 시 자동으로 받아온다 (수동 POST /dur/sync 없이도).
DUR_AUTO_SYNC = os.getenv("DUR_AUTO_SYNC", "true").lower() == "true"
_DUR_BOOTSTRAP_PAGES = os.getenv("DUR_BOOTSTRAP_MAX_PAGES", "20").strip().lower()
if _DUR_BOOTSTRAP_PAGES in {"all", "none", "*"}:
    DUR_BOOTSTRAP_MAX_PAGES = None
elif _DUR_BOOTSTRAP_PAGES.isdigit():
    DUR_BOOTSTRAP_MAX_PAGES = max(1, int(_DUR_BOOTSTRAP_PAGES))
else:
    DUR_BOOTSTRAP_MAX_PAGES = 20

# Backward-compatible names used by the existing external route.
MFDS_SERVICE_KEY = E_DRUG_API_KEY
MFDS_E_DRUG_BASE_URL = E_DRUG_BASE_URL
