"""Keep the repository's real SQLite files out of every pytest run.

This hook runs before test collection, including tests that import DB_PATH at
module import time. Individual tests may override these temporary paths.
"""

import os
import shutil
import tempfile
from pathlib import Path


_test_databases = None


def pytest_sessionstart(session):
    global _test_databases
    # Some legacy tests keep SQLite handles open until interpreter shutdown on
    # Windows; do not turn a passing test run into a cleanup failure.
    _test_databases = tempfile.TemporaryDirectory(
        prefix="alkong-pytest-", ignore_cleanup_errors=True
    )
    root = Path(_test_databases.name)
    os.environ["ALKONGYAKONG_DB_PATH"] = str(root / "alkongyakong.db")
    os.environ["MFDS_DRUG_PERMISSION_DB_PATH"] = str(root / "mfds.db")
    os.environ["EASY_CATEGORY_MAP_DB_PATH"] = str(root / "easy-category.db")
    os.environ["APP_ENV"] = "development"
    os.environ["ALKONGYAKONG_DATABASE_BACKEND"] = "sqlite"
    os.environ["AUTH_ENFORCED"] = "false"
    # Automatic network workers can outlive a test's DB monkeypatch and read
    # a different test's database. Explicit worker tests can opt back in.
    os.environ["DUR_AUTO_SYNC"] = "false"
    if os.getenv("RUN_MFDS_DATASET_TESTS") == "1":
        dataset_path = Path(os.getenv("MFDS_TEST_DATASET_PATH", ""))
        if not dataset_path.is_file():
            raise RuntimeError(
                "MFDS_TEST_DATASET_PATH must point to an existing dataset "
                "when RUN_MFDS_DATASET_TESTS=1"
            )
        shutil.copy2(dataset_path, root / "mfds.db")

    import app.database as database
    import init_db

    database.DB_PATH = os.environ["ALKONGYAKONG_DB_PATH"]
    init_db.DB_PATH = database.DB_PATH
    init_db.initialize_database()
    from app.services.mfds_drug_permission.db import initialize_permission_db
    initialize_permission_db()


def pytest_sessionfinish(session, exitstatus):
    global _test_databases
    if _test_databases is not None:
        _test_databases.cleanup()
        _test_databases = None
