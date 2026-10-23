-- ============================================================
-- TradeOps - Milestone 3
-- 06_dw_load.sql: ETL from the operational schema (tradeops)
-- into the warehouse (tradeops_dw). Runs in one transaction:
-- dimensions first, then facts with surrogate-key lookups.
-- Requires 01-03 (tradeops + v_trade_pnl) and 05 (tradeops_dw).
-- ============================================================

BEGIN;
SET search_path TO tradeops_dw, tradeops;

-- ------------------------------------------------------------
-- dim_date: every day of 2025-2026, with the day's high-impact
-- release (at most one per day in the source calendar).
-- ------------------------------------------------------------
INSERT INTO dim_date
SELECT  TO_CHAR(d, 'YYYYMMDD')::INTEGER,
        d,
        EXTRACT(ISODOW FROM d),
        TRIM(TO_CHAR(d, 'Day')),
        EXTRACT(ISODOW FROM d) <= 5,
        EXTRACT(WEEK FROM d),
        EXTRACT(MONTH FROM d),
        TRIM(TO_CHAR(d, 'Month')),
        TO_CHAR(d, 'YYYY-MM'),
        EXTRACT(QUARTER FROM d),
        TO_CHAR(d, 'YYYY') || '-Q' || EXTRACT(QUARTER FROM d),
        EXTRACT(YEAR FROM d),
        COALESCE(e.EventName, 'None'),
        e.EventTimeET,
        CASE WHEN e.EventName IS NULL THEN 'Regular day' ELSE 'Major event day' END
FROM    generate_series(DATE '2025-01-01', DATE '2026-12-31', INTERVAL '1 day') AS g(d)
LEFT JOIN EconomicEvent e ON e.EventDate = g.d::DATE AND e.Impact = 'High';

-- ------------------------------------------------------------
-- dim_time: 1,440 minutes mapped to trading sessions.
-- Asia wraps midnight (18:00-02:00); 17:00-18:00 is the daily
-- CME maintenance break and belongs to no session.
-- ------------------------------------------------------------
INSERT INTO dim_time
SELECT  (h * 100 + m)::SMALLINT,
        make_time(h, m, 0),
        h, m,
        COALESCE(s.SessionName, 'Maintenance'),
        s.StartTimeET,
        s.EndTimeET,
        CASE WHEN s.SessionName IN ('Asia', 'London')                     THEN 'Overnight'
             WHEN s.SessionName IN ('NY Open', 'NY Midday', 'NY Close')   THEN 'US Regular Hours'
             ELSE 'Closed' END
FROM    generate_series(0, 23) AS h
CROSS JOIN generate_series(0, 59) AS m
LEFT JOIN TradingSession s
       ON CASE WHEN s.StartTimeET < s.EndTimeET
               THEN make_time(h, m, 0) >= s.StartTimeET AND make_time(h, m, 0) < s.EndTimeET
               ELSE make_time(h, m, 0) >= s.StartTimeET OR  make_time(h, m, 0) < s.EndTimeET END;

-- ------------------------------------------------------------
-- Small, static dimensions
-- ------------------------------------------------------------
INSERT INTO dim_trade_role VALUES (1, 'Leader'), (2, 'Copy');

INSERT INTO dim_cash_flow_type VALUES
    (1, 'Evaluation fee', 'Fee',    -1),
    (2, 'Activation fee', 'Fee',    -1),
    (3, 'Reset fee',      'Fee',    -1),
    (4, 'Monthly fee',    'Fee',    -1),
    (5, 'Payout paid',    'Payout',  1),
    (6, 'Payout denied',  'Payout',  0);

INSERT INTO dim_account_status VALUES
    (1, 'Active',   'Open'),
    (2, 'Passed',   'Success'),
    (3, 'Failed',   'Lost'),
    (4, 'Breached', 'Lost'),
    (5, 'Closed',   'Closed');

-- ------------------------------------------------------------
-- dim_account: Account + AccountPlan + PropFirm flattened.
-- First load: one current version per account, valid from OpenDate.
-- ------------------------------------------------------------
INSERT INTO dim_account (account_id, account_label, platform, parent_account_id, account_type,
                         account_size, plan_id, plan_name, starting_balance, profit_target,
                         max_trailing_drawdown, daily_loss_limit, profit_split_pct, plan_fee,
                         firm_id, firm_name, payout_cycle_days, valid_from)
SELECT  a.AccountID, a.AccountLabel, a.Platform, a.ParentAccountID, p.PlanType,
        (p.StartingBalance / 1000)::INTEGER || 'K',
        p.PlanID, p.PlanName, p.StartingBalance, p.ProfitTarget,
        p.MaxTrailingDrawdown, p.DailyLossLimit, p.ProfitSplitPct, p.PlanFee,
        f.FirmID, f.FirmName, f.PayoutCycleDays, a.OpenDate
FROM    Account a
JOIN    AccountPlan p ON p.PlanID = a.PlanID
JOIN    PropFirm f    ON f.FirmID = p.FirmID
ORDER BY a.AccountID;

