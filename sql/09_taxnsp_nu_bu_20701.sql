-- ============================================================================
-- 09_taxnsp_nu_bu_20701.sql  (ред. 2)
-- Проверка признака налогового учёта (НУ) для счетов 207 / 20701.
--
-- Ред. 1 ошибочно указывала на TAXNSP - это справочник по старым балансовым
-- группам (BALGROUP), к счетам ЕПС не относится.
--
-- Признак "Всегда НУ = БУ / Всегда НУ = 0" хранится в:
--   REF_ACCBALANCE.AB_TAX_KIND  (балансовый счёт)
--   SYS_ACCBALANCE.SAB_TAX_KIND (системный счёт; null = брать из балансового)
-- Значения: 0 - Всегда БУ = НУ, 1 - Всегда НУ = 0, 2 - НУ может отличаться от БУ.
-- Проводки берут coalesce(sab_tax_kind, ab_tax_kind, 0) (hp_do_kn_operbook_ins).
-- Нужно: для 207 и 20701 итоговое значение = 1, как у 20501 и 20202.
-- ============================================================================

-- 1. Признак на балансовых счетах
select ab_code, ab_name, ab_tax_kind,
       case ab_tax_kind when 0 then 'Всегда БУ = НУ'
                        when 1 then 'Всегда НУ = 0'
                        when 2 then 'НУ может отличаться' end as tax_kind_name
from ref_accbalance
where ab_code in ('207', '20701', '205', '20501', '202', '20202')
order by ab_code;

-- 2. Переопределение на системных счетах (должно быть NULL или 1)
select distinct left(a.acc_code, 5) as bal, s.sab_full_code, s.sab_tax_kind
from ref_account a
join sys_accbalance s on s.sab_id = a.acc_from_sab_id
where a.acc_code starting '20701' or a.acc_code starting '20501' or a.acc_code starting '20202'
order by 1, 2;

-- 3. Исправление, если для 207 / 20701 стоит 0 (выполнять только после проверки п.1)
-- update ref_accbalance set ab_tax_kind = 1 where ab_code in ('207', '20701') and ab_tax_kind <> 1;
