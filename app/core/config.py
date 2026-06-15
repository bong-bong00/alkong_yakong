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

# Backward-compatible names used by the existing external route.
MFDS_SERVICE_KEY = E_DRUG_API_KEY
MFDS_E_DRUG_BASE_URL = E_DRUG_BASE_URL
