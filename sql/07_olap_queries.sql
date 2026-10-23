-- ============================================================
-- TradeOps - Milestone 3
-- 07_olap_queries.sql: nine OLAP operations on tradeops_dw,
-- written as the business owner's planned analyses.
-- Each query names the operation and the business question (BQ)
-- from the problem definition that it answers.
-- ============================================================

SET search_path TO tradeops_dw;
\pset footer off

-- ------------------------------------------------------------
-- OP1  ROLL-UP  (BQ1: net return by firm and plan)
-- Cash Flow fact, Account dimension: Account -> Plan -> Firm -> All.
-- GROUP BY ROLLUP adds the plan subtotals, firm subtotals, and grand total.
-- ------------------------------------------------------------
\echo '== OP1 Roll-up: net return (payouts - fees) along Account -> Plan -> Firm'
SELECT  COALESCE(a.firm_name, '** All firms')   AS firm,
        COALESCE(a.plan_name, '* All plans')    AS plan,
        SUM(f.amount) FILTER (WHERE t.category = 'Fee')    AS fees,
        SUM(f.amount) FILTER (WHERE t.category = 'Payout') AS payouts,
        SUM(f.amount)                                      AS net_return
FROM    fact_cash_flow f
JOIN    dim_account a        USING (account_key)
JOIN    dim_cash_flow_type t USING (cash_flow_type_key)
GROUP BY ROLLUP (a.firm_name, a.plan_name)
ORDER BY a.firm_name NULLS LAST, a.plan_name NULLS LAST;

-- ------------------------------------------------------------
-- OP2  DRILL-DOWN  (BQ1: when was the money made?)
-- Trade fact, Date dimension: Year -> Quarter -> Month.
-- Starts at Year level, then descends one level per query.
-- ------------------------------------------------------------
\echo '== OP2a Drill-down, level Year'
SELECT  d.year_num, SUM(f.net_pnl) AS net_pnl, SUM(f.trade_count) AS trades
FROM    fact_trade f JOIN dim_date d USING (date_key)
GROUP BY d.year_num ORDER BY 1;

\echo '== OP2b Drill-down, level Quarter'
SELECT  d.year_quarter, SUM(f.net_pnl) AS net_pnl, SUM(f.trade_count) AS trades
FROM    fact_trade f JOIN dim_date d USING (date_key)
GROUP BY d.year_quarter ORDER BY 1;

\echo '== OP2c Drill-down, level Month (2026-Q2 only)'
SELECT  d.year_month, SUM(f.net_pnl) AS net_pnl, SUM(f.trade_count) AS trades
FROM    fact_trade f JOIN dim_date d USING (date_key)
WHERE   d.year_quarter = '2026-Q2'
GROUP BY d.year_month ORDER BY 1;

-- ------------------------------------------------------------
-- OP3  SLICE  (BQ3: performance on major economic event days)
-- Trade fact sliced on Date.event_day_type = 'Major event day',
-- then grouped by the event and strategy.
-- ------------------------------------------------------------
\echo '== OP3 Slice: event_day_type = Major event day'
SELECT  d.major_event, s.strategy_name,
        SUM(f.trade_count)                            AS trades,
        SUM(f.net_pnl)                                AS net_pnl,
        ROUND(100.0 * SUM(f.is_win) / SUM(f.trade_count), 1) AS win_rate_pct
FROM    fact_trade f
JOIN    dim_date d     USING (date_key)
JOIN    dim_strategy s USING (strategy_key)
WHERE   d.event_day_type = 'Major event day'
GROUP BY d.major_event, s.strategy_name
ORDER BY d.major_event, net_pnl DESC;

