-- ============================================================
-- TradeOps - Milestone 2
-- 02_load.sql: loads the 16 CSV files from data/ in dependency
-- order inside one transaction (a bad row rolls back everything).
-- Run from the project folder: psql -d tradeops -f sql/02_load.sql
-- ============================================================

\set ON_ERROR_STOP on
SET search_path TO tradeops;

BEGIN;

-- Reference data
\copy PropFirm          FROM 'data/PropFirm.csv'          WITH (FORMAT csv, HEADER true)
\copy AccountPlan       FROM 'data/AccountPlan.csv'       WITH (FORMAT csv, HEADER true)
\copy Exchange          FROM 'data/Exchange.csv'          WITH (FORMAT csv, HEADER true)
\copy Product (RootSymbol, ProductName, ExchangeCode, AssetClass, TickSize, TickValue, IsMicro) FROM 'data/Product.csv' WITH (FORMAT csv, HEADER true)
\copy Instrument        FROM 'data/Instrument.csv'        WITH (FORMAT csv, HEADER true)
\copy Strategy          FROM 'data/Strategy.csv'          WITH (FORMAT csv, HEADER true)
\copy StrategyApproval  FROM 'data/StrategyApproval.csv'  WITH (FORMAT csv, HEADER true)
\copy TradingSession    FROM 'data/TradingSession.csv'    WITH (FORMAT csv, HEADER true)
\copy EconomicEvent     FROM 'data/EconomicEvent.csv'     WITH (FORMAT csv, HEADER true)

-- Transactional data (Account first, then the tables that reference Account and Trade)
\copy Account (AccountID, PlanID, ParentAccountID, AccountLabel, Platform, OpenDate, CloseDate, Status) FROM 'data/Account.csv' WITH (FORMAT csv, HEADER true)
\copy AccountCharge     FROM 'data/AccountCharge.csv'     WITH (FORMAT csv, HEADER true)
\copy Trade (TradeID, AccountID, StrategyID, Symbol, LeaderTradeID, Direction, Contracts, EntryTime, ExitTime, AvgEntryPrice, AvgExitPrice, Commission) FROM 'data/Trade.csv' WITH (FORMAT csv, HEADER true)
\copy Fill              FROM 'data/Fill.csv'              WITH (FORMAT csv, HEADER true)
\copy DailyAccountBalance FROM 'data/DailyAccountBalance.csv' WITH (FORMAT csv, HEADER true)
\copy RuleViolation     FROM 'data/RuleViolation.csv'     WITH (FORMAT csv, HEADER true)
\copy Payout            FROM 'data/Payout.csv'            WITH (FORMAT csv, HEADER true)

-- Link each micro contract to its full-size product (MNQ -> NQ, M2K -> RTY, ...).
-- Micro and full-size versions share the exchange and asset class; the full-size
-- symbol is the micro symbol without its leading M, except M2K (Russell 2000 -> RTY).
UPDATE Product m
SET    FullSizeRoot = CASE m.RootSymbol WHEN 'M2K' THEN 'RTY' ELSE substr(m.RootSymbol, 2) END
WHERE  m.IsMicro;

COMMIT;

ANALYZE;