-- ------------------------------------------------------------
-- dim_instrument: Instrument + Product + family + Exchange.
-- ------------------------------------------------------------
INSERT INTO dim_instrument (symbol, contract_month, expiration_date, root_symbol, product_name,
                            contract_size, tick_size, tick_value, family_root, family_name,
                            asset_class, exchange_code, exchange_name)
SELECT  i.Symbol, i.ContractMonth, i.ExpirationDate, p.RootSymbol, p.ProductName,
        CASE WHEN p.IsMicro THEN 'Micro' ELSE 'Full-size' END,
        p.TickSize, p.TickValue,
        COALESCE(p.FullSizeRoot, p.RootSymbol), fam.ProductName,
        p.AssetClass, x.ExchangeCode, x.ExchangeName
FROM    Instrument i
JOIN    Product  p   ON p.RootSymbol = i.RootSymbol
JOIN    Product  fam ON fam.RootSymbol = COALESCE(p.FullSizeRoot, p.RootSymbol)
JOIN    Exchange x   ON x.ExchangeCode = p.ExchangeCode
ORDER BY i.Symbol;

-- ------------------------------------------------------------
-- dim_strategy
-- ------------------------------------------------------------
INSERT INTO dim_strategy (strategy_id, strategy_name, style, timeframe, approved_products, valid_from)
SELECT  s.StrategyID, s.StrategyName, s.Style, s.Timeframe,
        (SELECT COUNT(*) FROM StrategyApproval sa WHERE sa.StrategyID = s.StrategyID),
        DATE '2025-01-01'
FROM    Strategy s
ORDER BY s.StrategyID;

-- ------------------------------------------------------------
-- fact_trade. Surrogate keys are looked up "as of" the trade date
-- so that SCD Type 2 versions are respected.
-- Slippage = leader P&L ticks - copy P&L ticks (positive = copy did worse).
-- ------------------------------------------------------------
INSERT INTO fact_trade
SELECT  v.TradeID,
        v.LeaderTradeID,
        TO_CHAR(v.EntryTime, 'YYYYMMDD')::INTEGER,
        (EXTRACT(HOUR FROM v.EntryTime) * 100 + EXTRACT(MINUTE FROM v.EntryTime))::SMALLINT,
        da.account_key,
        di.instrument_key,
        ds.strategy_key,
        CASE WHEN v.LeaderTradeID IS NULL THEN 1 ELSE 2 END,
        v.Direction,
        v.Contracts,
        v.PnLTicks,
        v.GrossPnL,
        v.Commission,
        v.NetPnL,
        v.HoldingSeconds,
        CASE WHEN v.LeaderTradeID IS NULL THEN NULL ELSE ld.PnLTicks - v.PnLTicks END,
        CASE WHEN v.NetPnL > 0 THEN 1 ELSE 0 END,
        1
FROM    v_trade_pnl v
LEFT JOIN v_trade_pnl ld ON ld.TradeID = v.LeaderTradeID
JOIN    dim_account da    ON da.account_id = v.AccountID
                         AND v.EntryTime::DATE BETWEEN da.valid_from AND da.valid_to
JOIN    dim_instrument di ON di.symbol = v.Symbol
JOIN    dim_strategy ds   ON ds.strategy_id = v.StrategyID
                         AND v.EntryTime::DATE BETWEEN ds.valid_from AND ds.valid_to;

-- ------------------------------------------------------------
-- fact_daily_balance: snapshot + same-day trade and violation counts.
-- ------------------------------------------------------------
INSERT INTO fact_daily_balance
SELECT  TO_CHAR(b.TradeDate, 'YYYYMMDD')::INTEGER,
        da.account_key,
        b.StartBalance, b.EndBalance, b.HighWaterMark, b.DrawdownFloor,
        b.EndBalance - b.DrawdownFloor,
        b.EndBalance - b.StartBalance,
        COALESCE(t.n, 0),
        COALESCE(v.total, 0),
        COALESCE(v.dd, 0),
        COALESCE(v.dll, 0),
        COALESCE(v.cons, 0)
FROM    DailyAccountBalance b
JOIN    dim_account da ON da.account_id = b.AccountID
                      AND b.TradeDate BETWEEN da.valid_from AND da.valid_to
LEFT JOIN (SELECT AccountID, EntryTime::DATE AS d, COUNT(*) AS n
           FROM Trade GROUP BY 1, 2) t
       ON t.AccountID = b.AccountID AND t.d = b.TradeDate
LEFT JOIN (SELECT AccountID, ViolationDate AS d,
                  COUNT(*) AS total,
                  COUNT(*) FILTER (WHERE RuleType = 'TrailingDrawdown') AS dd,
                  COUNT(*) FILTER (WHERE RuleType = 'DailyLossLimit')   AS dll,
                  COUNT(*) FILTER (WHERE RuleType = 'Consistency')      AS cons
           FROM RuleViolation GROUP BY 1, 2) v
       ON v.AccountID = b.AccountID AND v.d = b.TradeDate;

