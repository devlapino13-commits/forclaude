-- RFCRU-6240: в отчёт попадали клиенты с действующими договорами.
-- Проверка шла по кредитной папке закрытого договора, а не по клиенту.
-- Добавлено условие NOT EXISTS по клиенту (KNCLIENT + KONTSTATE ks_state = 1 на дату отчёта).

create or alter procedure aarep_clients_close_6101 (
    rep_region_id integer,
    rep_date date)
returns (
    counter d_integer,
    c_name_fio str_100,
    c_birth_date d_date,
    citizen str_100,
    c_point d_integer,
    is_cession d_str_10,
    is_stoplist d_str_10,
    kf_folder_name str_100,
    kf_officer_name str_100,
    deport_date_begin d_date,
    deport_date_end d_date,
    deport_status d_str_255,
    last_date_close d_date,
    kf_region_name str_100,
    deliq_days_count d_integer)
as
declare variable cash_id decimal(18,0);
declare variable officer_id id_type;
declare variable k_id id_type;
begin
  -- RFCRU-6101: Разработка отчета «Закрытые клиенты с закреплением и статусом нахождения в РФ»
  counter = 0;
for

select ks_from_k_id, reg_name, last_close, kal_new_kf_name, officer, c_name_fio,
       officer_id, k_clients_cashier_id, deliq_days_count, c_birth_date, rd_name, fpoint
from (
    select d.*
         , row_number() over (
               partition by d.k_clients_cashier_id
               order by d.last_close desc,
                        d.deliq_days_count desc,
                        d.ks_from_k_id desc
           ) as rn
    from (
        select ks_from_k_id
             , r.reg_name
             , tab.last_close
             , kal_new_kf_name
             , co.c_name_fio as officer
             , c.c_name_fio
             , co.c_id as officer_id
             , k_clients_cashier_id
             , coalesce((select max(ok.ok_ol_date - ok.ok_sh_date)
                         from operkred ok
                         where ok.ok_from_k_id = k.k_id
                           and ok.ok_ol_is_active = 1
                           and ok.ok_ol_date > ok.ok_sh_date
                           and ok.ok_type < 7
                           and ok.ok_os + ok.ok_perc < 0
                           and ok.ok_from_c_id = 0), 0) as deliq_days_count
             , c.c_birth_date
             , rd.rd_name
             , f_point(k_clients_cashier_id, :rep_date) as fpoint
        from kontstate ks
        join kontract k on k_id = ks_from_k_id
        join knaktlist kal on kal_from_kf_id = k_from_kf_id
        join region_list(:rep_region_id,1,3,1) rl on rl.id_list = kal.kal_new_reg_id
        join region r on r.reg_unicode = rl.id_list
        join clients co on co.c_id = kal_new_kf_officer
        join clients c on c.c_id = k_clients_cashier_id
        join refdata rd on rd.rd_id = c.c_citizen
        left join (
            select distinct kont.k_from_kf_id as kf_id
            from kontract kont
            join kontstate ks on ks.ks_from_k_id = kont.k_id
            where ks.ks_ol_is_delete = 0
              and ks.ks_state = 1
              and :rep_date between ks.ks_date_begin and ks.ks_date_end
        ) t on t.kf_id = k.k_from_kf_id
        join (select max(oks_date_end) as last_close, oks_from_k_id
              from oksummary oks, knclient kc
              where kc_from_k_id = oks_from_k_id
                and oks_date_end < :rep_date
              group by oks_from_k_id
             ) tab on tab.oks_from_k_id = k.k_id
        join hr_pstatus on ps_from_c_id = co.c_id
        where :rep_date between cast(ks_date_begin as date) and ks_date_end
          and ks_ol_is_delete = 0
          and ks_state = 2
          and :rep_date between kal_date and kal_date_end
          and kal_new_reg_id = :rep_region_id
          and kal.is_delete = 0
          and t.kf_id is null
          -- RFCRU-6240: исключаем клиентов, у которых на дату отчёта есть действующий договор
          -- (в любой кредитной папке и в любой роли участника, не только по папке закрытого договора)
          and not exists (
              select 1
              from knclient kc2
              join kontstate ks2 on ks2.ks_from_k_id = kc2.kc_from_k_id
              where kc2.kc_from_c_id = k.k_clients_cashier_id
                and kc2.kc_amount_approved > 0
                and ks2.ks_ol_is_delete = 0
                and ks2.ks_state = 1
                and :rep_date between cast(ks2.ks_date_begin as date) and ks2.ks_date_end)
          and ps_from_reg_id = :rep_region_id
          and :rep_date between ps_date_begin and ps_date_end
          and ps_status = 1
          and ps_is_working = 1
    ) d
) x
where rn = 1

