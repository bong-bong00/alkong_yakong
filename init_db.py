import sqlite3
from datetime import datetime

from app.database import DB_PATH


TABLE_DEFINITIONS = {
    "users": """
        CREATE TABLE users (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            birth_date TEXT,
            gender TEXT,
            phone TEXT,
            role TEXT NOT NULL DEFAULT 'PATIENT',
            is_pregnant INTEGER NOT NULL DEFAULT 0,
            pregnancy_status TEXT,
            created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
            updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
        )
    """,
    "guardians": """
        CREATE TABLE guardians (
            id TEXT PRIMARY KEY,
            user_id TEXT NOT NULL,
            guardian_name TEXT NOT NULL,
            relationship TEXT,
            phone TEXT,
            fcm_token TEXT,
            notification_enabled INTEGER NOT NULL DEFAULT 1,
            created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
            FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
        )
    """,
    "medicines": """
        CREATE TABLE medicines (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            medicine_code TEXT NOT NULL UNIQUE,
            product_name TEXT NOT NULL,
            ingredient TEXT NOT NULL,
            manufacturer TEXT,
            efficacy TEXT,
            usage TEXT,
            precautions TEXT,
            image_url TEXT,
            easy_category TEXT,
            created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
            updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
        )
    """,
    "dur_taboo": """
        CREATE TABLE dur_taboo (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            ingredient_a TEXT NOT NULL,
            ingredient_b TEXT,
            taboo_type TEXT NOT NULL,
            severity TEXT NOT NULL DEFAULT 'CAUTION',
            description TEXT NOT NULL,
            source TEXT,
            external_id TEXT,
            ingredient_a_code TEXT,
            ingredient_b_code TEXT,
            min_age INTEGER,
            max_age INTEGER,
            pregnancy_grade TEXT,
            notification_date TEXT,
            raw_json TEXT,
            updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
            created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
        )
    """,
    "prescriptions": """
        CREATE TABLE prescriptions (
            id TEXT PRIMARY KEY,
            user_id TEXT NOT NULL,
            source_type TEXT NOT NULL DEFAULT 'OCR',
            hospital_name TEXT,
            pharmacy_name TEXT,
            prescribed_date TEXT,
            expire_date TEXT,
            original_image_path TEXT,
            ocr_text TEXT,
            ocr_status TEXT NOT NULL DEFAULT 'COMPLETED',
            status TEXT NOT NULL DEFAULT 'ACTIVE',
            created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
            FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
        )
    """,
    "prescription_items": """
        CREATE TABLE prescription_items (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            prescription_id TEXT NOT NULL,
            medicine_code TEXT,
            ocr_drug_name TEXT NOT NULL,
            dosage TEXT,
            unit TEXT,
            frequency_per_day INTEGER,
            times_per_take INTEGER,
            duration_days INTEGER,
            administration_times TEXT,
            warning_note TEXT,
            easy_explanation TEXT,
            match_status TEXT NOT NULL DEFAULT 'UNMATCHED',
            created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
            FOREIGN KEY (prescription_id) REFERENCES prescriptions(id) ON DELETE CASCADE,
            FOREIGN KEY (medicine_code) REFERENCES medicines(medicine_code) ON DELETE SET NULL
        )
    """,
    "user_medicines": """
        CREATE TABLE user_medicines (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id TEXT NOT NULL,
            medicine_code TEXT NOT NULL,
            prescription_item_id INTEGER,
            start_date TEXT,
            end_date TEXT,
            dosage TEXT,
            frequency_per_day INTEGER,
            administration_times TEXT,
            is_active INTEGER NOT NULL DEFAULT 1,
            created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
            FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
            FOREIGN KEY (medicine_code) REFERENCES medicines(medicine_code),
            FOREIGN KEY (prescription_item_id) REFERENCES prescription_items(id) ON DELETE SET NULL
        )
    """,
    "medication_schedules": """
        CREATE TABLE medication_schedules (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id TEXT NOT NULL,
            user_medicine_id INTEGER NOT NULL,
            scheduled_date TEXT NOT NULL,
            scheduled_time TEXT NOT NULL,
            time_slot TEXT,
            status TEXT NOT NULL DEFAULT 'PENDING',
            created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
            FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
            FOREIGN KEY (user_medicine_id) REFERENCES user_medicines(id) ON DELETE CASCADE,
            UNIQUE (user_medicine_id, scheduled_date, scheduled_time)
        )
    """,
    "medication_logs": """
        CREATE TABLE medication_logs (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id TEXT NOT NULL,
            schedule_id INTEGER,
            user_medicine_id INTEGER,
            taken_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
            status TEXT NOT NULL DEFAULT 'TAKEN',
            image_path TEXT,
            verification_result TEXT,
            confidence_score REAL,
            details_json TEXT,
            note TEXT,
            FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
            FOREIGN KEY (schedule_id) REFERENCES medication_schedules(id) ON DELETE SET NULL,
            FOREIGN KEY (user_medicine_id) REFERENCES user_medicines(id) ON DELETE SET NULL
        )
    """,
    "risk_results": """
        CREATE TABLE risk_results (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id TEXT NOT NULL,
            risk_level TEXT NOT NULL,
            taboo_id INTEGER,
            ingredient_a TEXT,
            ingredient_b TEXT,
            description TEXT,
            analyzed_ingredients TEXT NOT NULL,
            analysis_id TEXT,
            risk_type TEXT,
            total_matches INTEGER NOT NULL DEFAULT 0,
            matches_json TEXT,
            created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
            FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
            FOREIGN KEY (taboo_id) REFERENCES dur_taboo(id) ON DELETE SET NULL
        )
    """,
    "heart_rate_logs": """
        CREATE TABLE heart_rate_logs (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id TEXT NOT NULL,
            bpm INTEGER NOT NULL CHECK (bpm > 0),
            measured_at TEXT NOT NULL,
            device_id TEXT,
            source TEXT NOT NULL DEFAULT 'POLAR',
            created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
            FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
        )
    """,
    "baseline_heart_rate": """
        CREATE TABLE baseline_heart_rate (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id TEXT NOT NULL UNIQUE,
            resting_bpm REAL NOT NULL,
            min_normal_bpm INTEGER NOT NULL,
            max_normal_bpm INTEGER NOT NULL,
            sample_count INTEGER NOT NULL DEFAULT 1,
            calculated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
            FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
        )
    """,
    "abnormal_events": """
        CREATE TABLE abnormal_events (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id TEXT NOT NULL,
            heart_rate_log_id INTEGER,
            event_type TEXT NOT NULL,
            bpm INTEGER NOT NULL,
            baseline_bpm REAL,
            severity TEXT NOT NULL,
            status TEXT NOT NULL DEFAULT 'OPEN',
            occurred_at TEXT NOT NULL,
            created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
            FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
            FOREIGN KEY (heart_rate_log_id) REFERENCES heart_rate_logs(id) ON DELETE SET NULL
        )
    """,
    "notifications": """
        CREATE TABLE notifications (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id TEXT NOT NULL,
            guardian_id TEXT,
            abnormal_event_id INTEGER,
            schedule_id INTEGER,
            medication_log_id INTEGER,
            notification_type TEXT NOT NULL,
            title TEXT NOT NULL,
            message TEXT NOT NULL,
            status TEXT NOT NULL DEFAULT 'RECORDED',
            sent_at TEXT,
            created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
            FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
            FOREIGN KEY (guardian_id) REFERENCES guardians(id) ON DELETE SET NULL,
            FOREIGN KEY (abnormal_event_id) REFERENCES abnormal_events(id) ON DELETE SET NULL,
            FOREIGN KEY (schedule_id) REFERENCES medication_schedules(id) ON DELETE SET NULL,
            FOREIGN KEY (medication_log_id) REFERENCES medication_logs(id) ON DELETE SET NULL
        )
    """,
    "ai_explanation_cards": """
        CREATE TABLE ai_explanation_cards (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            medicine_code TEXT NOT NULL,
            summary TEXT NOT NULL,
            what_it_does TEXT,
            how_to_take TEXT,
            warnings TEXT,
            cautions TEXT,
            side_effects TEXT,
            storage TEXT,
            ask_doctor_when TEXT,
            source_based INTEGER NOT NULL DEFAULT 0,
            official_raw_summary TEXT,
            source_document_ids TEXT,
            model_name TEXT NOT NULL DEFAULT 'mock',
            generated_by TEXT NOT NULL DEFAULT 'mock',
            source TEXT NOT NULL DEFAULT 'local',
            is_verified INTEGER NOT NULL DEFAULT 0,
            created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
            FOREIGN KEY (medicine_code) REFERENCES medicines(medicine_code) ON DELETE CASCADE
        )
    """,
    "medicine_documents": """
        CREATE TABLE medicine_documents (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            medicine_code TEXT NOT NULL,
            document_type TEXT NOT NULL,
            title TEXT,
            content TEXT NOT NULL,
            source_url TEXT,
            embedding TEXT,
            created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
            FOREIGN KEY (medicine_code) REFERENCES medicines(medicine_code) ON DELETE CASCADE
        )
    """,
}

