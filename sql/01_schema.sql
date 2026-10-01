-- ============================================================
-- TradeOps - Milestone 2
-- 01_schema.sql: operational database (OLTP) for PostgreSQL 16
-- Drops and recreates schema tradeops: 16 tables, named
-- constraints (16 PK, 17 FK, 7 UQ, 30 CHECK) and 15 indexes.
-- Run: psql -d tradeops -f sql/01_schema.sql
-- ============================================================

DROP SCHEMA IF EXISTS tradeops CASCADE;
CREATE SCHEMA tradeops;
SET search_path TO tradeops;

-- ---------- STATIC REFERENCE DATA ----------

CREATE TABLE PropFirm (
    FirmID              INTEGER       NOT NULL,
    FirmName            VARCHAR(60)   NOT NULL,
    Website             VARCHAR(100)  NOT NULL,
    PayoutCycleDays     INTEGER       NOT NULL,        -- min days between payouts
    CONSTRAINT pk_propfirm       PRIMARY KEY (FirmID),
    CONSTRAINT uq_propfirm_name  UNIQUE (FirmName),
    CONSTRAINT ck_propfirm_cycle CHECK (PayoutCycleDays > 0)
);

-- Disjoint, total specialization (Evaluation | Funded) stored in one table.
-- ck_accountplan_eval / ck_accountplan_funded enforce which subtype columns are used.
CREATE TABLE AccountPlan (
    PlanID              INTEGER       NOT NULL,
    FirmID              INTEGER       NOT NULL,
    PlanName            VARCHAR(60)   NOT NULL,
    PlanType            VARCHAR(10)   NOT NULL,
    StartingBalance     NUMERIC(12,2) NOT NULL,
    ProfitTarget        NUMERIC(12,2),                 -- Evaluation only
    MaxTrailingDrawdown NUMERIC(12,2) NOT NULL,
    DailyLossLimit      NUMERIC(12,2),                 -- NULL if the plan has none
    ConsistencyRulePct  NUMERIC(5,2),                  -- max share of profit from one day
    MinTradingDays      INTEGER,                       -- Evaluation only
    MaxContracts        INTEGER       NOT NULL,
    ProfitSplitPct      NUMERIC(5,2),                  -- Funded only
    PlanFee             NUMERIC(10,2) NOT NULL,
    CONSTRAINT pk_accountplan           PRIMARY KEY (PlanID),
    CONSTRAINT fk_accountplan_firm      FOREIGN KEY (FirmID) REFERENCES PropFirm (FirmID),
    CONSTRAINT uq_accountplan_firm_name UNIQUE (FirmID, PlanName),
    CONSTRAINT ck_accountplan_type      CHECK (PlanType IN ('Evaluation', 'Funded')),
    CONSTRAINT ck_accountplan_eval      CHECK (PlanType <> 'Evaluation'
        OR (ProfitTarget IS NOT NULL AND MinTradingDays IS NOT NULL AND ProfitSplitPct IS NULL)),
    CONSTRAINT ck_accountplan_funded    CHECK (PlanType <> 'Funded'
        OR (ProfitSplitPct IS NOT NULL AND ProfitTarget IS NULL AND MinTradingDays IS NULL)),
    CONSTRAINT ck_accountplan_amounts   CHECK (StartingBalance > 0 AND MaxTrailingDrawdown > 0
        AND PlanFee >= 0 AND MaxContracts > 0),
    CONSTRAINT ck_accountplan_pcts      CHECK (ConsistencyRulePct BETWEEN 0 AND 100
        AND ProfitSplitPct BETWEEN 0 AND 100)
);

CREATE TABLE Exchange (
    ExchangeCode        VARCHAR(10)   NOT NULL,
    ExchangeName        VARCHAR(80)   NOT NULL,
    TimeZone            VARCHAR(40)   NOT NULL,
    CONSTRAINT pk_exchange PRIMARY KEY (ExchangeCode)
);

