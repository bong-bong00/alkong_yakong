"""Create/refresh easy_category_map.db seed rows."""

from app.services.pharmacist.easy_category_db import (
    DB_PATH,
    initialize_easy_category_map_db,
    list_map_rows,
)


def main() -> None:
    path = initialize_easy_category_map_db(reset_seed=True)
    rows = list_map_rows()
    print("db =", path)
    print("rows =", len(rows))
    for row in rows[:12]:
        print(
            f"  [{row['match_scope']}] {row['official_phrase']} → {row['easy_label']}"
        )


if __name__ == "__main__":
    main()