REQUIRED_COLUMNS = {
    table: {
        line.strip().split()[0]
        for line in definition.splitlines()
        if line.strip()
        and not line.strip().upper().startswith(("CREATE ", "FOREIGN ", "UNIQUE ", "CHECK ", ")"))
    }
    for table, definition in TABLE_DEFINITIONS.items()
}

INDEXES = [
    "CREATE INDEX IF NOT EXISTS idx_guardians_user_id ON guardians(user_id)",
    "CREATE INDEX IF NOT EXISTS idx_medicines_ingredient ON medicines(ingredient)",
    "CREATE INDEX IF NOT EXISTS idx_dur_taboo_ingredients ON dur_taboo(ingredient_a, ingredient_b)",
    """
    CREATE UNIQUE INDEX IF NOT EXISTS idx_dur_taboo_source_external
    ON dur_taboo(source, taboo_type, external_id)
    WHERE external_id IS NOT NULL
    """,
    "CREATE INDEX IF NOT EXISTS idx_prescriptions_user_id ON prescriptions(user_id)",
    "CREATE INDEX IF NOT EXISTS idx_prescription_items_prescription_id ON prescription_items(prescription_id)",
    "CREATE INDEX IF NOT EXISTS idx_user_medicines_user_id ON user_medicines(user_id, is_active)",
    "CREATE INDEX IF NOT EXISTS idx_schedules_user_date ON medication_schedules(user_id, scheduled_date)",
    "CREATE INDEX IF NOT EXISTS idx_medication_logs_user_taken ON medication_logs(user_id, taken_at)",
    "CREATE INDEX IF NOT EXISTS idx_risk_results_user_created ON risk_results(user_id, created_at)",
    "CREATE INDEX IF NOT EXISTS idx_heart_rate_user_measured ON heart_rate_logs(user_id, measured_at)",
    "CREATE INDEX IF NOT EXISTS idx_abnormal_events_user_occurred ON abnormal_events(user_id, occurred_at)",
    "CREATE INDEX IF NOT EXISTS idx_notifications_user_created ON notifications(user_id, created_at)",
    "CREATE INDEX IF NOT EXISTS idx_notifications_schedule ON notifications(schedule_id, notification_type)",
]