-- FullSizeRoot: recursive link from a micro contract to its full-size product (MNQ -> NQ).
-- It is filled in by 02_load.sql after the products are loaded.
CREATE TABLE Product (
    RootSymbol          VARCHAR(6)    NOT NULL,
    ExchangeCode        VARCHAR(10)   NOT NULL,
    FullSizeRoot        VARCHAR(6),
    ProductName         VARCHAR(60)   NOT NULL,
    AssetClass          VARCHAR(20)   NOT NULL,
    TickSize            NUMERIC(10,4) NOT NULL,
    TickValue           NUMERIC(10,2) NOT NULL,
    IsMicro             BOOLEAN       NOT NULL,
    CONSTRAINT pk_product            PRIMARY KEY (RootSymbol),
    CONSTRAINT fk_product_exchange   FOREIGN KEY (ExchangeCode) REFERENCES Exchange (ExchangeCode),
    CONSTRAINT fk_product_fullsize   FOREIGN KEY (FullSizeRoot) REFERENCES Product (RootSymbol),
    CONSTRAINT ck_product_ticks      CHECK (TickSize > 0 AND TickValue > 0),
    CONSTRAINT ck_product_assetclass CHECK (AssetClass IN ('Equity Index', 'Energy', 'Metals')),
    CONSTRAINT ck_product_fullsize   CHECK (FullSizeRoot IS NULL OR IsMicro)
);

CREATE TABLE Instrument (
    Symbol              VARCHAR(10)   NOT NULL,        -- e.g. NQZ5
    RootSymbol          VARCHAR(6)    NOT NULL,
    ContractMonth       DATE          NOT NULL,
    ExpirationDate      DATE          NOT NULL,
    CONSTRAINT pk_instrument            PRIMARY KEY (Symbol),
    CONSTRAINT fk_instrument_product    FOREIGN KEY (RootSymbol) REFERENCES Product (RootSymbol),
    CONSTRAINT uq_instrument_root_month UNIQUE (RootSymbol, ContractMonth)
);

CREATE TABLE Strategy (
    StrategyID          INTEGER       NOT NULL,
    StrategyName        VARCHAR(60)   NOT NULL,
    Style               VARCHAR(30)   NOT NULL,        -- breakout, mean reversion, ...
    Timeframe           VARCHAR(10)   NOT NULL,
    Description         VARCHAR(255)  NOT NULL,
    CONSTRAINT pk_strategy      PRIMARY KEY (StrategyID),
    CONSTRAINT uq_strategy_name UNIQUE (StrategyName)
);

-- Associative entity: M:N between Strategy and Product
CREATE TABLE StrategyApproval (
    StrategyID          INTEGER       NOT NULL,
    RootSymbol          VARCHAR(6)    NOT NULL,
    MaxContracts        INTEGER       NOT NULL,
    EnabledDate         DATE          NOT NULL,
    CONSTRAINT pk_strategyapproval    PRIMARY KEY (StrategyID, RootSymbol),
    CONSTRAINT fk_approval_strategy   FOREIGN KEY (StrategyID) REFERENCES Strategy (StrategyID),
    CONSTRAINT fk_approval_product    FOREIGN KEY (RootSymbol) REFERENCES Product (RootSymbol),
    CONSTRAINT ck_approval_maxcontracts CHECK (MaxContracts > 0)
);

-- No stored relationship: sessions and events are matched to trades by timestamp in the ETL
CREATE TABLE TradingSession (
    SessionID           INTEGER       NOT NULL,
    SessionName         VARCHAR(30)   NOT NULL,
    StartTimeET         TIME          NOT NULL,
    EndTimeET           TIME          NOT NULL,        -- Asia session wraps past midnight
    CONSTRAINT pk_tradingsession      PRIMARY KEY (SessionID),
    CONSTRAINT uq_tradingsession_name UNIQUE (SessionName)
);

CREATE TABLE EconomicEvent (
    EventID             INTEGER       NOT NULL,
    EventDate           DATE          NOT NULL,
    EventTimeET         TIME          NOT NULL,
    EventName           VARCHAR(60)   NOT NULL,
    Impact              VARCHAR(6)    NOT NULL,
    CONSTRAINT pk_economicevent        PRIMARY KEY (EventID),
    CONSTRAINT uq_economicevent_date_name UNIQUE (EventDate, EventName),
    CONSTRAINT ck_economicevent_impact CHECK (Impact IN ('High', 'Medium', 'Low'))
);

-- ---------- TRANSACTIONAL DATA ----------