/*
select ks_from_k_id, reg_name, last_close, kal_new_kf_name, officer, c_name_fio,
       officer_id, k_clients_cashier_id, deliq_days_count, c_birth_date, rd_name, fpoint
from (
    select ks_from_k_id
         , r.reg_name
         , max(tab.last_close) as last_close
         , kal_new_kf_name
         , co.c_name_fio as officer
         , c.c_name_fio
         , co.c_id as officer_id
         , k_clients_cashier_id
         , coalesce(max(ok.ok_ol_date - ok_sh_date), 0) as deliq_days_count
         , c.c_birth_date
         , rd.rd_name
         , f_point(k_clients_cashier_id, :rep_date) as fpoint
         , row_number() over (
               partition by k_clients_cashier_id
               order by max(tab.last_close) desc,
                        coalesce(max(ok.ok_ol_date - ok_sh_date), 0) desc,
                        ks_from_k_id desc
           ) as rn
    from kontstate ks
    join kontract k on k_id = ks_from_k_id
    join knaktlist kal on kal_from_kf_id = k_from_kf_id
    join region_list(:rep_region_id,1,3,1) rl on rl.id_list = kal.kal_new_reg_id
    join region r on r.reg_unicode = rl.id_list
    join clients co on co.c_id = kal_new_kf_officer
    join clients c on c.c_id = k_clients_cashier_id
    join refdata rd on rd.rd_id = c.c_citizen
    left join operkred ok on ok_from_k_id = k.k_id
    left join (
        select distinct kont.k_from_kf_id as kf_id
        from kontract kont
        join kontstate ks on ks.ks_from_k_id = kont.k_id
        where ks.ks_ol_is_delete = 0
          and ks.ks_state = 1
          and :rep_date between ks.ks_date_begin and ks.ks_date_end
    ) t on t.kf_id = k.k_from_kf_id
    join (select max(oks_date_end) as last_close, oks_from_k_id
          from oksummary oks, knclient kc
          where kc_from_k_id = oks_from_k_id
            and oks_date_end < :rep_date
          group by oks_from_k_id
         ) tab on tab.oks_from_k_id = k.k_id
    join hr_pstatus on ps_from_c_id = co.c_id
    where :rep_date between cast(ks_date_begin as date) and ks_date_end
      and ks_ol_is_delete = 0
      and ks_state = 2
      and :rep_date between kal_date and kal_date_end
      and kal_new_reg_id = :rep_region_id
      and kal.is_delete = 0
      and t.kf_id is null
      and ok.ok_ol_is_active = 1
      and ok.ok_ol_date > ok_sh_date
      and ok_type < 7
      and ok_os + ok_perc < 0
      and ok_from_c_id = 0
      and ps_from_reg_id = :rep_region_id
      and :rep_date between ps_date_begin and ps_date_end
      and ps_status = 1
      and ps_is_working = 1
    group by ks_from_k_id, r.reg_name, kal_new_kf_name, co.c_name_fio, c.c_name_fio,
             co.c_id, k_clients_cashier_id, c.c_birth_date, rd.rd_name,
             f_point(k_clients_cashier_id, :rep_date)
) x
where rn = 1 */

