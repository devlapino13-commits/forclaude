-- ============================================================================
-- 01_metadata_columns.sql
-- Метаданные: таблицы/представления и их колонки, типы, NOT NULL, PK, default.
-- Просто выполните этот SELECT в IBExpert и экспортируйте результат
-- (правой кнопкой по гриду -> Export Data / Grid to file -> CSV/Excel).
-- ============================================================================

SELECT
    TRIM(r.RDB$RELATION_NAME)                              AS TABLE_NAME,
    CASE WHEN r.RDB$VIEW_BLR IS NULL THEN 'TABLE' ELSE 'VIEW' END AS OBJECT_KIND,
    rf.RDB$FIELD_POSITION                                  AS COL_POS,
    TRIM(rf.RDB$FIELD_NAME)                                AS COLUMN_NAME,
    CASE f.RDB$FIELD_TYPE
        WHEN 7  THEN CASE WHEN f.RDB$FIELD_SUB_TYPE IN (1,2)
                          THEN (CASE WHEN f.RDB$FIELD_SUB_TYPE = 1 THEN 'NUMERIC' ELSE 'DECIMAL' END)
                               || '(' || CAST(COALESCE(f.RDB$FIELD_PRECISION,4) AS VARCHAR(10))
                               || ',' || CAST(COALESCE(-f.RDB$FIELD_SCALE,0) AS VARCHAR(10)) || ')'
                          ELSE 'SMALLINT' END
        WHEN 8  THEN CASE WHEN f.RDB$FIELD_SUB_TYPE IN (1,2)
                          THEN (CASE WHEN f.RDB$FIELD_SUB_TYPE = 1 THEN 'NUMERIC' ELSE 'DECIMAL' END)
                               || '(' || CAST(COALESCE(f.RDB$FIELD_PRECISION,9) AS VARCHAR(10))
                               || ',' || CAST(COALESCE(-f.RDB$FIELD_SCALE,0) AS VARCHAR(10)) || ')'
                          ELSE 'INTEGER' END
        WHEN 9  THEN 'QUAD'
        WHEN 10 THEN 'FLOAT'
        WHEN 11 THEN 'D_FLOAT'
        WHEN 12 THEN 'DATE'
        WHEN 13 THEN 'TIME'
        WHEN 14 THEN 'CHAR(' || CAST(COALESCE(f.RDB$CHARACTER_LENGTH, f.RDB$FIELD_LENGTH) AS VARCHAR(10)) || ')'
        WHEN 16 THEN CASE WHEN f.RDB$FIELD_SUB_TYPE IN (1,2)
                          THEN (CASE WHEN f.RDB$FIELD_SUB_TYPE = 1 THEN 'NUMERIC' ELSE 'DECIMAL' END)
                               || '(' || CAST(COALESCE(f.RDB$FIELD_PRECISION,18) AS VARCHAR(10))
                               || ',' || CAST(COALESCE(-f.RDB$FIELD_SCALE,0) AS VARCHAR(10)) || ')'
                          ELSE 'BIGINT' END
        WHEN 23 THEN 'BOOLEAN'
        WHEN 27 THEN 'DOUBLE PRECISION'
        WHEN 35 THEN 'TIMESTAMP'
        WHEN 37 THEN 'VARCHAR(' || CAST(COALESCE(f.RDB$CHARACTER_LENGTH, f.RDB$FIELD_LENGTH) AS VARCHAR(10)) || ')'
        WHEN 261 THEN 'BLOB SUB_TYPE ' || CAST(f.RDB$FIELD_SUB_TYPE AS VARCHAR(10))
        ELSE 'TYPE_' || CAST(f.RDB$FIELD_TYPE AS VARCHAR(10))
    END                                                     AS FIELD_TYPE,
    CASE WHEN rf.RDB$NULL_FLAG = 1 THEN 'NOT NULL' ELSE '' END AS NULLABILITY,
    CASE WHEN pk.RDB$FIELD_NAME IS NOT NULL THEN 'PK' ELSE '' END AS IS_PK,
    rf.RDB$DEFAULT_SOURCE                                  AS DEFAULT_SOURCE
FROM RDB$RELATION_FIELDS rf
JOIN RDB$RELATIONS r
     ON r.RDB$RELATION_NAME = rf.RDB$RELATION_NAME
JOIN RDB$FIELDS f
     ON f.RDB$FIELD_NAME = rf.RDB$FIELD_SOURCE
LEFT JOIN (
    SELECT s.RDB$FIELD_NAME, rc.RDB$RELATION_NAME
    FROM RDB$RELATION_CONSTRAINTS rc
    JOIN RDB$INDEX_SEGMENTS s ON s.RDB$INDEX_NAME = rc.RDB$INDEX_NAME
    WHERE rc.RDB$CONSTRAINT_TYPE = 'PRIMARY KEY'
) pk
     ON pk.RDB$RELATION_NAME = rf.RDB$RELATION_NAME
    AND pk.RDB$FIELD_NAME = rf.RDB$FIELD_NAME
WHERE (r.RDB$SYSTEM_FLAG IS NULL OR r.RDB$SYSTEM_FLAG = 0)
ORDER BY 2 DESC, 1, rf.RDB$FIELD_POSITION;
