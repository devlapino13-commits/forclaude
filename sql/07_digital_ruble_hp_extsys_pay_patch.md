# УСТАРЕЛО / НЕ ПРИМЕНЯТЬ

Основано на вводной "esm_project = 'DigiRub'" (отдельный проект под ЦР,
на том же MNT-XML протоколе, что Moneta/Wirebank/Tinkoff/CaRuSell).

Уточнено (скрин `EXTSYSPRO`, комментарий Цымбалюка В.): отдельный проект
заводить не будут, ЦР идёт через уже существующий `esm_project = 'moneta'`,
различие — по параметру `MNT_PAYMENT_METHOD = 'cr'` внутри `ESM_FULL_SOURCE`.
Раз проект тот же самый (`moneta`), `HP_EXTSYS_PAY` уже и так знает про него
во всех нужных местах — править там ничего не нужно.

Актуальная правка: `sql/10_digital_ruble_via_moneta_patch.md`