CREATE TABLE Account (
    AccountID           INTEGER       NOT NULL,
    PlanID              INTEGER       NOT NULL,
    ParentAccountID     INTEGER,                       -- evaluation that earned this funded account
    AccountLabel        VARCHAR(30)   NOT NULL,
    Platform            VARCHAR(30)   NOT NULL,
    OpenDate            DATE          NOT NULL,
    CloseDate           DATE,
    Status              VARCHAR(12)   NOT NULL,
    CONSTRAINT pk_account        PRIMARY KEY (AccountID),
    CONSTRAINT fk_account_plan   FOREIGN KEY (PlanID) REFERENCES AccountPlan (PlanID),
    CONSTRAINT fk_account_parent FOREIGN KEY (ParentAccountID) REFERENCES Account (AccountID),
    CONSTRAINT uq_account_label  UNIQUE (AccountLabel),
    CONSTRAINT ck_account_status CHECK (Status IN ('Active', 'Passed', 'Failed', 'Breached', 'Closed')),
    CONSTRAINT ck_account_closed CHECK ((Status = 'Active') = (CloseDate IS NULL)),
    CONSTRAINT ck_account_dates  CHECK (CloseDate >= OpenDate)
);

CREATE TABLE AccountCharge (
    ChargeID            INTEGER       NOT NULL,
    AccountID           INTEGER       NOT NULL,
    ChargeDate          DATE          NOT NULL,
    ChargeType          VARCHAR(20)   NOT NULL,
    Amount              NUMERIC(10,2) NOT NULL,
    CONSTRAINT pk_accountcharge  PRIMARY KEY (ChargeID),
    CONSTRAINT fk_charge_account FOREIGN KEY (AccountID) REFERENCES Account (AccountID),
    CONSTRAINT ck_charge_type    CHECK (ChargeType IN ('Evaluation', 'Activation', 'Reset', 'Monthly')),
    CONSTRAINT ck_charge_amount  CHECK (Amount > 0)
);

CREATE TABLE Trade (
    TradeID             INTEGER       NOT NULL,
    AccountID           INTEGER       NOT NULL,
    StrategyID          INTEGER       NOT NULL,
    Symbol              VARCHAR(10)   NOT NULL,
    LeaderTradeID       INTEGER,                       -- NULL = leader trade; else copied trade
    Direction           VARCHAR(5)    NOT NULL,
    Contracts           INTEGER       NOT NULL,
    EntryTime           TIMESTAMP     NOT NULL,
    ExitTime            TIMESTAMP     NOT NULL,
    AvgEntryPrice       NUMERIC(12,4) NOT NULL,
    AvgExitPrice        NUMERIC(12,4) NOT NULL,
    Commission          NUMERIC(10,2) NOT NULL DEFAULT 0,
    CONSTRAINT pk_trade            PRIMARY KEY (TradeID),
    CONSTRAINT fk_trade_account    FOREIGN KEY (AccountID) REFERENCES Account (AccountID),
    CONSTRAINT fk_trade_strategy   FOREIGN KEY (StrategyID) REFERENCES Strategy (StrategyID),
    CONSTRAINT fk_trade_instrument FOREIGN KEY (Symbol) REFERENCES Instrument (Symbol),
    CONSTRAINT fk_trade_leader     FOREIGN KEY (LeaderTradeID) REFERENCES Trade (TradeID),
    CONSTRAINT ck_trade_direction  CHECK (Direction IN ('Long', 'Short')),
    CONSTRAINT ck_trade_contracts  CHECK (Contracts > 0),
    CONSTRAINT ck_trade_times      CHECK (ExitTime >= EntryTime),
    CONSTRAINT ck_trade_prices     CHECK (AvgEntryPrice > 0 AND AvgExitPrice > 0 AND Commission >= 0),
    CONSTRAINT ck_trade_leader_self CHECK (LeaderTradeID <> TradeID)
);

-- Weak entity of Trade: identified by (TradeID, LegNo)
CREATE TABLE Fill (
    TradeID             INTEGER       NOT NULL,
    LegNo               INTEGER       NOT NULL,
    FillTime            TIMESTAMP     NOT NULL,
    Side                VARCHAR(4)    NOT NULL,
    Quantity            INTEGER       NOT NULL,
    Price               NUMERIC(12,4) NOT NULL,
    OrderType           VARCHAR(10)   NOT NULL,
    CONSTRAINT pk_fill           PRIMARY KEY (TradeID, LegNo),
    CONSTRAINT fk_fill_trade     FOREIGN KEY (TradeID) REFERENCES Trade (TradeID) ON DELETE CASCADE,
    CONSTRAINT ck_fill_side      CHECK (Side IN ('Buy', 'Sell')),
    CONSTRAINT ck_fill_quantity  CHECK (Quantity > 0),
    CONSTRAINT ck_fill_ordertype CHECK (OrderType IN ('Market', 'Limit', 'Stop')),
    CONSTRAINT ck_fill_values    CHECK (LegNo > 0 AND Price > 0)
);

