-- ============================================================
-- TradeOps - Milestone 2
-- 03_views.sql: derived trade results. Net P&L is never stored;
-- it is calculated here from prices, tick size and tick value.
-- ============================================================

SET search_path TO tradeops;

CREATE OR REPLACE VIEW v_trade_pnl AS
SELECT
    t.TradeID,
    t.AccountID,
    t.StrategyID,
    t.Symbol,
    i.RootSymbol,
    COALESCE(p.FullSizeRoot, p.RootSymbol)                       AS ProductFamily,
    t.LeaderTradeID,
    CASE WHEN t.LeaderTradeID IS NULL THEN 'Leader' ELSE 'Copy' END AS TradeRole,
    t.Direction,
    t.Contracts,
    t.EntryTime,
    t.ExitTime,
    EXTRACT(EPOCH FROM (t.ExitTime - t.EntryTime))::INTEGER      AS HoldingSeconds,
    t.AvgEntryPrice,
    t.AvgExitPrice,
    ROUND(d.Sign * (t.AvgExitPrice - t.AvgEntryPrice) / p.TickSize, 2)                          AS PnLTicks,
    ROUND(d.Sign * (t.AvgExitPrice - t.AvgEntryPrice) / p.TickSize * p.TickValue * t.Contracts, 2) AS GrossPnL,
    t.Commission,
    ROUND(d.Sign * (t.AvgExitPrice - t.AvgEntryPrice) / p.TickSize * p.TickValue * t.Contracts
          - t.Commission, 2)                                     AS NetPnL
FROM Trade t
JOIN Instrument i ON i.Symbol = t.Symbol
JOIN Product    p ON p.RootSymbol = i.RootSymbol
CROSS JOIN LATERAL (SELECT CASE t.Direction WHEN 'Long' THEN 1 ELSE -1 END AS Sign) d;