-- ------------------------------------------------------------
-- OP4  DICE  (BQ2/BQ3: equity-index leader trades in the US morning, 2026)
-- Sub-cube on four dimensions at once: Instrument.asset_class,
-- Time.session_name, Date.year_num, and Trade role.
-- ------------------------------------------------------------
\echo '== OP4 Dice: Equity Index x {NY Open, NY Midday} x 2026 x Leader'
SELECT  i.family_name, t.session_name,
        SUM(f.trade_count) AS trades,
        SUM(f.net_pnl)     AS net_pnl,
        ROUND(AVG(f.holding_seconds) / 60.0, 1) AS avg_hold_min
FROM    fact_trade f
JOIN    dim_instrument i USING (instrument_key)
JOIN    dim_time t       USING (time_key)
JOIN    dim_date d       USING (date_key)
JOIN    dim_trade_role r USING (role_key)
WHERE   i.asset_class = 'Equity Index'
  AND   t.session_name IN ('NY Open', 'NY Midday')
  AND   d.year_num = 2026
  AND   r.role_name = 'Leader'
GROUP BY i.family_name, t.session_name
ORDER BY i.family_name, t.session_name;

-- ------------------------------------------------------------
-- OP5  PIVOT (ROTATE)  (BQ2: strategy x asset class matrix)
-- Asset-class values are rotated from rows into columns, so each
-- strategy reads across the three markets it trades.
-- ------------------------------------------------------------
\echo '== OP5 Pivot: net P&L, strategies as rows, asset classes as columns'
SELECT  s.strategy_name,
        SUM(f.net_pnl) FILTER (WHERE i.asset_class = 'Equity Index') AS equity_index,
        SUM(f.net_pnl) FILTER (WHERE i.asset_class = 'Energy')       AS energy,
        SUM(f.net_pnl) FILTER (WHERE i.asset_class = 'Metals')       AS metals,
        SUM(f.net_pnl)                                               AS total
FROM    fact_trade f
JOIN    dim_strategy s   USING (strategy_key)
JOIN    dim_instrument i USING (instrument_key)
GROUP BY s.strategy_name
ORDER BY total DESC;

-- ------------------------------------------------------------
-- OP6  DRILL-ACROSS  (BQ1: does trading profit turn into cash?)
-- Combines two facts through the conformed Account and Date
-- dimensions: trading P&L (Trade) vs. fees and payouts (Cash Flow),
-- each aggregated separately to the same firm x quarter grain.
-- ------------------------------------------------------------
\echo '== OP6 Drill-across: Trade fact + Cash Flow fact by firm and quarter'
WITH trading AS (
    SELECT a.firm_name, d.year_quarter, SUM(f.net_pnl) AS trading_pnl
    FROM   fact_trade f JOIN dim_account a USING (account_key) JOIN dim_date d USING (date_key)
    GROUP BY 1, 2),
cash AS (
    SELECT a.firm_name, d.year_quarter,
           -SUM(f.amount) FILTER (WHERE t.category = 'Fee')   AS fees_paid,
           SUM(f.amount)  FILTER (WHERE t.category = 'Payout') AS payouts_received
    FROM   fact_cash_flow f JOIN dim_account a USING (account_key) JOIN dim_date d USING (date_key)
    JOIN   dim_cash_flow_type t USING (cash_flow_type_key)
    GROUP BY 1, 2)
SELECT  COALESCE(tr.firm_name, c.firm_name)       AS firm,
        COALESCE(tr.year_quarter, c.year_quarter) AS quarter,
        COALESCE(tr.trading_pnl, 0)               AS trading_pnl,
        COALESCE(c.fees_paid, 0)                  AS fees_paid,
        COALESCE(c.payouts_received, 0)           AS payouts_received,
        COALESCE(c.payouts_received, 0) - COALESCE(c.fees_paid, 0) AS net_return
FROM    trading tr
FULL JOIN cash c ON c.firm_name = tr.firm_name AND c.year_quarter = tr.year_quarter
ORDER BY firm, quarter;

