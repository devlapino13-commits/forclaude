-- ============================================================================
-- 03_metadata_indexes.sql
-- Индексы всех таблиц (кроме индексов, обслуживающих внешние ключи).
-- ============================================================================

SELECT
    TRIM(i.RDB$RELATION_NAME) AS TABLE_NAME,
    TRIM(i.RDB$INDEX_NAME)    AS INDEX_NAME,
    CASE WHEN i.RDB$UNIQUE_FLAG = 1 THEN 'UNIQUE' ELSE '' END AS IS_UNIQUE,
    s.RDB$FIELD_POSITION      AS COL_POS,
    TRIM(s.RDB$FIELD_NAME)    AS COLUMN_NAME
FROM RDB$INDICES i
JOIN RDB$INDEX_SEGMENTS s ON s.RDB$INDEX_NAME = i.RDB$INDEX_NAME
WHERE i.RDB$FOREIGN_KEY IS NULL
  AND (i.RDB$SYSTEM_FLAG IS NULL OR i.RDB$SYSTEM_FLAG = 0)
ORDER BY 1, 2, s.RDB$FIELD_POSITION;
