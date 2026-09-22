# Правки в HP_EXTSYS_PAY для проекта DigiRub (Цифровой рубль)

Оплата ЦР подтверждена как идущая через тот же MNT-XML протокол, что
Moneta/Wirebank/CaRuSell/Tinkoff. Значит `hp_extsys_pay` должен узнавать
`esm_project = 'DigiRub'` как принадлежащий этой группе. Ниже — точные места
правки (процедура целиком не переписывается — правки локальные, вносит
разработчик через IBExpert/аналог, с последующим `CREATE OR ALTER PROCEDURE`).

Источник: `.github.io/procedures/hp_extsys_pay.html` (DDL), ветка на момент
анализа.

## Правка 1 — проверка дублей по txn_id (~строка 128)

Было:

```sql
if (not((:esp_is_internal_protocol = 1 and
    result_id = 1) or (project = 'europlat' and
    result_id = 111) or (project = 'eleksnet' and
    result_id = 60) or (project in ('moneta', 'tinkoff', 'processing_kz', 'Wirebank', 'CaRuSell') and
    result_id = 302))) then
```

Стало:

```sql
if (not((:esp_is_internal_protocol = 1 and
    result_id = 1) or (project = 'europlat' and
    result_id = 111) or (project = 'eleksnet' and
    result_id = 60) or (project in ('moneta', 'tinkoff', 'processing_kz', 'Wirebank', 'CaRuSell', 'DigiRub') and
    result_id = 302))) then
```

## Правка 2 — основной блок обработки платежа "Moneta.ru" (~строка 2069)

Было:

```sql
/* -------------------------------- Moneta.ru ------------------------------*/
if (project in ('moneta', 'tinkoff', 'processing_kz', 'Wirebank', 'CaRuSell')) then
begin
```

Стало:

```sql
/* -------------------------------- Moneta.ru ------------------------------*/
if (project in ('moneta', 'tinkoff', 'processing_kz', 'Wirebank', 'CaRuSell', 'DigiRub')) then
begin
```

## Что НЕ трогаем (сознательно)

- Комиссионный блок в `HP_EXTSYS_PROCESS_ONE` (`if (esm_project in ('moneta', 'qiwi', 'tinkoff', 'wirebank', 'CaRuSell'))`,
  ~строка 112 и ~572 в `hp_extsys_process_one.sql`) — туда `DigiRub`
  **не добавляем**, чтобы комиссия не начислялась (п.2 ТЗ — "без комиссии").
- Основная проводка погашения — управляется данными через `EXTSYSPRO`
  (см. `sql/06_digital_ruble_extsyspro_insert.sql`), кода трогать не нужно.
- Блок `qiwi`-специфичной комиссии (`if (project in ('qiwi','qiwi_test'))`,
  ~строка 1488) — не относится к DigiRub.
- Блоки на ~строках 1376, 1706 используют `esm_project = :project` как
  параметр (не хардкод-список) — их трогать не нужно.

## Порядок внедрения (рекомендация)

1. Открыть в REF_ACCOUNT счёт `20701.810.00.00.00000001`, привязать
   `ACC_LIST.AL_FROM_ACC_ID` для `al_id = '010181053-01000001'` (п.1 ТЗ,
   штатным способом — не через raw SQL).
2. Выполнить `sql/06_digital_ruble_extsyspro_insert.sql`.
3. Внести правки 1 и 2 выше в `HP_EXTSYS_PAY`, задеплоить через
   `CREATE OR ALTER PROCEDURE` (полный текст процедуры взять из живой базы
   в IBExpert, а не из этого файла — здесь только диф, чтобы не рисковать
   потерей/порчей остального тела процедуры при копировании).
4. Прогнать тестовый платёж в тестовом контуре, убедиться, что:
   - проводка погашения ушла на счёт `010181053-01000001` без комиссии;
   - при закрытии месяца проводка попала в экспорт `HP_EXPORT_PACKET_1C`
     (проверочный запрос — в предыдущем анализе, по `SYS_ACCBALANCE.sab_export_1c`);
   - чек в Первый ОФД сформировался (`HP_KKT_INSERT` должен сработать
     автоматически, т.к. не зависит от `esm_project`).
