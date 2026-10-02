-- RFCRU-5822, п.3 ТЗ: добавить в экспорт сводных проводок в 1С проводки со счётом 20701 (Цифровой рубль).
-- Изменение одно - новое условие в блоке OR (помечено комментарием RFCRU-5822).

create or alter procedure hp_export_packet_1c (
    rep_date_begin date,
    rep_date_end date,
    un_id id_type,
    full_recreate integer = 0)
as
declare variable rep_date date;
declare variable pck_id integer;
declare variable pck_invalid integer;
declare variable pck_kind integer;
declare variable kob_acc_dt id_type;
declare variable kob_acc_kt id_type;
declare variable kob_summa curr_type;
declare variable kob_summa_val curr_type;
declare variable kob_summa_tax_dt curr_type;
declare variable kob_summa_tax_kt curr_type;
declare variable kob_detail_id id_type;
begin
  rep_date = rep_date_begin;
  pck_kind = 1;
  while (rep_date <= rep_date_end) do
  begin
    pck_id = null;
    pck_invalid = null;
    select pck_id, pck_invalid
    from packet_1c
    where pck_date = :rep_date and
          pck_kind = :pck_kind
    into :pck_id, :pck_invalid;

    if (pck_id is not null) then
    begin
      if (pck_invalid = 0 and
          full_recreate = 0) then
      begin
        rep_date = dateadd(day, 1, rep_date);
        continue;
      end
      else
      begin
        delete from packet_1c
        where pck_id = :pck_id;

        pck_id = null;
      end
    end

    insert into packet_1c (pck_date, pck_kind, pck_invalid, pck_excel_done, pck_un_id)
    values (:rep_date, :pck_kind, 0, 0, :un_id)
    returning pck_id
    into :pck_id;

    for select f_get_acc_common_id(a_dt.acc_id, a_dt.acc_code, s_dt.sab_full_code, a_dt.acc_object_kind, a_dt.acc_object_id),
               f_get_acc_common_id(a_kt.acc_id, a_kt.acc_code, s_kt.sab_full_code, a_kt.acc_object_kind, a_kt.acc_object_id),
               kob_detail_id, sum(kob_summa), sum(kob_summa_val), sum(kob_summa_tax_dt), sum(kob_summa_tax_kt)
        from kn_operbook
        inner join ref_account a_dt on (kob_acc_dt = a_dt.acc_id)
        inner join ref_account a_kt on (kob_acc_kt = a_kt.acc_id)
        inner join sys_accbalance s_dt on (a_dt.acc_from_sab_id = s_dt.sab_id)
        inner join sys_accbalance s_kt on (a_kt.acc_from_sab_id = s_kt.sab_id)
        where kob_ol_date = :rep_date and
              kob_ol_is_active = 1 and
              not(s_dt.sab_full_code in ('Деньги.Безнал.Банк.РасчСчет', 'Деньги.Безнал.Банк.СпецСчет') and
              s_kt.sab_full_code = 'ПлатСистемы.Погашено') and
              ((s_dt.sab_export_1c = 1 or
              s_kt.sab_export_1c = 1) or
              -- RFCRU-5822: Цифровой рубль - все проводки со счётом 20701 (в Дт или Кт)
              (a_dt.acc_code starting '20701' or
              a_kt.acc_code starting '20701') or
              (a_dt.acc_code starting '7170281000531021' and
              a_kt.acc_code starting '20501' and
              a_kt.acc_from_reg_id <> 1010100) or
              (a_dt.acc_code starting '7170281000531022' and
              a_kt.acc_code starting '20501' and
              a_kt.acc_from_reg_id <> 1010100) or
              (a_dt.acc_code starting '7170281000531011' and
              a_kt.acc_code starting '20501' and
              a_kt.acc_from_reg_id <> 1010100) or
              (a_dt.acc_code = '71702810005310210101' and
              a_kt.acc_code = '20501810000000000035') or
              (a_dt.acc_code = '71702810005310310101' and
              a_kt.acc_code = '20501810000000000035') or
              (a_dt.acc_code = '71702810005310220101' and
              a_kt.acc_code = '20501810000000000035') or
              (a_dt.acc_code = '71702810005310320101' and
              a_kt.acc_code = '20501810000000000035') or
              (a_dt.acc_code = '20501810000000000035' and
              a_kt.acc_code = '47416810000000000001') or
              (a_dt.acc_code = '20209810000000003601' and
              a_kt.acc_code = '20501810000000000041') or
              (a_dt.acc_code = '20501810000000000041' and
              a_kt.acc_code = '20209810000000003601') or
              (a_dt.acc_code = '20209810000000004601' and
              a_kt.acc_code = '20501810000000000045') or
              (a_dt.acc_code = '20501810000000000045' and
              a_kt.acc_code = '20209810000000004601') or
              (a_dt.acc_code = '20209810000000003001' and
              a_kt.acc_code = '20501810000000000046') or
              (a_dt.acc_code = '20501810000000000046' and
              a_kt.acc_code = '20209810000000003001') or
              (a_dt.acc_code = '71702810005310310101' and
              a_kt.acc_code = '20501810000000000047') or
              (a_dt.acc_code = '71702810005310210101' and
              a_kt.acc_code = '20501810000000000048'))
        group by 1, 2, 3
        into kob_acc_dt, kob_acc_kt, kob_detail_id, kob_summa, kob_summa_val, kob_summa_tax_dt, kob_summa_tax_kt
    do
    begin
      insert into packet_1c_ob (pcb_pck_id, pcb_acc_dt, pcb_acc_kt, pcb_detail_id, pcb_summa, pcb_summa_val,
                                pcb_summa_tax_dt, pcb_summa_tax_kt)
      values (:pck_id, :kob_acc_dt, :kob_acc_kt, :kob_detail_id, :kob_summa, :kob_summa_val, :kob_summa_tax_dt,
              :kob_summa_tax_kt);
    end

    rep_date = dateadd(day, 1, rep_date);
  end
end
