-- ============================================================
-- IE6750 Milestone 1 - Operational Database (OLTP)
-- Prop-Firm Futures Trading Operations
-- ============================================================

-- ---------- STATIC REFERENCE DATA ----------

CREATE TABLE PropFirm (
    FirmID              INTEGER PRIMARY KEY,
    FirmName            VARCHAR(60)  NOT NULL UNIQUE,
    Website             VARCHAR(100),
    PayoutCycleDays     INTEGER      NOT NULL          -- min days between payouts
);

CREATE TABLE AccountPlan (
    PlanID              INTEGER PRIMARY KEY,
    FirmID              INTEGER      NOT NULL REFERENCES PropFirm(FirmID),
    PlanName            VARCHAR(60)  NOT NULL,
    PlanType            VARCHAR(10)  NOT NULL CHECK (PlanType IN ('Evaluation','Funded')),
    StartingBalance     DECIMAL(12,2) NOT NULL,
    ProfitTarget        DECIMAL(12,2),                 -- NULL for funded plans
    MaxTrailingDrawdown DECIMAL(12,2) NOT NULL,
    DailyLossLimit      DECIMAL(12,2),                 -- NULL if the plan has none
    ConsistencyRulePct  DECIMAL(5,2),                  -- max share of profit from one day
    MinTradingDays      INTEGER,
    MaxContracts        INTEGER      NOT NULL,
    ProfitSplitPct      DECIMAL(5,2),                  -- NULL for evaluation plans
    PlanFee             DECIMAL(10,2) NOT NULL,
    UNIQUE (FirmID, PlanName)
);

CREATE TABLE Exchange (
    ExchangeCode        VARCHAR(10)  PRIMARY KEY,
    ExchangeName        VARCHAR(80)  NOT NULL,
    TimeZone            VARCHAR(40)  NOT NULL
);

CREATE TABLE Product (
    RootSymbol          VARCHAR(6)   PRIMARY KEY,
    ProductName         VARCHAR(60)  NOT NULL,
    ExchangeCode        VARCHAR(10)  NOT NULL REFERENCES Exchange(ExchangeCode),
    AssetClass          VARCHAR(20)  NOT NULL,
    TickSize            DECIMAL(10,4) NOT NULL,
    TickValue           DECIMAL(10,2) NOT NULL,
    IsMicro             BOOLEAN      NOT NULL
);

CREATE TABLE Instrument (
    Symbol              VARCHAR(10)  PRIMARY KEY,      -- e.g. NQZ5
    RootSymbol          VARCHAR(6)   NOT NULL REFERENCES Product(RootSymbol),
    ContractMonth       DATE         NOT NULL,
    ExpirationDate      DATE         NOT NULL
);

CREATE TABLE Strategy (
    StrategyID          INTEGER PRIMARY KEY,
    StrategyName        VARCHAR(60)  NOT NULL UNIQUE,
    Style               VARCHAR(30)  NOT NULL,         -- breakout, mean reversion, ...
    Timeframe           VARCHAR(10)  NOT NULL,
    Description         VARCHAR(255)
);

CREATE TABLE StrategyApproval (                        -- M:N Strategy x Product
    StrategyID          INTEGER      NOT NULL REFERENCES Strategy(StrategyID),
    RootSymbol          VARCHAR(6)   NOT NULL REFERENCES Product(RootSymbol),
    MaxContracts        INTEGER      NOT NULL,
    EnabledDate         DATE         NOT NULL,
    PRIMARY KEY (StrategyID, RootSymbol)
);

CREATE TABLE TradingSession (
    SessionID           INTEGER PRIMARY KEY,
    SessionName         VARCHAR(30)  NOT NULL UNIQUE,
    StartTimeET         TIME         NOT NULL,
    EndTimeET           TIME         NOT NULL
);

CREATE TABLE EconomicEvent (
    EventID             INTEGER PRIMARY KEY,
    EventDate           DATE         NOT NULL,
    EventTimeET         TIME         NOT NULL,
    EventName           VARCHAR(60)  NOT NULL,
    Impact              VARCHAR(6)   NOT NULL CHECK (Impact IN ('High','Medium','Low'))
);

-- ---------- TRANSACTIONAL DATA ----------

