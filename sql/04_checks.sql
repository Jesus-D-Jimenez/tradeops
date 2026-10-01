-- ============================================================
-- TradeOps - Milestone 2
-- 04_checks.sql: row counts, constraint inventory, and integrity
-- checks that go beyond what constraints can express.
-- Expected: every integrity check returns 0.
-- ============================================================

SET search_path TO tradeops;

\echo '== Rows loaded per table =='
SELECT 'PropFirm' AS table_name, 'Reference' AS kind, COUNT(*) AS row_count FROM PropFirm
UNION ALL SELECT 'AccountPlan',         'Reference',     COUNT(*) FROM AccountPlan
UNION ALL SELECT 'Exchange',            'Reference',     COUNT(*) FROM Exchange
UNION ALL SELECT 'Product',             'Reference',     COUNT(*) FROM Product
UNION ALL SELECT 'Instrument',          'Reference',     COUNT(*) FROM Instrument
UNION ALL SELECT 'Strategy',            'Reference',     COUNT(*) FROM Strategy
UNION ALL SELECT 'StrategyApproval',    'Reference',     COUNT(*) FROM StrategyApproval
UNION ALL SELECT 'TradingSession',      'Reference',     COUNT(*) FROM TradingSession
UNION ALL SELECT 'EconomicEvent',       'Reference',     COUNT(*) FROM EconomicEvent
UNION ALL SELECT 'Account',             'Transactional', COUNT(*) FROM Account
UNION ALL SELECT 'AccountCharge',       'Transactional', COUNT(*) FROM AccountCharge
UNION ALL SELECT 'Trade',               'Transactional', COUNT(*) FROM Trade
UNION ALL SELECT 'Fill',                'Transactional', COUNT(*) FROM Fill
UNION ALL SELECT 'DailyAccountBalance', 'Transactional', COUNT(*) FROM DailyAccountBalance
UNION ALL SELECT 'RuleViolation',       'Transactional', COUNT(*) FROM RuleViolation
UNION ALL SELECT 'Payout',              'Transactional', COUNT(*) FROM Payout;

\echo '== Constraints and indexes in schema tradeops =='
SELECT CASE c.contype WHEN 'p' THEN 'Primary key' WHEN 'f' THEN 'Foreign key'
                      WHEN 'u' THEN 'Unique'      WHEN 'c' THEN 'Check' END AS constraint_type,
       COUNT(*) AS n
FROM pg_constraint c
JOIN pg_namespace n ON n.oid = c.connamespace
WHERE n.nspname = 'tradeops' AND c.contype IN ('p', 'f', 'u', 'c')
GROUP BY c.contype
UNION ALL
SELECT 'Index (secondary)', COUNT(*)
FROM pg_indexes
WHERE schemaname = 'tradeops' AND indexname LIKE 'ix\_%';

\echo '== Integrity checks (expected 0) =='
SELECT 'Trades whose fills do not net to a flat position' AS check_name, COUNT(*) AS result
FROM (SELECT TradeID
      FROM Fill
      GROUP BY TradeID
      HAVING SUM(CASE Side WHEN 'Buy' THEN Quantity ELSE -Quantity END) <> 0) x
UNION ALL
SELECT 'Copied trades in a different direction or contract family than their leader', COUNT(*)
FROM v_trade_pnl c
JOIN v_trade_pnl l ON l.TradeID = c.LeaderTradeID
WHERE c.Direction <> l.Direction OR c.ProductFamily <> l.ProductFamily
UNION ALL
SELECT 'Funded accounts whose parent account is not an evaluation', COUNT(*)
FROM Account a
JOIN Account     pa ON pa.AccountID = a.ParentAccountID
JOIN AccountPlan pp ON pp.PlanID    = pa.PlanID
WHERE pp.PlanType <> 'Evaluation'
UNION ALL
SELECT 'Trades on a product the strategy is not approved for', COUNT(*)
FROM Trade t
JOIN Instrument i ON i.Symbol = t.Symbol
LEFT JOIN StrategyApproval s ON s.StrategyID = t.StrategyID AND s.RootSymbol = i.RootSymbol
WHERE s.StrategyID IS NULL
UNION ALL
SELECT 'Micro products without a full-size parent', COUNT(*)
FROM Product
WHERE IsMicro AND FullSizeRoot IS NULL;

\echo '== Trade coverage =='
SELECT MIN(EntryTime::date)          AS first_trade_date,
       MAX(EntryTime::date)          AS last_trade_date,
       COUNT(DISTINCT EntryTime::date) AS trading_days,
       COUNT(DISTINCT Symbol)        AS contract_months_traded,
       COUNT(*) FILTER (WHERE LeaderTradeID IS NULL)     AS leader_trades,
       COUNT(*) FILTER (WHERE LeaderTradeID IS NOT NULL) AS copied_trades
FROM Trade;
