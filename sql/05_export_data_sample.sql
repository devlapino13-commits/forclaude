-- ============================================================================
-- 05_export_data_sample.sql
-- Выгрузка данных: до 100 САМЫХ СВЕЖИХ строк с каждой пользовательской таблицы.
--
-- Это анонимный PSQL-блок (EXECUTE BLOCK) - выполняется один раз как обычный
-- запрос, ничего не создаёт и не меняет в базе. Работает в SQL-редакторе
-- IBExpert так же, как обычный SELECT: результат - грид, который нужно
-- экспортировать (правой кнопкой по гриду -> Export Data / Save to file,
-- формат CSV; в качестве разделителя внутри ROW_TEXT используется '|').
--
-- "Свежесть" определяется эвристически для каждой таблицы отдельно:
--   1) если есть колонка типа DATE/TIMESTAMP - сортируем по ней DESC
--      (среди нескольких таких колонок в приоритете поля с именем вроде
--      "дата изменения/обновления", затем "дата создания", затем любая
--      другая дата/время);
--   2) если такой колонки нет - сортируем по первому полю первичного
--      ключа DESC (обычно это автоинкремент, и большие значения -
--      более новые записи);
--   3) если нет ни того, ни другого - строки берутся без сортировки
--      (свежесть не гарантируется).
-- Строка ROW_TYPE = 'SORTBY' в результате показывает, по какой колонке и
-- по какому правилу отсортирована каждая таблица.
--
-- Настройки ниже можно менять:
--   MAXROWS - сколько строк выгружать на таблицу (по умолчанию 100)
--   DO_MASK - 1: маскировать колонки с "чувствительными" именами, 0: не маскировать
--
-- Таблицы с именем, начинающимся на "UX$" (служебные таблицы IBExpert),
-- в выгрузку не включаются.
-- ============================================================================

EXECUTE BLOCK
RETURNS (
    TABLE_NAME VARCHAR(63),
    ROW_TYPE   VARCHAR(10),
    ROW_TEXT   VARCHAR(4000)
)
AS
    DECLARE VARIABLE REL_NAME     VARCHAR(63);
    DECLARE VARIABLE FLD_NAME     VARCHAR(63);
    DECLARE VARIABLE FLD_TYPE     SMALLINT;
    DECLARE VARIABLE FLD_SUBTYPE  SMALLINT;
    DECLARE VARIABLE COL_LIST     VARCHAR(8000);
    DECLARE VARIABLE HDR_LIST     VARCHAR(4000);
    DECLARE VARIABLE COL_EXPR     VARCHAR(500);
    DECLARE VARIABLE SQL_TEXT     VARCHAR(8000);
    DECLARE VARIABLE LINE_TEXT    VARCHAR(4000);
    DECLARE VARIABLE FIRST_COL    SMALLINT;
    DECLARE VARIABLE IS_SENSITIVE SMALLINT;
    DECLARE VARIABLE MAXROWS      INTEGER;
    DECLARE VARIABLE DO_MASK      SMALLINT;
    DECLARE VARIABLE DATE_COL     VARCHAR(63);
    DECLARE VARIABLE DATE_SCORE   SMALLINT;
    DECLARE VARIABLE CUR_SCORE    SMALLINT;
    DECLARE VARIABLE PK_COL       VARCHAR(63);
    DECLARE VARIABLE ORDER_COL    VARCHAR(63);
