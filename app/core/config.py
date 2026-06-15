import os

from dotenv import load_dotenv


load_dotenv()

E_DRUG_API_KEY = os.getenv("E_DRUG_API_KEY") or os.getenv("MFDS_SERVICE_KEY")
GEMINI_API_KEY = os.getenv("GEMINI_API_KEY")
GEMINI_MODEL = os.getenv("GEMINI_MODEL", "gemini-2.5-flash")

E_DRUG_BASE_URL = (
    "https://apis.data.go.kr/1471000/DrbEasyDrugInfoService/getDrbEasyDrugList"
)

# Backward-compatible names used by the existing external route.
MFDS_SERVICE_KEY = E_DRUG_API_KEY
MFDS_E_DRUG_BASE_URL = E_DRUG_BASE_URL