OBSOLETE_TABLES = ("prescription_drugs",)

ADDITIVE_COLUMNS = {
    "dur_taboo": {
        "external_id": "TEXT",
        "ingredient_a_code": "TEXT",
        "ingredient_b_code": "TEXT",
        "min_age": "INTEGER",
        "max_age": "INTEGER",
        "pregnancy_grade": "TEXT",
        "notification_date": "TEXT",
        "raw_json": "TEXT",
        "updated_at": "TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP",
    },
    "risk_results": {
        "analysis_id": "TEXT",
        "risk_type": "TEXT",
        "total_matches": "INTEGER NOT NULL DEFAULT 0",
        "matches_json": "TEXT",
    },
    "notifications": {
        "schedule_id": "INTEGER",
        "medication_log_id": "INTEGER",
    },
    "ai_explanation_cards": {
        "cautions": "TEXT",
        "side_effects": "TEXT",
        "what_it_does": "TEXT",
        "storage": "TEXT",
        "ask_doctor_when": "TEXT",
        "source_based": "INTEGER NOT NULL DEFAULT 0",
        "official_raw_summary": "TEXT",
        "generated_by": "TEXT NOT NULL DEFAULT 'mock'",
        "source": "TEXT NOT NULL DEFAULT 'local'",
        "is_verified": "INTEGER NOT NULL DEFAULT 0",
    },
    "prescription_items": {
        "easy_explanation": "TEXT",
    },
    "medicines": {
        "easy_category": "TEXT",
    },
    "users": {
        "is_pregnant": "INTEGER NOT NULL DEFAULT 0",
        "pregnancy_status": "TEXT",
    },
}


def _existing_columns(cursor: sqlite3.Cursor, table: str) -> set[str]:
    return {row[1] for row in cursor.execute(f"PRAGMA table_info({table})")}


def initialize_database() -> None:
    conn = sqlite3.connect(DB_PATH)
    conn.execute("PRAGMA foreign_keys = ON")
    cursor = conn.cursor()
    suffix = datetime.now().strftime("%Y%m%d%H%M%S")

    for table in OBSOLETE_TABLES:
        if _existing_columns(cursor, table):
            cursor.execute(f"ALTER TABLE {table} RENAME TO legacy_{table}_{suffix}")

    for table, columns in ADDITIVE_COLUMNS.items():
        existing = _existing_columns(cursor, table)
        for column, definition in columns.items():
            if existing and column not in existing:
                cursor.execute(
                    f"ALTER TABLE {table} ADD COLUMN {column} {definition}"
                )

    for table, definition in TABLE_DEFINITIONS.items():
        existing = _existing_columns(cursor, table)
        if existing and not REQUIRED_COLUMNS[table].issubset(existing):
            cursor.execute(f"ALTER TABLE {table} RENAME TO legacy_{table}_{suffix}")
        cursor.execute(definition.replace(f"CREATE TABLE {table}", f"CREATE TABLE IF NOT EXISTS {table}"))

    for statement in INDEXES:
        cursor.execute(statement)

    conn.commit()
    conn.close()


if __name__ == "__main__":
    initialize_database()
    print(f"알콩약콩 MVP 16개 테이블 생성 완료: {DB_PATH}")