-- ------------------------------------------------------------
-- fact_cash_flow: fees (negative) and payouts (trader share, positive).
-- A denied payout is kept with amount 0 so it can still be counted.
-- ------------------------------------------------------------
INSERT INTO fact_cash_flow
SELECT  'CHG-' || c.ChargeID,
        TO_CHAR(c.ChargeDate, 'YYYYMMDD')::INTEGER,
        da.account_key,
        t.cash_flow_type_key,
        -c.Amount,
        c.Amount,
        1
FROM    AccountCharge c
JOIN    dim_cash_flow_type t ON t.cash_flow_type = c.ChargeType || ' fee'
JOIN    dim_account da ON da.account_id = c.AccountID
                      AND c.ChargeDate BETWEEN da.valid_from AND da.valid_to;

INSERT INTO fact_cash_flow
SELECT  'PAY-' || p.PayoutID,
        TO_CHAR(COALESCE(p.PaidDate, p.RequestDate), 'YYYYMMDD')::INTEGER,
        da.account_key,
        CASE p.Status WHEN 'Paid' THEN 5 ELSE 6 END,
        CASE p.Status WHEN 'Paid' THEN p.TraderShare ELSE 0 END,
        p.GrossAmount,
        1
FROM    Payout p
JOIN    dim_account da ON da.account_id = p.AccountID
                      AND p.RequestDate BETWEEN da.valid_from AND da.valid_to;

-- ------------------------------------------------------------
-- fact_account_lifecycle: one row per account (current version).
-- Open accounts are measured up to the last date in the data.
-- ------------------------------------------------------------
INSERT INTO fact_account_lifecycle
SELECT  da.account_key,
        TO_CHAR(a.OpenDate, 'YYYYMMDD')::INTEGER,
        CASE WHEN a.Status = 'Passed' THEN TO_CHAR(a.CloseDate, 'YYYYMMDD')::INTEGER END,
        TO_CHAR(a.CloseDate, 'YYYYMMDD')::INTEGER,
        st.status_key,
        COALESCE(a.CloseDate, last_day.d) - a.OpenDate,
        CASE WHEN a.Status = 'Passed' THEN a.CloseDate - a.OpenDate END,
        COALESCE(b.days, 0),
        COALESCE(t.n, 0),
        COALESCE(t.pnl, 0),
        COALESCE(c.fees, 0),
        COALESCE(p.paid, 0),
        COALESCE(p.paid, 0) - COALESCE(c.fees, 0),
        COALESCE(c.resets, 0),
        COALESCE(v.n, 0),
        CASE WHEN a.Status = 'Passed' THEN 1 ELSE 0 END
FROM    Account a
JOIN    dim_account da        ON da.account_id = a.AccountID AND da.is_current
JOIN    dim_account_status st ON st.status_name = a.Status
CROSS JOIN (SELECT MAX(TradeDate) AS d FROM DailyAccountBalance) last_day
LEFT JOIN (SELECT AccountID, COUNT(*) AS days FROM DailyAccountBalance GROUP BY 1) b ON b.AccountID = a.AccountID
LEFT JOIN (SELECT AccountID, COUNT(*) AS n, SUM(NetPnL) AS pnl FROM v_trade_pnl GROUP BY 1) t ON t.AccountID = a.AccountID
LEFT JOIN (SELECT AccountID, SUM(Amount) AS fees,
                  COUNT(*) FILTER (WHERE ChargeType = 'Reset') AS resets
           FROM AccountCharge GROUP BY 1) c ON c.AccountID = a.AccountID
LEFT JOIN (SELECT AccountID, SUM(TraderShare) FILTER (WHERE Status = 'Paid') AS paid
           FROM Payout GROUP BY 1) p ON p.AccountID = a.AccountID
LEFT JOIN (SELECT AccountID, COUNT(*) AS n FROM RuleViolation GROUP BY 1) v ON v.AccountID = a.AccountID;


-- ------------------------------------------------------------
-- Record this initial full load and the high-water marks that
-- the next incremental load starts from.
-- ------------------------------------------------------------
INSERT INTO etl_load_log (table_name, load_type, high_water_mark, rows_inserted)
SELECT 'dim_date',               'Full', MAX(date_key)::TEXT,   COUNT(*) FROM dim_date
UNION ALL SELECT 'dim_time',     'Full', NULL,                  COUNT(*) FROM dim_time
UNION ALL SELECT 'dim_account',  'Full', MAX(account_id)::TEXT, COUNT(*) FROM dim_account
UNION ALL SELECT 'dim_instrument','Full', NULL,                 COUNT(*) FROM dim_instrument
UNION ALL SELECT 'dim_strategy', 'Full', MAX(strategy_id)::TEXT, COUNT(*) FROM dim_strategy
UNION ALL SELECT 'fact_trade',   'Full', MAX(trade_id)::TEXT,   COUNT(*) FROM fact_trade
UNION ALL SELECT 'fact_daily_balance', 'Full', MAX(date_key)::TEXT, COUNT(*) FROM fact_daily_balance
UNION ALL SELECT 'fact_cash_flow', 'Full', MAX(date_key)::TEXT, COUNT(*) FROM fact_cash_flow
UNION ALL SELECT 'fact_account_lifecycle', 'Full', NULL,        COUNT(*) FROM fact_account_lifecycle;

COMMIT;
ANALYZE;
