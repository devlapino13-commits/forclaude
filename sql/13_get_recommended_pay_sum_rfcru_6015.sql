-- RFCRU-6015 (ред. 5): рекомендуемый платёж при просрочке.
-- Исправлено относительно ред. 1:
--   1) "просрочки нет, есть только пеня" -> пеня + ближайший платёж без условия 10 дней (раньше ближайший отсекался окном);
--   2) окно "10 и менее календарных дней" = next_sh_date - rep_date <= 10 (раньше rep_date + 9, т.е. <= 9);
--   3) пеня по просроченным платежам включается всегда, в т.ч. при > 10 днях до ближайшего платежа
--      (ред. 4: заказчик считает пеню частью просроченной суммы - Муминова 3 872 + 2 = 3 874,
--      Музаффаров 14 817 + 9 + 8 = 14 834; в ред. 3 пеня при > 10 днях не бралась).
-- Новая логика - только для РФ (db_id = 81001), как в RFCRU-4811; для остальных баз (кроме КЗ/КГ)
-- оставлено прежнее окно rep_date + 9 (ред. 5).
-- Ветки КЗ/КГ, расторжения и "нет просрочки" не менялись.

create or alter procedure get_recommended_pay_sum (
    k_id id_type,
    rep_date date)
returns (
    recom_pay_sum curr_type)