/*  for select ks_from_k_id, reg_name, last_close, kal_new_kf_name, officer, c_name_fio,
             officer_id, k_clients_cashier_id, deliq_days_count, c_birth_date, rd_name, fpoint
  from (
      select ks_from_k_id
           , r.reg_name
           , max(tab.last_close)
           , kal_new_kf_name
           , co.c_name_fio as officer
           , c.c_name_fio
           , co.c_id as officer_id
           , k_clients_cashier_id
           , coalesce(max(ok.ok_ol_date - ok_sh_date), 0) as deliq_days_count
           , c.c_birth_date
           , rd.rd_name
           , f_point(k_clients_cashier_id, :rep_date) as fpoint
           , row_number() over (
                 partition by ks_from_k_id
                 order by tab.last_close desc
             ) as rn
      from kontstate ks
      join kontract k on k_id = ks_from_k_id
      join knaktlist kal on kal_from_kf_id = k_from_kf_id
      join region_list(:rep_region_id,1,3,1) rl on rl.id_list = kal.kal_new_reg_id
      join region r on r.reg_unicode = rl.id_list
      join clients co on co.c_id = kal_new_kf_officer
      join clients c on c.c_id = k_clients_cashier_id
      join refdata rd on rd.rd_id = c.c_citizen
      left join operkred ok on ok_from_k_id = k.k_id
      left join (
          select distinct kont.k_from_kf_id as kf_id
          from kontract kont
          join kontstate ks on ks.ks_from_k_id = kont.k_id
          where ks.ks_ol_is_delete = 0
            and ks.ks_state = 1
            and :rep_date between ks.ks_date_begin and ks.ks_date_end
      ) t on t.kf_id = k.k_from_kf_id
      join (select max(oks_date_end) as last_close, oks_from_k_id
            from oksummary oks, knclient kc
            where kc_from_k_id = oks_from_k_id
            --  and kc_from_c_id = :cash_id
            --  and oks_from_k_id = :k_id
              and oks_date_end < :rep_date
          --  order by 1 desc
            --rows 1
            group by oks_from_k_id
            ) tab on tab.oks_from_k_id = k.k_id
      join hr_pstatus on ps_from_c_id = co.c_id
  
      where :rep_date between cast(ks_date_begin as date) and ks_date_end
        and ks_ol_is_delete = 0
        and ks_state = 2
        and :rep_date between kal_date and kal_date_end
        and kal_new_reg_id = :rep_region_id
        and kal.is_delete = 0
        and t.kf_id is null
        and ok.ok_ol_is_active = 1
        and ok.ok_ol_date > ok_sh_date
        and ok_type < 7
        and ok_os + ok_perc < 0
        and ok_from_c_id = 0
        and ps_from_reg_id = :rep_region_id
        and :rep_date between ps_date_begin and ps_date_end
        and ps_status = 1
        and ps_is_working = 1
      group by ks_from_k_id, r.reg_name, tab.last_close, kal_new_kf_name, co.c_name_fio, c.c_name_fio, co.c_id, k_clients_cashier_id, c.c_birth_date, rd.rd_name, f_point(k_clients_cashier_id, :rep_date)
  ) x
  where rn = 1 */
  into :k_id, :kf_region_name, :last_date_close, :kf_folder_name, :kf_officer_name, :c_name_fio, :officer_id, :cash_id, :deliq_days_count, :c_birth_date, :citizen, :c_point
  do
  begin
      is_stoplist = 'нет';
      select 'да'
      from moratory m
      where m.m_from_c_id = :cash_id
        and m.m_is_active = 1
        and m.m_is_black = 2
        and :rep_date between m.m_date_begin and m.m_date_end
      rows 1
      into is_stoplist;

      select cd.cds_doc_date_begin, cd.cds_doc_date_end
      from clientdocs cd
      join passkind pk on pk.pk_id = cd.cds_from_pk_id
      join passdoctype pdt on pdt.pdt_id = pk.pk_from_pdt_id
      where cd.cds_from_c_id = :cash_id
        and pdt.pdt_code = 'deport_document'
        and cd.cds_is_delete = 0
        and :rep_date between cd.cds_doc_date_begin and cd.cds_doc_date_end
      order by cd.cds_doc_date_begin desc
      rows 1
      into :deport_date_begin, :deport_date_end;
      
      select iif(coalesce(status_full, '') = '', 'Нет', status_full)
      from hp_deprot_status(:cash_id, :rep_date)
      into :deport_status;

     /* select oks_date_end
      from oksummary oks, knclient kc
      where kc_from_k_id = oks_from_k_id
        and kc_from_c_id = :cash_id
        and oks_from_k_id = :k_id
        and oks_date_end < :report_date
      order by 1 desc
      rows 1
      into :last_date_close; */

    is_cession = 'нет';
    select 'да'
    from sud_cession_packet
    join sud_cession_loans on scl_from_scp_id = scp_id
    where scl_from_k_id = :k_id
      and scp_status > 0
      and scp_date <= :rep_date
    rows 1
    into is_cession;

    counter = counter + 1;
    suspend;
  end
end