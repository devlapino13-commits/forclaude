-- ============================================================================
-- 15_digital_ruble_test_payment_check.sql
-- RFCRU-5822: проверка тестового платежа ЦР (тестовая БД).
-- Транзакция 1791279466487089597, 100 руб., K_ID 1010101195843003 01,
-- MNT_PAYMENT_METHOD=cr, MNT_FEE=0.00.
-- Только SELECT, ничего не меняет. Для другого платежа заменить trans_id во всех запросах.
-- ============================================================================

-- 1. Платёж в EXTSYSMAIN: должен быть pay со статусом 1 (обработан), проект moneta,
--    payment_method = cr.
select e.esm_id, e.esm_action, e.esm_status, e.esm_project, e.esm_from_k_id, e.esm_amount,
       (select field_value from hp_extsys_parcer(e.esm_full_source, 'MNT_PAYMENT_METHOD')) as payment_method,
       (select field_value from hp_extsys_parcer(e.esm_full_source, 'MNT_FEE')) as mnt_fee
from extsysmain e
where e.esm_trans_id = '1791279466487089597'
order by e.esm_id;

-- 2. Операции по платежу (головная + дочерние).
--    Ожидается: операция погашения есть, is_delete = 0;
--    операции комиссии (ol_oper_subtype = 36, "Комиссия за погашение через moneta") НЕТ.
select ol.ol_id, ol.ol_parent_id, ol.ol_date, ol.ol_oper_type, ol.ol_oper_subtype, ol.is_delete, ol.ol_memo
from extsysmain e
join extsysoper eso on eso.eso_from_esm_id = e.esm_id
join operlist ol on ol.ol_id = eso.eso_from_ol_id or ol.ol_parent_id = eso.eso_from_ol_id
where e.esm_trans_id = '1791279466487089597'
order by ol.ol_id;

-- 3. Вид и счёт поступления (OPERLOAN).
--    Ожидается: opl_acc_kind = 2 (банк, не коррекция), al_account = 53-01/1.
select opl.opl_from_ol_id, opl.opl_acc_kind, opl.opl_from_al_id, al.al_account, a.acc_code
from extsysmain e
join extsysoper eso on eso.eso_from_esm_id = e.esm_id
join operlist ol on ol.ol_id = eso.eso_from_ol_id or ol.ol_parent_id = eso.eso_from_ol_id
join operloan opl on opl.opl_from_ol_id = ol.ol_id
left join acc_list al on al.al_id = opl.opl_from_al_id
left join ref_account a on a.acc_id = opl.opl_from_acc_id
where e.esm_trans_id = '1791279466487089597'
order by opl.opl_from_ol_id;

-- 4. Проводки минфин (OPERBOOK).
--    Ожидается: Дт 53-01/1 (а не 51-01/24 / 51-01/26), сумма 100,
--    проводок по счёту комиссии 010181091-02000003 нет.
select ob.ob_from_ol_id, al_dt.al_account as acc_dt, al_kt.al_account as acc_kt,
       ob.ob_summa, ob.ob_currency, ob.ob_detail, ob.ob_ol_is_active
from extsysmain e
join extsysoper eso on eso.eso_from_esm_id = e.esm_id
join operlist ol on ol.ol_id = eso.eso_from_ol_id or ol.ol_parent_id = eso.eso_from_ol_id
join operbook ob on ob.ob_from_ol_id = ol.ol_id
left join acc_list al_dt on al_dt.al_id = ob.ob_account_dt
left join acc_list al_kt on al_kt.al_id = ob.ob_account_kt
where e.esm_trans_id = '1791279466487089597'
order by ob.ob_from_ol_id, ob.ob_account_dt;

-- 5. Проводки ЕПС (KN_OPERBOOK).
--    Ожидается: Дт 20701810000000000001 (ЦифрСчет), сумма 100;
--    kob_summa_tax_dt = 0, если Грабовская уже выставила НУ = 0 на "Деньги.Безнал.Банк.ЦифрСчет"
--    (иначе НУ = БУ = 100 - признак ещё не исправлен).
select k.kob_from_ol_id, a_dt.acc_code as acc_dt, s_dt.sab_full_code as sab_dt,
       a_kt.acc_code as acc_kt, s_kt.sab_full_code as sab_kt,
       k.kob_summa, k.kob_summa_tax_dt, k.kob_summa_tax_kt, k.kob_ol_is_active