-- ------------------------------------------------------------
-- OP7  CUBE ROLL-UP ON THE INSTRUMENT HIERARCHY  (BQ5: copy slippage)
-- Copies only (slice on role). CUBE over Family x Contract size gives
-- every combination of subtotals; slippage is AVG (unit measure).
-- ------------------------------------------------------------
\echo '== OP7 Cube: average copy slippage (ticks) by Family x Contract size'
SELECT  COALESCE(i.family_name, '** All families') AS family,
        COALESCE(i.contract_size, '* All sizes')   AS contract_size,
        SUM(f.trade_count)                         AS copies,
        ROUND(AVG(f.slippage_ticks), 2)            AS avg_slippage_ticks,
        ROUND(SUM(f.slippage_ticks * i.tick_value * f.contracts), 2) AS slippage_cost_usd
FROM    fact_trade f
JOIN    dim_instrument i USING (instrument_key)
JOIN    dim_trade_role r USING (role_key)
WHERE   r.role_name = 'Copy'
GROUP BY CUBE (i.family_name, i.contract_size)
ORDER BY i.family_name NULLS LAST, i.contract_size NULLS LAST;

-- ------------------------------------------------------------
-- OP8  DRILL-ACROSS + RANK (TOP-N)  (BQ2: which strategies precede violations?)
-- Daily Balance fact (violations) is joined to the Trade fact at the
-- shared account x date grain; strategies are ranked by the number of
-- violation days they traded on.
-- ------------------------------------------------------------
\echo '== OP8 Drill-across + rank: strategies traded on violation days'
WITH violation_days AS (
    SELECT date_key, account_key, violation_count
    FROM   fact_daily_balance
    WHERE  violation_count > 0),
strat AS (
    SELECT s.strategy_name,
           COUNT(DISTINCT (v.date_key, v.account_key)) AS violation_days,
           SUM(f.net_pnl)                              AS pnl_on_those_days
    FROM   violation_days v
    JOIN   fact_trade f   ON f.date_key = v.date_key AND f.account_key = v.account_key
    JOIN   dim_strategy s USING (strategy_key)
    GROUP BY s.strategy_name)
SELECT  RANK() OVER (ORDER BY violation_days DESC) AS rank,
        strategy_name, violation_days, pnl_on_those_days
FROM    strat
ORDER BY rank;

-- ------------------------------------------------------------
-- OP9  ROLL-UP WITH A NON-ADDITIVE MEASURE  (BQ4: pass rate and time to pass)
-- Account Lifecycle fact, evaluations only, rolled up Plan -> Firm.
-- Pass rate is recomputed from counts at each level (never summed).
-- ------------------------------------------------------------
\echo '== OP9 Roll-up: evaluation pass rate and days to pass, Plan -> Firm'
SELECT  COALESCE(a.firm_name, '** All firms') AS firm,
        COALESCE(a.plan_name, '* All plans')  AS plan,
        COUNT(*)                              AS evaluations,
        SUM(l.is_passed)                      AS passed,
        ROUND(100.0 * SUM(l.is_passed) / COUNT(*), 1) AS pass_rate_pct,
        ROUND(AVG(l.days_to_pass), 1)         AS avg_days_to_pass,
        ROUND(AVG(l.reset_count), 2)          AS avg_resets
FROM    fact_account_lifecycle l
JOIN    dim_account a USING (account_key)
WHERE   a.account_type = 'Evaluation'
GROUP BY ROLLUP (a.firm_name, a.plan_name)
ORDER BY a.firm_name NULLS LAST, a.plan_name NULLS LAST;

-- Semi-additive check used by the risk dashboard: balances are summed
-- across accounts but averaged (not summed) across days.
\echo '== OP9b Semi-additive level measure: average daily total funded balance per month'
SELECT  d.year_month,
        ROUND(AVG(day_total), 2) AS avg_total_end_balance
FROM   (SELECT f.date_key, SUM(f.end_balance) AS day_total
        FROM fact_daily_balance f JOIN dim_account a USING (account_key)
        WHERE a.account_type = 'Funded'
        GROUP BY f.date_key) x
JOIN    dim_date d USING (date_key)
GROUP BY d.year_month
ORDER BY d.year_month;
