-- ============================================================================
-- 04_source_views_procedures_triggers.sql
-- Исходники представлений, хранимых процедур и триггеров.
-- Часто именно тут зашита бизнес-логика (расчёты, проверки), полезная для ТЗ.
-- Выполняйте три запроса по отдельности (каждый даёт свой грид) и
-- экспортируйте каждый в отдельный файл.
-- ============================================================================

-- 4.1. Представления (VIEW)
SELECT
    TRIM(RDB$RELATION_NAME) AS VIEW_NAME,
    RDB$VIEW_SOURCE         AS SOURCE_TEXT
FROM RDB$RELATIONS
WHERE RDB$VIEW_BLR IS NOT NULL
ORDER BY 1;

-- 4.2. Хранимые процедуры
SELECT
    TRIM(RDB$PROCEDURE_NAME) AS PROCEDURE_NAME,
    RDB$PROCEDURE_SOURCE     AS SOURCE_TEXT
FROM RDB$PROCEDURES
ORDER BY 1;

-- 4.3. Триггеры
SELECT
    TRIM(RDB$TRIGGER_NAME)  AS TRIGGER_NAME,
    TRIM(RDB$RELATION_NAME) AS TABLE_NAME,
    RDB$TRIGGER_SOURCE      AS SOURCE_TEXT
FROM RDB$TRIGGERS
WHERE (RDB$SYSTEM_FLAG IS NULL OR RDB$SYSTEM_FLAG = 0)
ORDER BY 2, 1;
