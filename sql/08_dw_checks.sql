-- ============================================================
-- TradeOps - Milestone 3
-- 08_dw_checks.sql: reconciles tradeops_dw with the operational
-- schema. Every "diff" column should be 0.
-- ============================================================

SET search_path TO tradeops_dw;
\pset footer off

\echo '== Row counts per warehouse table'
SELECT 'dim_date' AS table_name, COUNT(*) AS row_count FROM dim_date
UNION ALL SELECT 'dim_time',               COUNT(*) FROM dim_time
UNION ALL SELECT 'dim_account',            COUNT(*) FROM dim_account
UNION ALL SELECT 'dim_instrument',         COUNT(*) FROM dim_instrument
UNION ALL SELECT 'dim_strategy',           COUNT(*) FROM dim_strategy
UNION ALL SELECT 'dim_trade_role',         COUNT(*) FROM dim_trade_role
UNION ALL SELECT 'dim_cash_flow_type',     COUNT(*) FROM dim_cash_flow_type
UNION ALL SELECT 'dim_account_status',     COUNT(*) FROM dim_account_status
UNION ALL SELECT 'fact_trade',             COUNT(*) FROM fact_trade
UNION ALL SELECT 'fact_daily_balance',     COUNT(*) FROM fact_daily_balance
UNION ALL SELECT 'fact_cash_flow',         COUNT(*) FROM fact_cash_flow
UNION ALL SELECT 'fact_account_lifecycle', COUNT(*) FROM fact_account_lifecycle;

\echo '== Fact rows vs. source rows'
SELECT  (SELECT COUNT(*) FROM fact_trade)
      - (SELECT COUNT(*) FROM tradeops.Trade)                         AS trade_diff,
        (SELECT COUNT(*) FROM fact_daily_balance)
      - (SELECT COUNT(*) FROM tradeops.DailyAccountBalance)           AS balance_diff,
        (SELECT COUNT(*) FROM fact_cash_flow)
      - (SELECT COUNT(*) FROM tradeops.AccountCharge)
      - (SELECT COUNT(*) FROM tradeops.Payout)                        AS cash_flow_diff,
        (SELECT COUNT(*) FROM fact_account_lifecycle)
      - (SELECT COUNT(*) FROM tradeops.Account)                       AS lifecycle_diff;

\echo '== Measure totals vs. source totals'
SELECT  (SELECT SUM(net_pnl) FROM fact_trade)                        AS dw_net_pnl,
        (SELECT SUM(NetPnL)  FROM tradeops.v_trade_pnl)              AS src_net_pnl,
        (SELECT -SUM(amount) FROM fact_cash_flow WHERE amount < 0)   AS dw_fees,
        (SELECT SUM(Amount)  FROM tradeops.AccountCharge)            AS src_fees,
        (SELECT SUM(amount)  FROM fact_cash_flow WHERE amount > 0)   AS dw_payouts,
        (SELECT SUM(TraderShare) FROM tradeops.Payout WHERE Status = 'Paid') AS src_payouts,
        (SELECT SUM(violation_count) FROM fact_daily_balance)        AS dw_violations,
        (SELECT COUNT(*) FROM tradeops.RuleViolation)                AS src_violations;

\echo '== Cross-fact consistency: lifecycle net return = cash-flow total'
SELECT  (SELECT SUM(net_return) FROM fact_account_lifecycle)         AS lifecycle_net_return,
        (SELECT SUM(amount)     FROM fact_cash_flow)                 AS cash_flow_net_return;

\echo '== Trades by session (every trade maps to a session)'
SELECT  t.session_name, COUNT(*) AS trades
FROM    fact_trade f JOIN dim_time t USING (time_key)
GROUP BY t.session_name ORDER BY trades DESC;

\echo '== ETL load log (initial full load and high-water marks)'
SELECT  table_name, load_type, high_water_mark, rows_inserted, rows_updated
FROM    etl_load_log ORDER BY batch_id;

\echo '== Integrity constraints declared in tradeops_dw, by table'
SELECT  cl.relname AS table_name,
        COUNT(*) FILTER (WHERE c.contype = 'p') AS primary_keys,
        COUNT(*) FILTER (WHERE c.contype = 'f') AS foreign_keys,
        COUNT(*) FILTER (WHERE c.contype = 'u') AS unique_keys,
        COUNT(*) FILTER (WHERE c.contype = 'c') AS check_constraints
FROM    pg_constraint c
JOIN    pg_class cl     ON cl.oid = c.conrelid
JOIN    pg_namespace n  ON n.oid = cl.relnamespace
WHERE   n.nspname = 'tradeops_dw'
GROUP BY ROLLUP (cl.relname)
ORDER BY cl.relname NULLS LAST;
