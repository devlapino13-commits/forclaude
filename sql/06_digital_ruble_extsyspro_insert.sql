-- ============================================================================
-- 06_digital_ruble_extsyspro_insert.sql
-- Настройка проекта "Цифровой рубль" (esm_project = 'DigiRub') в EXTSYSPRO.
--
-- Даёт возможность погашения микрозаймов через Цифровой рубль по аналогии
-- со схемой Альфа-Банка (см. hp_extsys_process_one.sql): проводка погашения
-- строится процедурой HP_DO_REPAYMENT на счёт ESP_ACCOUNT_NO, взятый отсюда,
-- БЕЗ каких-либо правок PSQL-кода — механизм полностью управляется данными.
--
-- Комиссия НЕ будет начисляться, т.к. 'DigiRub' сознательно НЕ добавляется
-- в список ('moneta','qiwi','tinkoff','wirebank','CaRuSell') внутри
-- HP_EXTSYS_PROCESS_ONE, который включает комиссионный блок (kommis_al_id).
--
-- ESP_ACCOUNT_NO = AL_ID строки в ACC_LIST для минфиновского счёта 53-01/1
-- (уже существует: al_id = 010181053-01000001, проверено запросом
--  select al_id from acc_list where al_account = '53-01/1').
--
-- ПЕРЕД запуском проверьте/выполните:
--   1) П.1 ТЗ должен быть сделан отдельно (штатным способом, не этим
--      скриптом!) - в REF_ACCOUNT должен быть открыт внутренний ЕПС-счёт
--      20701.810.00.00.00000001, и ACC_LIST.AL_FROM_ACC_ID для
--      al_id = '010181053-01000001' должен на него указывать.
--   2) Уточнить у Цымбалюка В., идёт ли колбэк по ЦР через тот же
--      MNT-XML протокол, что у moneta/tinkoff/wirebank/CaRuSell
--      (hp_extsys_pay.sql, блоки со списком проектов около строк 128, 2069).
--      Если да - 'DigiRub' нужно добавить в эти списки (правка кода).
--      Если у ЦР свой колбэк (напр. отдельный edoc-эндпоинт, который сам
--      создаёт запись в EXTSYSMAIN с esm_project='DigiRub' и esm_action='pay'),
--      то этот INSERT - единственное, что нужно на стороне БД.
-- ============================================================================

INSERT INTO EXTSYSPRO (
    ESP_ID,
    ESP_PROJECT,
    ESP_NAME,
    ESP_PROJECT_KIND,
    ESP_ACCOUNT_NO,
    ESP_STATUS,
    ESP_MEMO,
    ESP_DATE_BEGIN,
    ESP_IS_JSON,
    ESP_IS_INTERNAL_PROTOCOL
)
VALUES (
    (SELECT COALESCE(MAX(ESP_ID), 0) + 1 FROM EXTSYSPRO),
    'DigiRub',
    'Цифровой рубль',
    'payment',
    '010181053-01000001',           -- al_id счёта 53-01/1 (см. комментарий выше)
    1,                                -- 1 - действующий проект
    'Погашения микрозаймов через Цифровой рубль. Без комиссии (RFCRU-XXXX)',
    CURRENT_DATE,
    1,                                -- ответ в JSON; поменяйте на 0, если протокол XML
    0                                 -- 1, если это внутренний протокол МБулак, а не протокол платежной системы
);

-- Проверка результата:
-- select esp_id, esp_project, esp_account_no, esp_status
-- from extsyspro
-- where esp_project = 'DigiRub';