CREATE TABLE Account (
    AccountID           INTEGER PRIMARY KEY,
    PlanID              INTEGER      NOT NULL REFERENCES AccountPlan(PlanID),
    ParentAccountID     INTEGER      REFERENCES Account(AccountID), -- eval that produced this funded acct
    AccountLabel        VARCHAR(30)  NOT NULL UNIQUE,
    Platform            VARCHAR(30)  NOT NULL,
    OpenDate            DATE         NOT NULL,
    CloseDate           DATE,
    Status              VARCHAR(12)  NOT NULL
        CHECK (Status IN ('Active','Passed','Failed','Breached','Closed'))
);

CREATE TABLE AccountCharge (
    ChargeID            INTEGER PRIMARY KEY,
    AccountID           INTEGER      NOT NULL REFERENCES Account(AccountID),
    ChargeDate          DATE         NOT NULL,
    ChargeType          VARCHAR(20)  NOT NULL
        CHECK (ChargeType IN ('Evaluation','Activation','Reset','Monthly')),
    Amount              DECIMAL(10,2) NOT NULL
);

CREATE TABLE Trade (
    TradeID             INTEGER PRIMARY KEY,
    AccountID           INTEGER      NOT NULL REFERENCES Account(AccountID),
    StrategyID          INTEGER      NOT NULL REFERENCES Strategy(StrategyID),
    Symbol              VARCHAR(10)  NOT NULL REFERENCES Instrument(Symbol),
    LeaderTradeID       INTEGER      REFERENCES Trade(TradeID), -- NULL = leader; else copied trade
    Direction           VARCHAR(5)   NOT NULL CHECK (Direction IN ('Long','Short')),
    Contracts           INTEGER      NOT NULL CHECK (Contracts > 0),
    EntryTime           TIMESTAMP    NOT NULL,
    ExitTime            TIMESTAMP,
    AvgEntryPrice       DECIMAL(12,4) NOT NULL,
    AvgExitPrice        DECIMAL(12,4),
    Commission          DECIMAL(10,2) NOT NULL DEFAULT 0
);

CREATE TABLE Fill (                                    -- weak entity of Trade
    TradeID             INTEGER      NOT NULL REFERENCES Trade(TradeID),
    LegNo               INTEGER      NOT NULL,
    FillTime            TIMESTAMP    NOT NULL,
    Side                VARCHAR(4)   NOT NULL CHECK (Side IN ('Buy','Sell')),
    Quantity            INTEGER      NOT NULL CHECK (Quantity > 0),
    Price               DECIMAL(12,4) NOT NULL,
    OrderType           VARCHAR(10)  NOT NULL CHECK (OrderType IN ('Market','Limit','Stop')),
    PRIMARY KEY (TradeID, LegNo)
);

CREATE TABLE DailyAccountBalance (                     -- end-of-day statement snapshot
    AccountID           INTEGER      NOT NULL REFERENCES Account(AccountID),
    TradeDate           DATE         NOT NULL,
    StartBalance        DECIMAL(12,2) NOT NULL,
    EndBalance          DECIMAL(12,2) NOT NULL,
    HighWaterMark       DECIMAL(12,2) NOT NULL,
    DrawdownFloor       DECIMAL(12,2) NOT NULL,
    PRIMARY KEY (AccountID, TradeDate)
);

CREATE TABLE RuleViolation (
    ViolationID         INTEGER PRIMARY KEY,
    AccountID           INTEGER      NOT NULL REFERENCES Account(AccountID),
    ViolationDate       DATE         NOT NULL,
    RuleType            VARCHAR(20)  NOT NULL
        CHECK (RuleType IN ('TrailingDrawdown','DailyLossLimit','Consistency','MaxContracts')),
    Details             VARCHAR(255)
);

CREATE TABLE Payout (
    PayoutID            INTEGER PRIMARY KEY,
    AccountID           INTEGER      NOT NULL REFERENCES Account(AccountID),
    RequestDate         DATE         NOT NULL,
    GrossAmount         DECIMAL(12,2) NOT NULL,
    TraderShare         DECIMAL(12,2) NOT NULL,
    Status              VARCHAR(10)  NOT NULL CHECK (Status IN ('Requested','Paid','Denied')),
    PaidDate            DATE
);