as
declare variable rep_date_limit date;
declare variable min_sh_date date;
declare variable db_id integer;
declare variable sh_date date;
declare variable pr_code d_str_100;
declare variable insurance_amount curr_type;
declare variable delinq_body curr_type;
declare variable delinq_fine curr_type;
declare variable next_sh_date date;
declare variable next_pay_sum curr_type;
begin
  /*
    Igusev: Логика согласованная с Зарой (02.04.2019):
    если просрочка есть, тогда: вся просроченная сумма + сумма ближайшего платежа (ОС + проценты по графику), который наступит в пределах текущая дата + 10 дней, причем если сегодня 02.04, то +10 дней должна быть 11.04
    если просроченного платежа нет, то должна отображаться сумма ближайшего платежа по графику (ОС + проценты по графику), причем не важно чз сколько дней этот платеж настанет.
  */
  db_id = f_get_db_id();

  /*
  select oks_delinq_date
  from oksummary oks
  where oks_from_k_id = :k_id and
        :rep_date between oks_date_begin and oks_date_end
  into min_sh_date;
  */

  -- т.к. возможна ситуация когда по платежу есть долг только по пеням и этот платеж прочрочен
  -- и чз  oksummary  его не понймать, решил искать дату самого раннего активного платежа чз aarep_make_zad_list
  -- письмо: Subject: RE: Re: группа 4-15-19-116 - из-за округления возникла разница в 1 рубль. .

  if (db_id in (39801, 41701)) then
  begin
    select min(coalesce(sh_date, cast('01.01.1900' as date)))
    from aarep_make_zad_list(:k_id, :rep_date, 1)
    where sh_date is not null
    into :min_sh_date;

    rep_date_limit = rep_date + 20;

    if (min_sh_date < rep_date or min_sh_date is null ) then
    begin
      select sum(zad_os + iif(coalesce(sh_date, :rep_date) <= :rep_date, sh_calc_perc, zad_perc) + sh_calc_fine + zad_kommis + iif(:db_id <> 39801, round(zad_perc * 2 / 100,0), 0))
      from aarep_make_zad_list(:k_id, :rep_date, 1)
      where coalesce(sh_date, :rep_date_limit) <= :rep_date_limit
      into recom_pay_sum;
    end else
    begin
      select sh_date, zad_os + zad_perc + iif(:db_id <> 39801, round(zad_perc * 2 / 100,0), 0)
      from aarep_make_zad_list(:k_id, :rep_date, 0)
      where sh_date >= :rep_date
      rows 1
      into sh_date, recom_pay_sum;

      -- Для КЗ при реструктуризации выводим сумму первого платежа, не учитывая условие с 20 днями
      if (not(db_id = 39801 and
              exists(select *
                     from aarep_get_restructuring(:k_id, :rep_date, :db_id)
                     where is_restruct = 1))) then
      begin
        if (:rep_date <= :sh_date - 20) then recom_pay_sum = 0;
      end
    end
  end else
  begin
    select min(coalesce(sh_date, cast('01.01.1900' as date)))
    from aarep_make_zad_list(:k_id, :rep_date, 1)
    into :min_sh_date;

    --  если было расторжение договора то отображаем всю задолженность.
    if (exists(select *
               from kontract, operlist
               where k_id = :k_id and
                     k_stopped_perc_ol_id = ol_id and
                     operlist.is_delete = 0 and
                     ol_date <= :rep_date)) then
        
    begin
      select sum(zad_os + sh_calc_perc + sh_calc_fine + zad_kommis)
      from aarep_make_zad_list(:k_id, :rep_date, 1)
      into recom_pay_sum;
    end
    else
    if (min_sh_date < rep_date or min_sh_date is null) then
    begin
      -- RFCRU-6015 ред. 5: новая логика только для РФ (как и RFCRU-4811); остальные базы - прежнее окно +9 дней
      if (db_id = 81001) then
      begin
        -- RFCRU-6015 ред. 4: рекомендуемый платёж при наличии просрочки/пени
        --   есть просрочка (ОД/%), до ближайшего платежа > 10 дней:  просрочка + пеня
        --   есть просрочка (ОД/%), до ближайшего платежа <= 10 дней: просрочка + пеня + ближайший платёж
        --   просрочки (ОД/%) нет, есть только пеня:                  пеня + ближайший платёж (без условия 10 дней)

        -- просроченная часть: платежи с датой до даты отчёта (и строки без даты)
        select sum(zad_os + sh_calc_perc + zad_kommis), sum(sh_calc_fine)
        from aarep_make_zad_list(:k_id, :rep_date, 1)
        where coalesce(sh_date, '01.01.1900') < :rep_date
        into delinq_body, delinq_fine;
        delinq_body = coalesce(delinq_body, 0);
        delinq_fine = coalesce(delinq_fine, 0);

        -- ближайший платёж по графику (сегодня или позже)
        next_sh_date = null;
        next_pay_sum = 0;
        select first 1 sh_date, zad_os + zad_perc + sh_calc_fine + zad_kommis
        from aarep_make_zad_list(:k_id, :rep_date, 1)
        where sh_date >= :rep_date
        order by sh_date
        into next_sh_date, next_pay_sum;
        next_pay_sum = coalesce(next_pay_sum, 0);

        if (delinq_body > 0) then
          recom_pay_sum = delinq_body + delinq_fine +
                          iif(next_sh_date is not null and next_sh_date - rep_date <= 10, next_pay_sum, 0);
        else
          recom_pay_sum = delinq_fine + next_pay_sum;
      end
      else
      begin
        rep_date_limit = rep_date + 9;

        select sum(zad_os + iif(coalesce(sh_date, :rep_date) <= :rep_date, sh_calc_perc, zad_perc) + sh_calc_fine + zad_kommis)
        from aarep_make_zad_list(:k_id, :rep_date, 1)
        where coalesce(sh_date, :rep_date_limit) <= :rep_date_limit
        into recom_pay_sum;
      end
    end
    else
      select zad_os + zad_perc
      from aarep_make_zad_list(:k_id, :rep_date, 0)
      where sh_date >= :rep_date
      rows 1
      into recom_pay_sum;
  end

  recom_pay_sum = coalesce(recom_pay_sum, 0);

  select pr.pr_code
  from kontract k
  inner join product pr on pr.pr_id = k.k_from_pr_id
  where k.k_id = :k_id
  into :pr_code;

  if (db_id = 41701 and             -- RFCKG-5391
      pr_code containing '.ipf.' and
      pr_code not containing '.ignore_insurance.' and
      f_get_const('kont_insurance_active') = 1) then
  begin
    if (exists(select 1
               from kontstate ks
               where ks.ks_from_k_id = :k_id and
                     ks.ks_ol_is_delete = 0 and
                     ks.ks_state = 1 and
                     current_date between ks.ks_date_begin and ks.ks_date_end)) then
    begin
      select coalesce(res_amount, 0)
      from hp_opercash_loan_other_amount(:k_id, 'CashTransactionIncom.Insurance')
      into :insurance_amount;   -- сумма страхового полиса к оплате

      if (insurance_amount > 0) then
          recom_pay_sum = recom_pay_sum + insurance_amount;  -- добавляем сумма страхового полиса к рекомендуемой сумме
    end
  end

  suspend;
end