from extsysmain e
join extsysoper eso on eso.eso_from_esm_id = e.esm_id
join operlist ol on ol.ol_id = eso.eso_from_ol_id or ol.ol_parent_id = eso.eso_from_ol_id
join kn_operbook k on k.kob_from_ol_id = ol.ol_id
join ref_account a_dt on a_dt.acc_id = k.kob_acc_dt
join ref_account a_kt on a_kt.acc_id = k.kob_acc_kt
join sys_accbalance s_dt on s_dt.sab_id = a_dt.acc_from_sab_id
join sys_accbalance s_kt on s_kt.sab_id = a_kt.acc_from_sab_id
where e.esm_trans_id = '1791279466487089597'
order by k.kob_from_ol_id, k.kob_id;

-- 6. Чек ККТ (п.4 ТЗ - как при безнале).
--    Ожидается: 1 чек, kkm_kkt_kind = 1 (Первый ОФД, облако), kkm_corr_ol_id пусто (не коррекция),
--    kkm_is_return = 0; позиции - только проценты. Если в платеже не было процентов - чека может не быть.
select kkm.kkm_id, kkm.kkm_from_ol_id, kkm.kkm_kkt_kind, kkm.kkm_is_return, kkm.kkm_corr_ol_id,
       kkm.kkm_status, kkm.kkm_ol_is_delete, kki.kki_type, kki.kki_amount
from extsysmain e
join extsysoper eso on eso.eso_from_esm_id = e.esm_id
join operlist ol on ol.ol_id = eso.eso_from_ol_id or ol.ol_parent_id = eso.eso_from_ol_id
join kkt_main kkm on kkm.kkm_from_ol_id = ol.ol_id
left join kkt_items kki on kki.kki_from_kkm_id = kkm.kkm_id
where e.esm_trans_id = '1791279466487089597'
order by kkm.kkm_id;

-- 7. Попадание в экспорт 1С (п.3 ТЗ): проводки дня с 20701 - именно их отберёт
--    новое условие HP_EXPORT_PACKET_1C. Подставить дату платежа (ol_date из запроса 2).
select a_dt.acc_code as acc_dt, a_kt.acc_code as acc_kt, sum(k.kob_summa) as summa, count(*) as cnt
from kn_operbook k
join ref_account a_dt on a_dt.acc_id = k.kob_acc_dt
join ref_account a_kt on a_kt.acc_id = k.kob_acc_kt
where k.kob_ol_date = current_date   -- дата платежа
  and k.kob_ol_is_active = 1
  and (a_dt.acc_code starting '20701' or a_kt.acc_code starting '20701')
group by 1, 2;

-- 8. Для сравнения: последние обычные платежи moneta (не ЦР) - у них Дт должен остаться
--    прежний счёт (ESP_ACCOUNT_NO проекта / 51-01/24 / 51-01/26) и комиссия по MNT_FEE.
select first 5 e.esm_trans_id, e.esm_amount,
       (select field_value from hp_extsys_parcer(e.esm_full_source, 'MNT_PAYMENT_METHOD')) as payment_method,
       (select field_value from hp_extsys_parcer(e.esm_full_source, 'MNT_FEE')) as mnt_fee,
       al_dt.al_account as acc_dt, ob.ob_summa
from extsysmain e
join extsysoper eso on eso.eso_from_esm_id = e.esm_id
join operbook ob on ob.ob_from_ol_id = eso.eso_from_ol_id
left join acc_list al_dt on al_dt.al_id = ob.ob_account_dt
where e.esm_project = 'moneta'
  and e.esm_action = 'pay'
  and e.esm_status = 1
  and e.esm_trans_id <> '1791279466487089597'
order by e.esm_id desc;
