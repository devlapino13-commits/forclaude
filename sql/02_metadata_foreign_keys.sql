-- ============================================================================
-- 02_metadata_foreign_keys.sql
-- Внешние ключи: какая таблица.колонка ссылается на какую таблицу.колонку.
-- ============================================================================

SELECT
    TRIM(rc.RDB$RELATION_NAME)   AS TABLE_NAME,
    TRIM(rc.RDB$CONSTRAINT_NAME) AS FK_NAME,
    TRIM(s.RDB$FIELD_NAME)       AS COLUMN_NAME,
    TRIM(rc2.RDB$RELATION_NAME)  AS REF_TABLE,
    TRIM(s2.RDB$FIELD_NAME)      AS REF_COLUMN
FROM RDB$RELATION_CONSTRAINTS rc
JOIN RDB$REF_CONSTRAINTS refc
     ON refc.RDB$CONSTRAINT_NAME = rc.RDB$CONSTRAINT_NAME
JOIN RDB$RELATION_CONSTRAINTS rc2
     ON rc2.RDB$CONSTRAINT_NAME = refc.RDB$CONST_NAME_UQ
JOIN RDB$INDEX_SEGMENTS s
     ON s.RDB$INDEX_NAME = rc.RDB$INDEX_NAME
JOIN RDB$INDEX_SEGMENTS s2
     ON s2.RDB$INDEX_NAME = rc2.RDB$INDEX_NAME
    AND s2.RDB$FIELD_POSITION = s.RDB$FIELD_POSITION
WHERE rc.RDB$CONSTRAINT_TYPE = 'FOREIGN KEY'
ORDER BY 1, 2, s.RDB$FIELD_POSITION;
