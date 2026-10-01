# Правка HP_EXTSYS_PROCESS_ONE — ЦР через существующий проект `moneta`

Ред. 2 (01.10.2026) — исправлены две ошибки первой редакции, см. «Что
изменилось» внизу.

Заменяет `sql/06_digital_ruble_extsyspro_insert.sql` и
`sql/07_digital_ruble_hp_extsys_pay_patch.md` — оба устарели, не применять.

Отдельного проекта под ЦР нет: платёж идёт через существующий
`esm_project = 'moneta'` (счёт `010181051-01000018`), способ оплаты
передаётся в `ESM_FULL_SOURCE` параметром `MNT_PAYMENT_METHOD`
(`card` / `sbp` / `cr`). Проводки по ТЗ — **только для `cr`**; для `sbp`
(СБП через Альфа-Банк) ничего не меняем — будет отдельная задача.

Все правки — внутри `HP_EXTSYS_PROCESS_ONE`, только для `db_id = 81001`.

## Предусловие (п.1 ТЗ)

`ACC_LIST.AL_FROM_ACC_ID` для `al_id = '010181053-01000001'` (53-01/1)
сейчас `NULL`. Пока счёт 20701 не открыт в `REF_ACCOUNT` и не привязан,
проводка по новому плану счетов (ЕПС) для ЦР не построится. Деплоить
правки ниже — только после п.1.

## Правка 0 — объявить переменную

```sql
declare variable payment_method d_str_20;
```

## Правка 1 — счёт погашения ЦР вместо счёта Moneta

Вставить сразу после выборки из `EXTSYSPRO` и проверки `rep_rus_name`
(до блока `if (db_id = 81001) then ... kommis_al_id = ...`, чтобы
`moneta_acc_id` там посчитался уже от счёта ЦР):

```sql
    if (rep_rus_name = '') then
      exit;

    -- RFCRU-5822: Цифровой рубль приходит как moneta + MNT_PAYMENT_METHOD = 'cr'
    payment_method = '';
    if (db_id = 81001 and esm_project = 'moneta') then
    begin
      select field_value
      from hp_extsys_parcer(:esm_full_source, 'MNT_PAYMENT_METHOD')
      into :payment_method;
      payment_method = lower(trim(coalesce(payment_method, '')));

      if (payment_method = 'cr') then
        repay_dt_account_no = (select al_id
                               from acc_list
                               where al_from_reg_id = 1010100 and
                                     al_account = '53-01/1' and
                                     al_currency = '810');
    end
```

(Счёт ищется по `al_account = '53-01/1'` так же, как в процедуре ищутся
`51-01/24` / `51-01/26`, а не хардкодом `al_id`.)

## Правка 2 — комиссия = 0 для ЦР (блок комиссии НЕ отключаем)

Комиссионный блок для `moneta` (`kommis_al_id = '010181091-02000003'`)
**оставляем как есть** — от него зависит вид счёта в `hp_do_repayment`:
`iif(:kommis_al_id = '', 3, 2)`. Для moneta/Альфы это `2` («приём напрямую
на расчётный счёт»), и ЦР должен идти так же — иначе изменится
`OPERLOAN.OPL_ACC_KIND`, а `HP_KKT_INSERT` будет считать погашения,
проведённые не в день операции, чеками коррекции.

Обнуляем только сумму комиссии — в расчёте `kommis_amount`:

Было:
```sql
            if (esm_project in ('moneta', 'tinkoff', 'wirebank', 'CaRuSell')) then
            begin
              select iif(field_value = '', 0, field_value)
              from hp_extsys_parcer(:esm_full_source, 'MNT_FEE')
              into kommis_amount;
              kommis_amount = -kommis_amount;
            end
```

Стало:
```sql
            if (esm_project in ('moneta', 'tinkoff', 'wirebank', 'CaRuSell')) then
            begin
              select iif(field_value = '', 0, field_value)
              from hp_extsys_parcer(:esm_full_source, 'MNT_FEE')
              into kommis_amount;
              kommis_amount = -kommis_amount;

              -- ЦР без комиссии до 01.01.2027 (решение ЦБ), даже если edoc передал fee
              if (payment_method = 'cr') then
                kommis_amount = 0;
            end
```

При `kommis_amount = 0` проводка по комиссии не строится (дальше по коду
стоит `if (kommis_amount <> 0)`).

## Правка 3 — не перебивать счёт ЦР для продуктов Oivo

Ниже по процедуре для `db_id = 81001` есть блок, который для продуктов
`.oivo_pack.` **перезаписывает** `repay_dt_account_no` на `51-01/24`
(или `51-01/26` для Wirebank). Без правки ЦР-платёж по займу Oivo уйдёт
на `51-01/24`, а не на `53-01/1`.

Было:
```sql
      if (:pr_code containing '.oivo_pack.') then
      begin
        repay_dt_account_no = (select al_id ...
```

Стало (вариант по умолчанию — Oivo ЦР не принимаем на 51-01/24):
```sql
      if (:pr_code containing '.oivo_pack.' and payment_method <> 'cr') then
      begin
        repay_dt_account_no = (select al_id ...
```

**Открытый вопрос к бухгалтерии**: если Oivo — отдельная организация,
её погашения ЦР не должны попадать на счёт ЦР М Булак (53-01/1). Тогда
нужен отдельный счёт ЦР для Oivo, а правку 3 надо делать иначе. Решить
до деплоя.

## Что не трогаем

- `HP_EXTSYS_PAY` — `moneta` уже во всех нужных списках.
- `EXTSYSPRO` — строку `moneta` не меняем.
- `MNT_PAYMENT_METHOD = 'sbp'` / `'card'` — поведение без изменений.

## Что изменилось относительно ред. 1

1. **Правка 2 в ред. 1 была ошибочной**: она исключала ЦР из комиссионного
   блока целиком, из-за чего `kommis_al_id` оставался пустым и вид счёта в
   `hp_do_repayment` менялся с `2` на `3` — неверный `OPL_ACC_KIND` и
   риск ложных чеков коррекции в ОФД (п.4 ТЗ). Теперь блок сохраняется,
   обнуляется только сумма.
2. **Пропущен блок Oivo**, который перезаписывал счёт погашения уже после
   правки 1 — добавлена правка 3.
3. Счёт ЦР ищется по `al_account = '53-01/1'`, а не хардкодом `al_id`;
   значение `MNT_PAYMENT_METHOD` нормализуется (`lower`/`trim`).
