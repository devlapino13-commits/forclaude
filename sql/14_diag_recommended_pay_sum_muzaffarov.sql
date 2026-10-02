-- RFCRU-6015: диагностика рекомендуемого платежа по договору 0119-1055384-11 (Музаффаров).

-- 1. Какая версия процедуры стоит на базе
select iif(rdb$procedure_source containing 'ред. 4', 'ред. 4 (Claude, с пеней)',
       iif(rdb$procedure_source containing 'delinq_body', 'ред. 3 (Claude, без пени)',
       iif(rdb$procedure_source containing 'RFCRU-6015', 'новая (6015, 92a6cb2c)',
       iif(rdb$procedure_source containing 'RFCRU-4811', 'старая (4811)', '?')))) as version
from rdb$procedures
where rdb$procedure_name = 'GET_RECOMMENDED_PAY_SUM';

-- 2. Строки задолженности, из которых складывается сумма
select z.sh_date,
       z.sh_date - current_date as days_left,
       z.zad_os, z.zad_perc, z.sh_calc_perc, z.sh_calc_fine, z.zad_kommis
from kontract k
cross join aarep_make_zad_list(k.k_id, current_date, 1) z
where k.k_kontract_no = '0119-1055384-11'
order by z.sh_date nulls first;
