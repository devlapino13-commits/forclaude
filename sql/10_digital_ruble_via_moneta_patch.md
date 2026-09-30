# Правка HP_EXTSYS_PROCESS_ONE — ЦР через существующий проект `moneta`

Заменяет `sql/06_digital_ruble_extsyspro_insert.sql` и
`sql/07_digital_ruble_hp_extsys_pay_patch.md` — **оба этих файла устарели**,
их применять не нужно. По факту (скрин `EXTSYSPRO`) отдельного проекта под
ЦР не заводят — платёж идёт через уже существующий `esm_project = 'moneta'`
(счёт `010181051-01000018`, комиссия `71702810005310310101`), а способ
оплаты (`card` / `sbp` / `cr`) передаётся отдельным параметром
`MNT_PAYMENT_METHOD` внутри `ESM_FULL_SOURCE`.

Значит нужно не добавлять данные/код для нового проекта, а **разветвить
уже существующую обработку `moneta`** внутри `HP_EXTSYS_PROCESS_ONE` по
значению `MNT_PAYMENT_METHOD`.

Извлечение параметра — по образцу уже имеющегося в этой же процедуре
извлечения `MNT_FEE`:
```sql
select iif(field_value = '', 0, field_value)
from hp_extsys_parcer(:esm_full_source, 'MNT_FEE')
into kommis_amount;
```

## Правка 1 — подменить счёт погашения на ЦР, когда MNT_PAYMENT_METHOD = 'cr'

Было (после выборки `repay_dt_account_no` из `EXTSYSPRO` по `esm_project`):
```sql
    repay_dt_account_no = '';
    select esp_name, esp_account_no, esp_acc_classic, esp_acc_ipf
    from extsyspro
    where esp_project_kind = 'payment' and
          esp_project = :esm_project and
          esp_status = 1
    into :rep_rus_name,
         :repay_dt_account_no,
         classic_acc,
         ipf_acc;

    if (rep_rus_name = '') then
      exit;
```

Стало (добавлен блок сразу после выборки, до `if (rep_rus_name = '')`):
```sql
    repay_dt_account_no = '';
    select esp_name, esp_account_no, esp_acc_classic, esp_acc_ipf
    from extsyspro
    where esp_project_kind = 'payment' and
          esp_project = :esm_project and
          esp_status = 1
    into :rep_rus_name,
         :repay_dt_account_no,
         classic_acc,
         ipf_acc;

    if (rep_rus_name = '') then
      exit;

    -- Цифровой рубль: приходит как esm_project = 'moneta' с
    -- MNT_PAYMENT_METHOD = 'cr'. Счёт погашения подменяем на счёт ЦР
    -- (al_id минфин-счёта 53-01/1), вместо обычного счёта Moneta.
    payment_method = '';
    if (esm_project = 'moneta') then
    begin
      select field_value
      from hp_extsys_parcer(:esm_full_source, 'MNT_PAYMENT_METHOD')
      into :payment_method;

      if (payment_method = 'cr') then
        repay_dt_account_no = '010181053-01000001';
    end
```

Требуется добавить в `declare`-секцию процедуры:
```sql
declare variable payment_method varchar(20);
```

## Правка 2 — убрать комиссию для MNT_PAYMENT_METHOD = 'cr'

Было:
```sql
    if (db_id = 81001) then
    begin
      if (esm_project in ('moneta', 'qiwi', 'tinkoff', 'wirebank', 'CaRuSell')) then
      begin
        kommis_al_id = '010181091-02000003';
        ...
```

Стало:
```sql
    if (db_id = 81001) then
    begin
      if (esm_project in ('moneta', 'qiwi', 'tinkoff', 'wirebank', 'CaRuSell') and
          not (esm_project = 'moneta' and payment_method = 'cr')) then
      begin
        kommis_al_id = '010181091-02000003';
        ...
```

Дальше в блоке ничего менять не нужно — раз `kommis_al_id` остаётся пустым
для `payment_method = 'cr'`, комиссионный блок ниже по коду
(`if (kommis_al_id <> '') then ...`) для ЦР просто не выполнится, как и
раньше для остальных провайдеров без комиссии.

Комиссия = 0 для `cr` действует до 01.01.2027 (подтверждено бизнесом,
после этой даты ЦБ объявит процент — тогда условие `not (... and
payment_method = 'cr')` нужно будет убрать/доработать).

## Что не трогаем

- `HP_EXTSYS_PAY` — правок там больше не нужно: `moneta` уже есть во всех
  нужных списках (дублей по `txn_id`, диспетчер платежа), новый код
  проекта никуда добавлять не требуется.
- `EXTSYSPRO` — новую строку не создаём, существующая запись `moneta`
  не меняется (её `ESP_ACCOUNT_NO` остаётся счётом обычных платежей
  Moneta; счёт ЦР подставляется только в переменной внутри процедуры,
  как в правке 1).

## Открытый вопрос

Нужно подтвердить точное имя параметра `MNT_PAYMENT_METHOD` и его значение
для ЦР (`'cr'`, судя по комментарию Цымбалюка) — это из XML/параметров,
которые реально шлёт edoc. Также стоит проверить у него: приходит ли этот
параметр только при `esm_action = 'pay'` или тоже нужен для `'check'`.
