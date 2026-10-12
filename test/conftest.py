# 실행 결과를 보관한 UTF-16 텍스트는 doctest 수집 대상이 아니다.
collect_ignore = ["test_result.txt"]

# Never run tests against the workspace/operating database. Configure before
# application modules are imported during collection; retain fixtures for diagnosis.
import os
import tempfile
from pathlib import Path


def pytest_configure(config):
    fixture_root = Path(tempfile.mkdtemp(prefix="alkong-pytest-"))
    os.environ["ALKONGYAKONG_DB_PATH"] = str(fixture_root / "app.db")
    os.environ["MFDS_DRUG_PERMISSION_DB_PATH"] = str(fixture_root / "permission.db")
    os.environ["APP_ENV"] = "development"
    os.environ["AUTH_ENFORCED"] = "false"
    import shutil
    source = Path(__file__).resolve().parents[1] / "alkongyakong.db"
    if source.is_file():
        shutil.copyfile(source, fixture_root / "app.db")
    from init_db import initialize_database
    from app.services.mfds_drug_permission.db import initialize_permission_db
    initialize_permission_db()
    initialize_database()