BEGIN
    MAXROWS = 100;
    DO_MASK = 1;

    FOR SELECT TRIM(RDB$RELATION_NAME)
        FROM RDB$RELATIONS
        WHERE (RDB$SYSTEM_FLAG IS NULL OR RDB$SYSTEM_FLAG = 0)
          AND RDB$VIEW_BLR IS NULL
          AND RDB$RELATION_NAME NOT STARTING WITH 'UX$'
        ORDER BY 1
        INTO :REL_NAME
    DO
    BEGIN
        COL_LIST   = '';
        HDR_LIST   = '';
        FIRST_COL  = 1;
        DATE_COL   = NULL;
        DATE_SCORE = 0;
        PK_COL     = NULL;

        FOR SELECT TRIM(rf.RDB$FIELD_NAME), f.RDB$FIELD_TYPE, f.RDB$FIELD_SUB_TYPE
            FROM RDB$RELATION_FIELDS rf
            JOIN RDB$FIELDS f ON f.RDB$FIELD_NAME = rf.RDB$FIELD_SOURCE
            WHERE rf.RDB$RELATION_NAME = :REL_NAME
            ORDER BY rf.RDB$FIELD_POSITION
            INTO :FLD_NAME, :FLD_TYPE, :FLD_SUBTYPE
        DO
        BEGIN
            -- Ищем лучшую колонку-кандидата на "дату свежести"
            IF (FLD_TYPE IN (12, 35)) THEN               -- DATE / TIMESTAMP
            BEGIN
                CUR_SCORE = 1;
                IF (FLD_NAME CONTAINING 'ИЗМЕН' OR FLD_NAME CONTAINING 'ОБНОВ'
                    OR FLD_NAME CONTAINING 'MODIF' OR FLD_NAME CONTAINING 'UPDATE') THEN
                    CUR_SCORE = 3;
                ELSE IF (FLD_NAME CONTAINING 'СОЗДАН' OR FLD_NAME CONTAINING 'CREATE'
                    OR FLD_NAME CONTAINING 'ДАТА' OR FLD_NAME CONTAINING 'DATE') THEN
                    CUR_SCORE = 2;

                IF (CUR_SCORE > DATE_SCORE) THEN
                BEGIN
                    DATE_SCORE = CUR_SCORE;
                    DATE_COL   = FLD_NAME;
                END
            END

            IS_SENSITIVE = CASE WHEN (
                   FLD_NAME CONTAINING 'PASSPORT' OR FLD_NAME CONTAINING 'ПАСПОРТ'
                OR FLD_NAME CONTAINING 'SNILS'    OR FLD_NAME CONTAINING 'СНИЛС'
                OR FLD_NAME CONTAINING 'INN'      OR FLD_NAME CONTAINING 'ИНН'
                OR FLD_NAME CONTAINING 'CARD'     OR FLD_NAME CONTAINING 'КАРТ'
                OR FLD_NAME CONTAINING 'PHONE'    OR FLD_NAME CONTAINING 'ТЕЛЕФОН'
                OR FLD_NAME CONTAINING 'EMAIL'    OR FLD_NAME CONTAINING 'ПОЧТА'
                OR FLD_NAME CONTAINING 'ADDRESS'  OR FLD_NAME CONTAINING 'АДРЕС'
                OR FLD_NAME CONTAINING 'ACCOUNT'  OR FLD_NAME CONTAINING 'СЧЕТ' OR FLD_NAME CONTAINING 'СЧЁТ'
                OR FLD_NAME CONTAINING 'IBAN'
                OR FLD_NAME CONTAINING 'FIO'      OR FLD_NAME CONTAINING 'ФИО'
                OR FLD_NAME CONTAINING 'SURNAME'  OR FLD_NAME CONTAINING 'ФАМИЛ'
                OR FLD_NAME CONTAINING 'NAME'     OR FLD_NAME CONTAINING 'ИМЯ' OR FLD_NAME CONTAINING 'ОТЧЕСТВ'
                OR FLD_NAME CONTAINING 'BIRTH'    OR FLD_NAME CONTAINING 'РОЖД'
                OR FLD_NAME CONTAINING 'SALARY'   OR FLD_NAME CONTAINING 'ЗАРПЛАТ' OR FLD_NAME CONTAINING 'ДОХОД'
                OR FLD_NAME CONTAINING 'BALANCE'  OR FLD_NAME CONTAINING 'БАЛАНС'
                OR FLD_NAME CONTAINING 'SUM'      OR FLD_NAME CONTAINING 'СУММ' OR FLD_NAME CONTAINING 'AMOUNT'
            ) THEN 1 ELSE 0 END;

            IF (FIRST_COL = 0) THEN
            BEGIN
                COL_LIST = COL_LIST || ' || ''|'' || ';
                HDR_LIST = HDR_LIST || '|';
            END

            IF (DO_MASK = 1 AND IS_SENSITIVE = 1) THEN
                COL_EXPR = '''*** MASKED ***''';
            ELSE IF (FLD_TYPE IN (14, 37)) THEN                       -- CHAR / VARCHAR
                COL_EXPR = 'COALESCE(SUBSTRING("' || FLD_NAME || '" FROM 1 FOR 300), ''<NULL>'')';
            ELSE IF (FLD_TYPE = 261 AND FLD_SUBTYPE = 1) THEN          -- BLOB SUB_TYPE TEXT
                COL_EXPR = 'COALESCE(SUBSTRING("' || FLD_NAME || '" FROM 1 FOR 300), ''<NULL>'')';
            ELSE IF (FLD_TYPE = 261) THEN                              -- BLOB SUB_TYPE BINARY / прочее
                COL_EXPR = '''<BLOB>''';
            ELSE
                COL_EXPR = 'COALESCE(CAST("' || FLD_NAME || '" AS VARCHAR(100)), ''<NULL>'')';

            COL_LIST = COL_LIST || COL_EXPR;
            HDR_LIST = HDR_LIST || FLD_NAME;
            FIRST_COL = 0;
        END

        -- Первое поле первичного ключа - запасной критерий "свежести"
        SELECT FIRST 1 TRIM(s.RDB$FIELD_NAME)
        FROM RDB$RELATION_CONSTRAINTS rc
        JOIN RDB$INDEX_SEGMENTS s ON s.RDB$INDEX_NAME = rc.RDB$INDEX_NAME
        WHERE rc.RDB$RELATION_NAME = :REL_NAME
          AND rc.RDB$CONSTRAINT_TYPE = 'PRIMARY KEY'
        ORDER BY s.RDB$FIELD_POSITION
        INTO :PK_COL;

        ORDER_COL = COALESCE(DATE_COL, PK_COL);

        TABLE_NAME = REL_NAME;
        ROW_TYPE   = 'HEADER';
        ROW_TEXT   = HDR_LIST;
        SUSPEND;

        TABLE_NAME = REL_NAME;
        ROW_TYPE   = 'SORTBY';
        ROW_TEXT   = CASE
                        WHEN DATE_COL IS NOT NULL THEN DATE_COL || ' DESC (дата/время)'
                        WHEN PK_COL IS NOT NULL THEN PK_COL || ' DESC (первичный ключ, эвристика)'
                        ELSE '<нет колонки для сортировки, свежесть не гарантирована>'
                     END;
        SUSPEND;

        IF (COL_LIST <> '') THEN
        BEGIN
            IF (ORDER_COL IS NOT NULL) THEN
                SQL_TEXT = 'SELECT ' || COL_LIST || ' FROM "' || REL_NAME
                           || '" ORDER BY "' || ORDER_COL || '" DESC ROWS '
                           || CAST(MAXROWS AS VARCHAR(10));
            ELSE
                SQL_TEXT = 'SELECT ' || COL_LIST || ' FROM "' || REL_NAME
                           || '" ROWS ' || CAST(MAXROWS AS VARCHAR(10));

            FOR EXECUTE STATEMENT :SQL_TEXT INTO :LINE_TEXT
            DO
            BEGIN
                TABLE_NAME = REL_NAME;
                ROW_TYPE   = 'DATA';
                ROW_TEXT   = LINE_TEXT;
                SUSPEND;
            END
        END
    END
END