-- Weak entity of Account: end-of-day statement snapshot
CREATE TABLE DailyAccountBalance (
    AccountID           INTEGER       NOT NULL,
    TradeDate           DATE          NOT NULL,
    StartBalance        NUMERIC(12,2) NOT NULL,
    EndBalance          NUMERIC(12,2) NOT NULL,
    HighWaterMark       NUMERIC(12,2) NOT NULL,
    DrawdownFloor       NUMERIC(12,2) NOT NULL,
    CONSTRAINT pk_dailyaccountbalance PRIMARY KEY (AccountID, TradeDate),
    CONSTRAINT fk_balance_account     FOREIGN KEY (AccountID) REFERENCES Account (AccountID) ON DELETE CASCADE,
    CONSTRAINT ck_balance_levels      CHECK (DrawdownFloor <= HighWaterMark AND EndBalance <= HighWaterMark)
);

CREATE TABLE RuleViolation (
    ViolationID         INTEGER       NOT NULL,
    AccountID           INTEGER       NOT NULL,
    ViolationDate       DATE          NOT NULL,
    RuleType            VARCHAR(20)   NOT NULL,
    Details             VARCHAR(255)  NOT NULL,
    CONSTRAINT pk_ruleviolation     PRIMARY KEY (ViolationID),
    CONSTRAINT fk_violation_account FOREIGN KEY (AccountID) REFERENCES Account (AccountID),
    CONSTRAINT ck_violation_ruletype CHECK (RuleType IN
        ('TrailingDrawdown', 'DailyLossLimit', 'Consistency', 'MaxContracts'))
);

CREATE TABLE Payout (
    PayoutID            INTEGER       NOT NULL,
    AccountID           INTEGER       NOT NULL,
    RequestDate         DATE          NOT NULL,
    GrossAmount         NUMERIC(12,2) NOT NULL,
    TraderShare         NUMERIC(12,2) NOT NULL,
    Status              VARCHAR(10)   NOT NULL,
    PaidDate            DATE,
    CONSTRAINT pk_payout         PRIMARY KEY (PayoutID),
    CONSTRAINT fk_payout_account FOREIGN KEY (AccountID) REFERENCES Account (AccountID),
    CONSTRAINT ck_payout_status  CHECK (Status IN ('Requested', 'Paid', 'Denied')),
    CONSTRAINT ck_payout_paid    CHECK ((Status = 'Paid') = (PaidDate IS NOT NULL)),
    CONSTRAINT ck_payout_amounts CHECK (GrossAmount > 0 AND TraderShare > 0
        AND TraderShare <= GrossAmount AND PaidDate >= RequestDate)
);

-- ---------- INDEXES ----------
-- One index per foreign key column (FKs that lead a primary key are already indexed),
-- plus Trade.EntryTime for the date-range filters the ETL will use.

CREATE INDEX ix_accountplan_firm       ON AccountPlan (FirmID);
CREATE INDEX ix_product_exchange       ON Product (ExchangeCode);
CREATE INDEX ix_product_fullsize       ON Product (FullSizeRoot);
CREATE INDEX ix_instrument_product     ON Instrument (RootSymbol);
CREATE INDEX ix_approval_product       ON StrategyApproval (RootSymbol);
CREATE INDEX ix_account_plan           ON Account (PlanID);
CREATE INDEX ix_account_parent         ON Account (ParentAccountID);
CREATE INDEX ix_charge_account         ON AccountCharge (AccountID);
CREATE INDEX ix_trade_account          ON Trade (AccountID);
CREATE INDEX ix_trade_strategy         ON Trade (StrategyID);
CREATE INDEX ix_trade_symbol           ON Trade (Symbol);
CREATE INDEX ix_trade_leader           ON Trade (LeaderTradeID);
CREATE INDEX ix_trade_entrytime        ON Trade (EntryTime);
CREATE INDEX ix_violation_account      ON RuleViolation (AccountID);
CREATE INDEX ix_payout_account         ON Payout (AccountID);
