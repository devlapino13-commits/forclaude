-- ============================================================================
-- 08_contdata_trigger_bki_event_1_9.sql
-- Триггер: при смене номера телефона клиента формировать событие БКИ 1.9
-- (блок FL_10_Contact с телефоном).
--
-- Построен по образцу уже существующего автогенерённого триггера
-- CONTDATA_TRG_PIF_UPD (тот же способ определить "номер реально сменился"
-- и различить cell_main/cell_add), плюс паттерн постановки события в очередь
-- из HP_BKI_CALCULATE_LOAN5 (bki_clients -> bki_events).
--
-- CDA_CONT_KIND = 0 - "Сотовый номер" (см. Enum cont_kind, скрин пользователя).
-- cell_main / cell_add - не отдельные хранимые коды, а производные:
-- CDA_CONT_KIND = 0 и CDA_IS_MAIN = 1/0.
--
-- ВАЖНО, требует подтверждения перед деплоем (см. TODO по тексту):
--   1) Реагировать только на основной номер (CDA_IS_MAIN=1) или на любой
--      сотовый (включая добавочный)? Сейчас - только основной.
--   2) Нужно ли ограничивать BKI_CLIENTS только активными/непогашенными
--      кредитами (через BKI_LOANS -> KONTRACT/KONTSTATE), чтобы не слать
--      1.9 по давно закрытым кредитам. Сейчас - без ограничения, TODO ниже.
--   3) Событие 1.9 шлётся под каждый BKC_ID клиента (т.е. под каждый
--      репортящийся в БКИ кредит) - по аналогии с HP_BKI_CALCULATE_LOAN5.
--   4) Payload (сам блок FL_10_Contact с телефоном) не хранится в
--      BKI_EVENTS - предполагается, что он собирается на этапе подготовки
--      пакета (HP_BKI_PREPARE_PACKET5 / HP_BKI_CREATE_PACKETS) из текущего
--      CONTDATA/CONTLIST клиента. Нужно подтвердить, что билдер пакета уже
--      умеет для события 1.9 подставлять FL_10 - если нет, доработка нужна
--      там, а не в этом триггере.
-- ============================================================================

CREATE OR ALTER TRIGGER CONTDATA_AIU_BKI_1_9 FOR CONTDATA
ACTIVE AFTER INSERT OR UPDATE POSITION 5
AS
    DECLARE VARIABLE CONT_KIND D_STR_CODE;
    DECLARE VARIABLE EVENT_ID D_INTEGER;
    DECLARE VARIABLE EVENT_DATE D_DATE;
    DECLARE VARIABLE BKC_ID D_ID;
    DECLARE VARIABLE BEV_ID D_ID;
BEGIN
    -- "Номер реально сменился" - то же условие, что в CONTDATA_TRG_PIF_UPD
    IF (((INSERTING AND NEW.CDA_FROM_CLT_ID IS NOT NULL) OR
         (UPDATING AND NEW.CDA_FROM_CLT_ID IS DISTINCT FROM OLD.CDA_FROM_CLT_ID)) AND
        NEW.CDA_CONT_KIND = 0 AND               -- сотовый номер
        NEW.CDA_IS_MAIN = 1 AND                 -- TODO: убрать, если нужен и cell_add
        NEW.CDA_IS_DELETE = 0) THEN
    BEGIN
        EVENT_DATE = CURRENT_DATE;

        -- код события '1.9...' из справочника bki_event
        EVENT_ID = NULL;
        SELECT ID
        FROM HP_ENUM_LIST('bki_event')
        WHERE CODE STARTING '1.9'
        INTO :EVENT_ID;

        IF (EVENT_ID IS NOT NULL) THEN
        BEGIN
            -- по одному событию на каждый репортящийся в БКИ кредит клиента
            FOR SELECT BKC_ID
                FROM BKI_CLIENTS
                WHERE BKC_FROM_C_ID = NEW.CDA_FROM_C_ID
                -- TODO: ограничить активными/непогашенными кредитами, например
                --   AND EXISTS (SELECT 1 FROM BKI_LOANS bkl
                --               JOIN KONTSTATE ks ON ks.ks_from_k_id = bkl.bkl_object_id
                --               WHERE bkl.bkl_id = BKC_FROM_BKL_ID
                --                 AND bkl.bkl_object_kind = f_objkind('kontract', 'id')
                --                 AND ks.ks_state = 1 AND ks.ks_ol_is_delete = 0)
                INTO :BKC_ID
            DO
            BEGIN
                BEV_ID = NULL;
                SELECT BEV_ID
                FROM BKI_EVENTS
                WHERE BEV_FROM_BKC_ID = :BKC_ID AND
                      BEV_EVENT_ID = :EVENT_ID AND
                      BEV_EVENT_DATE = :EVENT_DATE
                INTO :BEV_ID;

                IF (BEV_ID IS NULL) THEN
                    INSERT INTO BKI_EVENTS (BEV_FROM_BKC_ID, BEV_EVENT_ID, BEV_EVENT_DATE, BEV_STATUS)
                    VALUES (:BKC_ID, :EVENT_ID, :EVENT_DATE, 0);
            END
        END
    END
END
