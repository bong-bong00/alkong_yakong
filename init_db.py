import sqlite3

conn = sqlite3.connect("alkongyakong.db")
cursor = conn.cursor()

# 1. users
cursor.execute("""
CREATE TABLE IF NOT EXISTS users (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    birth_date TEXT,
    gender TEXT,
    phone TEXT,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP
);
""")

# 2. guardians
cursor.execute("""
CREATE TABLE IF NOT EXISTS guardians (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL,
    guardian_name TEXT NOT NULL,
    relationship TEXT,
    phone TEXT,
    fcm_token TEXT,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP
);
""")

# 3. prescriptions
cursor.execute("""
CREATE TABLE IF NOT EXISTS prescriptions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL,
    source_type TEXT NOT NULL,
    hospital_name TEXT,
    pharmacy_name TEXT,
    prescribed_date TEXT,
    expire_date TEXT,
    original_image_path TEXT,
    ocr_text TEXT,
    status TEXT DEFAULT 'ACTIVE',
    created_at TEXT DEFAULT CURRENT_TIMESTAMP
);
""")

# 4. prescription_drugs
cursor.execute("""
CREATE TABLE IF NOT EXISTS prescription_drugs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    prescription_id INTEGER NOT NULL,
    drug_name TEXT NOT NULL,
    ingredient_name TEXT,
    dosage TEXT,
    unit TEXT,
    frequency_per_day INTEGER,
    times_per_take INTEGER,
    morning INTEGER DEFAULT 0,
    lunch INTEGER DEFAULT 0,
    dinner INTEGER DEFAULT 0,
    bedtime INTEGER DEFAULT 0,
    duration_days INTEGER,
    warning_note TEXT
);
""")

# 5. medication_schedules
cursor.execute("""
CREATE TABLE IF NOT EXISTS medication_schedules (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL,
    prescription_drug_id INTEGER NOT NULL,
    scheduled_date TEXT NOT NULL,
    time_slot TEXT NOT NULL,
    scheduled_time TEXT,
    status TEXT DEFAULT 'PENDING'
);
""")

# 6. medication_logs
cursor.execute("""
CREATE TABLE IF NOT EXISTS medication_logs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL,
    schedule_id INTEGER,
    taken_at TEXT DEFAULT CURRENT_TIMESTAMP,
    image_path TEXT,
    verification_result TEXT NOT NULL,
    confidence_score REAL,
    predicted_drugs_json TEXT,
    missing_drugs_json TEXT,
    extra_drugs_json TEXT,
    note TEXT
);
""")

conn.commit()
conn.close()

print("모든 테이블 생성 완료")