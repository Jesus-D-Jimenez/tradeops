-- ============================================================
-- TradeOps - Milestone 3
-- 05_dw_schema.sql: ROLAP data warehouse in schema tradeops_dw.
-- Fact constellation: four fact tables share conformed,
-- denormalized (star) dimensions. Surrogate keys everywhere;
-- source keys are kept as natural-key attributes.
-- ============================================================

DROP SCHEMA IF EXISTS tradeops_dw CASCADE;
CREATE SCHEMA tradeops_dw;
SET search_path TO tradeops_dw;

-- ------------------------------------------------------------
-- Dimensions
-- ------------------------------------------------------------

-- Calendar dimension. Two hierarchies:
--   Calendar: Date -> Month -> Quarter -> Year   (also Date -> Week)
--   Event:    Date -> MajorEvent -> EventDayType
CREATE TABLE dim_date (
    date_key            INTEGER      NOT NULL,      -- yyyymmdd
    full_date           DATE         NOT NULL,
    day_of_week         SMALLINT     NOT NULL,      -- ISO: 1 = Monday
    day_name            VARCHAR(9)   NOT NULL,
    is_weekday          BOOLEAN      NOT NULL,
    iso_week            SMALLINT     NOT NULL,
    month_num           SMALLINT     NOT NULL,
    month_name          VARCHAR(9)   NOT NULL,
    year_month          CHAR(7)      NOT NULL,      -- '2026-03'
    quarter_num         SMALLINT     NOT NULL,
    year_quarter        CHAR(7)      NOT NULL,      -- '2026-Q1'
    year_num            SMALLINT     NOT NULL,
    major_event         VARCHAR(30)  NOT NULL,      -- CPI, Nonfarm Payrolls, FOMC Rate Decision, or 'None'
    major_event_time_et TIME,
    event_day_type      VARCHAR(20)  NOT NULL,      -- 'Major event day' / 'Regular day'
    CONSTRAINT pk_dim_date PRIMARY KEY (date_key),
    CONSTRAINT ck_dim_date_key CHECK (date_key = TO_CHAR(full_date, 'YYYYMMDD')::INTEGER),
    CONSTRAINT ck_dim_date_event CHECK (event_day_type IN ('Major event day', 'Regular day')),
    CONSTRAINT uq_dim_date_full UNIQUE (full_date)
);

-- Time-of-day dimension at minute grain (1,440 rows).
--   Minute -> Hour;  Minute -> Session -> Market period
CREATE TABLE dim_time (
    time_key            SMALLINT     NOT NULL,      -- hhmm, e.g. 935 = 09:35
    time_of_day         TIME         NOT NULL,
    hour_num            SMALLINT     NOT NULL,
    minute_num          SMALLINT     NOT NULL,
    session_name        VARCHAR(20)  NOT NULL,      -- Asia, London, NY Open, NY Midday, NY Close, Maintenance
    session_start_et    TIME,
    session_end_et      TIME,
    market_period       VARCHAR(20)  NOT NULL,      -- Overnight, US Regular Hours, Closed
    CONSTRAINT pk_dim_time PRIMARY KEY (time_key),
    CONSTRAINT ck_dim_time_key CHECK (time_key = hour_num * 100 + minute_num)
);

-- Account dimension (Account -> Plan -> Firm; Account -> Account type;
-- Account -> Account size). Prepared as an SCD Type 2 dimension:
-- a change in plan rules inserts a new row with a new account_key.
CREATE TABLE dim_account (
    account_key         SERIAL       NOT NULL,
    account_id          INTEGER      NOT NULL,      -- natural key
    account_label       VARCHAR(30)  NOT NULL,
    platform            VARCHAR(30)  NOT NULL,
    parent_account_id   INTEGER,                    -- recursive: evaluation that earned this funded account
    account_type        VARCHAR(10)  NOT NULL,      -- Evaluation / Funded
    account_size        VARCHAR(5)   NOT NULL,      -- 50K / 150K
    plan_id             INTEGER      NOT NULL,
    plan_name           VARCHAR(60)  NOT NULL,
    starting_balance    NUMERIC(12,2) NOT NULL,
    profit_target       NUMERIC(12,2),
    max_trailing_drawdown NUMERIC(12,2) NOT NULL,
    daily_loss_limit    NUMERIC(12,2),
    profit_split_pct    NUMERIC(5,2),
    plan_fee            NUMERIC(10,2) NOT NULL,
    firm_id             INTEGER      NOT NULL,
    firm_name           VARCHAR(60)  NOT NULL,
    payout_cycle_days   INTEGER      NOT NULL,
    valid_from          DATE         NOT NULL,
    valid_to            DATE         NOT NULL DEFAULT DATE '9999-12-31',
    is_current          BOOLEAN      NOT NULL DEFAULT TRUE,
    CONSTRAINT pk_dim_account PRIMARY KEY (account_key),
    CONSTRAINT uq_dim_account_version UNIQUE (account_id, valid_from),
    CONSTRAINT ck_dim_account_type CHECK (account_type IN ('Evaluation', 'Funded')),
    CONSTRAINT ck_dim_account_validity CHECK (valid_from <= valid_to),
    CONSTRAINT ck_dim_account_split CHECK (profit_split_pct IS NULL OR profit_split_pct BETWEEN 0 AND 100)
);
-- SCD Type 2: at most one current version per natural key.
CREATE UNIQUE INDEX uq_dim_account_current ON dim_account (account_id) WHERE is_current;

-- Instrument dimension (Contract month -> Product -> Family -> Asset class;
-- Product -> Exchange). Family groups a micro with its full-size product.
CREATE TABLE dim_instrument (
    instrument_key      SERIAL       NOT NULL,
    symbol              VARCHAR(10)  NOT NULL,      -- natural key, e.g. MNQZ5
    contract_month      DATE         NOT NULL,
    expiration_date     DATE         NOT NULL,
    root_symbol         VARCHAR(6)   NOT NULL,
    product_name        VARCHAR(60)  NOT NULL,
    contract_size       VARCHAR(10)  NOT NULL,      -- Micro / Full-size
    tick_size           NUMERIC(10,4) NOT NULL,
    tick_value          NUMERIC(10,2) NOT NULL,
    family_root         VARCHAR(6)   NOT NULL,      -- NQ for both NQ and MNQ
    family_name         VARCHAR(60)  NOT NULL,
    asset_class         VARCHAR(20)  NOT NULL,
    exchange_code       VARCHAR(10)  NOT NULL,
    exchange_name       VARCHAR(80)  NOT NULL,
    CONSTRAINT pk_dim_instrument PRIMARY KEY (instrument_key),
    CONSTRAINT uq_dim_instrument_symbol UNIQUE (symbol),
    CONSTRAINT ck_dim_instrument_size CHECK (contract_size IN ('Micro', 'Full-size')),
    CONSTRAINT ck_dim_instrument_tick CHECK (tick_size > 0 AND tick_value > 0)
);

-- Strategy dimension (Strategy -> Style). SCD Type 2 ready.
CREATE TABLE dim_strategy (
    strategy_key        SERIAL       NOT NULL,
    strategy_id         INTEGER      NOT NULL,
    strategy_name       VARCHAR(60)  NOT NULL,
    style               VARCHAR(30)  NOT NULL,
    timeframe           VARCHAR(10)  NOT NULL,
    approved_products   SMALLINT     NOT NULL,      -- number of products the strategy may trade
    valid_from          DATE         NOT NULL,
    valid_to            DATE         NOT NULL DEFAULT DATE '9999-12-31',
    is_current          BOOLEAN      NOT NULL DEFAULT TRUE,
    CONSTRAINT pk_dim_strategy PRIMARY KEY (strategy_key),
    CONSTRAINT uq_dim_strategy_version UNIQUE (strategy_id, valid_from),
    CONSTRAINT ck_dim_strategy_validity CHECK (valid_from <= valid_to)
);
CREATE UNIQUE INDEX uq_dim_strategy_current ON dim_strategy (strategy_id) WHERE is_current;

-- Trade role: leader trade or copied trade.
CREATE TABLE dim_trade_role (
    role_key            SMALLINT     NOT NULL,
    role_name           VARCHAR(10)  NOT NULL,
    CONSTRAINT pk_dim_trade_role PRIMARY KEY (role_key),
    CONSTRAINT uq_dim_trade_role UNIQUE (role_name)
);

-- Cash-flow type (Type -> Category). direction: -1 money out, +1 money in, 0 none.
CREATE TABLE dim_cash_flow_type (
    cash_flow_type_key  SMALLINT     NOT NULL,
    cash_flow_type      VARCHAR(20)  NOT NULL,
    category            VARCHAR(10)  NOT NULL,      -- Fee / Payout
    direction           SMALLINT     NOT NULL,
    CONSTRAINT pk_dim_cash_flow_type PRIMARY KEY (cash_flow_type_key),
    CONSTRAINT uq_dim_cash_flow_type UNIQUE (cash_flow_type),
    CONSTRAINT ck_dim_cash_flow_dir CHECK (direction IN (-1, 0, 1))
);

-- Account status at the end of the lifecycle (Status -> Outcome).
CREATE TABLE dim_account_status (
    status_key          SMALLINT     NOT NULL,
    status_name         VARCHAR(12)  NOT NULL,
    outcome             VARCHAR(12)  NOT NULL,      -- Open / Success / Lost
    CONSTRAINT pk_dim_account_status PRIMARY KEY (status_key),
    CONSTRAINT uq_dim_account_status UNIQUE (status_name)
);

-- ------------------------------------------------------------
-- Facts
-- ------------------------------------------------------------

-- Transaction fact: one row per closed trade.
CREATE TABLE fact_trade (
    trade_id            INTEGER      NOT NULL,      -- degenerate dimension
    leader_trade_id     INTEGER,                    -- degenerate dimension (NULL for leaders)
    date_key            INTEGER      NOT NULL,
    time_key            SMALLINT     NOT NULL,
    account_key         INTEGER      NOT NULL,
    instrument_key      INTEGER      NOT NULL,
    strategy_key        INTEGER      NOT NULL,
    role_key            SMALLINT     NOT NULL,
    direction           VARCHAR(5)   NOT NULL,      -- degenerate dimension
    contracts           INTEGER      NOT NULL,      -- flow, additive
    pnl_ticks           NUMERIC(10,2) NOT NULL,     -- flow, additive
    gross_pnl           NUMERIC(12,2) NOT NULL,     -- flow, additive
    commission          NUMERIC(10,2) NOT NULL,     -- flow, additive
    net_pnl             NUMERIC(12,2) NOT NULL,     -- flow, additive
    holding_seconds     INTEGER      NOT NULL,      -- unit, non-additive (AVG/MIN/MAX)
    slippage_ticks      NUMERIC(10,2),              -- leader ticks - copy ticks; NULL for leaders
    is_win              SMALLINT     NOT NULL,      -- 1 if net_pnl > 0 (for win rate)
    trade_count         SMALLINT     NOT NULL DEFAULT 1,
    CONSTRAINT pk_fact_trade PRIMARY KEY (trade_id),
    CONSTRAINT ck_ft_contracts  CHECK (contracts > 0),
    CONSTRAINT ck_ft_commission CHECK (commission >= 0),
    CONSTRAINT ck_ft_net_pnl    CHECK (net_pnl = gross_pnl - commission),
    CONSTRAINT ck_ft_holding    CHECK (holding_seconds >= 0),
    CONSTRAINT ck_ft_is_win     CHECK (is_win IN (0, 1)),
    CONSTRAINT ck_ft_copy       CHECK ((leader_trade_id IS NULL) = (slippage_ticks IS NULL)),
    CONSTRAINT fk_ft_date       FOREIGN KEY (date_key)       REFERENCES dim_date (date_key),
    CONSTRAINT fk_ft_time       FOREIGN KEY (time_key)       REFERENCES dim_time (time_key),
    CONSTRAINT fk_ft_account    FOREIGN KEY (account_key)    REFERENCES dim_account (account_key),
    CONSTRAINT fk_ft_instrument FOREIGN KEY (instrument_key) REFERENCES dim_instrument (instrument_key),
    CONSTRAINT fk_ft_strategy   FOREIGN KEY (strategy_key)   REFERENCES dim_strategy (strategy_key),
    CONSTRAINT fk_ft_role       FOREIGN KEY (role_key)       REFERENCES dim_trade_role (role_key)
);

-- Periodic snapshot: one row per account per trading day.
CREATE TABLE fact_daily_balance (
    date_key            INTEGER      NOT NULL,
    account_key         INTEGER      NOT NULL,
    start_balance       NUMERIC(12,2) NOT NULL,     -- level, semi-additive
    end_balance         NUMERIC(12,2) NOT NULL,     -- level, semi-additive
    high_water_mark     NUMERIC(12,2) NOT NULL,     -- level, semi-additive
    drawdown_floor      NUMERIC(12,2) NOT NULL,     -- level, semi-additive
    drawdown_cushion    NUMERIC(12,2) NOT NULL,     -- end_balance - drawdown_floor (level)
    daily_pnl           NUMERIC(12,2) NOT NULL,     -- end - start (flow, additive)
    trade_count         INTEGER      NOT NULL,      -- flow, additive
    violation_count     SMALLINT     NOT NULL,      -- flow, additive
    drawdown_violations SMALLINT     NOT NULL,
    daily_loss_violations SMALLINT   NOT NULL,
    consistency_violations SMALLINT  NOT NULL,
    CONSTRAINT pk_fact_daily_balance PRIMARY KEY (date_key, account_key),
    CONSTRAINT ck_fdb_cushion    CHECK (drawdown_cushion = end_balance - drawdown_floor),
    CONSTRAINT ck_fdb_counts     CHECK (trade_count >= 0 AND drawdown_violations >= 0
                                        AND daily_loss_violations >= 0 AND consistency_violations >= 0),
    CONSTRAINT ck_fdb_violations CHECK (violation_count = drawdown_violations
                                        + daily_loss_violations + consistency_violations),
    CONSTRAINT fk_fdb_date    FOREIGN KEY (date_key)    REFERENCES dim_date (date_key),
    CONSTRAINT fk_fdb_account FOREIGN KEY (account_key) REFERENCES dim_account (account_key)
);

-- Transaction fact: one row per fee charge or payout request.
CREATE TABLE fact_cash_flow (
    cash_flow_id        VARCHAR(12)  NOT NULL,      -- degenerate: 'CHG-17' / 'PAY-3'
    date_key            INTEGER      NOT NULL,      -- charge date, paid date, or request date if denied
    account_key         INTEGER      NOT NULL,
    cash_flow_type_key  SMALLINT     NOT NULL,
    amount              NUMERIC(12,2) NOT NULL,     -- signed: fees < 0, payouts received > 0 (flow, additive)
    gross_amount        NUMERIC(12,2) NOT NULL,     -- unsigned amount before profit split
    event_count         SMALLINT     NOT NULL DEFAULT 1,
    CONSTRAINT pk_fact_cash_flow PRIMARY KEY (cash_flow_id),
    CONSTRAINT ck_fcf_gross     CHECK (gross_amount >= 0),
    CONSTRAINT fk_fcf_date    FOREIGN KEY (date_key)           REFERENCES dim_date (date_key),
    CONSTRAINT fk_fcf_account FOREIGN KEY (account_key)        REFERENCES dim_account (account_key),
    CONSTRAINT fk_fcf_type    FOREIGN KEY (cash_flow_type_key) REFERENCES dim_cash_flow_type (cash_flow_type_key)
);

-- Accumulating snapshot: one row per account, updated as milestones occur.
-- Milestone dates are role-playing Date dimensions; NULL = not reached yet.
-- account_key always points to the current SCD2 version; a new version
-- re-points the row, so the grain stays one row per account.
CREATE TABLE fact_account_lifecycle (
    account_key         INTEGER      NOT NULL,
    open_date_key       INTEGER      NOT NULL,
    pass_date_key       INTEGER,                    -- evaluations that passed
    close_date_key      INTEGER,                    -- NULL while Active
    status_key          SMALLINT     NOT NULL,
    days_open           INTEGER      NOT NULL,      -- calendar days open (to close or to last data date)
    days_to_pass        INTEGER,                    -- NULL unless passed
    trading_days        INTEGER      NOT NULL,
    trade_count         INTEGER      NOT NULL,
    net_trading_pnl     NUMERIC(12,2) NOT NULL,
    total_fees          NUMERIC(12,2) NOT NULL,     -- positive amount paid to the firm
    total_payouts       NUMERIC(12,2) NOT NULL,     -- trader share received
    net_return          NUMERIC(12,2) NOT NULL,     -- total_payouts - total_fees
    reset_count         SMALLINT     NOT NULL,
    violation_count     SMALLINT     NOT NULL,
    is_passed           SMALLINT     NOT NULL,      -- 1/0, for pass rate
    CONSTRAINT pk_fact_account_lifecycle PRIMARY KEY (account_key),
    CONSTRAINT ck_fal_net_return CHECK (net_return = total_payouts - total_fees),
    CONSTRAINT ck_fal_is_passed  CHECK (is_passed IN (0, 1)),
    CONSTRAINT ck_fal_pass       CHECK ((pass_date_key IS NULL) = (days_to_pass IS NULL)),
    CONSTRAINT ck_fal_counts     CHECK (days_open >= 0 AND trading_days >= 0
                                        AND reset_count >= 0 AND violation_count >= 0),
    CONSTRAINT fk_fal_account FOREIGN KEY (account_key)    REFERENCES dim_account (account_key),
    CONSTRAINT fk_fal_open    FOREIGN KEY (open_date_key)  REFERENCES dim_date (date_key),
    CONSTRAINT fk_fal_pass    FOREIGN KEY (pass_date_key)  REFERENCES dim_date (date_key),
    CONSTRAINT fk_fal_close   FOREIGN KEY (close_date_key) REFERENCES dim_date (date_key),
    CONSTRAINT fk_fal_status  FOREIGN KEY (status_key)     REFERENCES dim_account_status (status_key)
);

-- ------------------------------------------------------------
-- ETL control table (outside the star schemas). One row per table
-- per load batch; high_water_mark is where the next incremental
-- load resumes (last trade_id, last balance date, etc.).
-- ------------------------------------------------------------
CREATE TABLE etl_load_log (
    batch_id            SERIAL       NOT NULL,
    table_name          VARCHAR(40)  NOT NULL,
    load_type           VARCHAR(12)  NOT NULL,
    loaded_at           TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    high_water_mark     VARCHAR(20),
    rows_inserted       INTEGER      NOT NULL DEFAULT 0,
    rows_updated        INTEGER      NOT NULL DEFAULT 0,
    CONSTRAINT pk_etl_load_log PRIMARY KEY (batch_id),
    CONSTRAINT ck_etl_load_type CHECK (load_type IN ('Full', 'Incremental')),
    CONSTRAINT ck_etl_rows CHECK (rows_inserted >= 0 AND rows_updated >= 0)
);

-- Indexes on fact foreign keys used by the OLAP queries.
CREATE INDEX ix_ft_date       ON fact_trade (date_key);
CREATE INDEX ix_ft_time       ON fact_trade (time_key);
CREATE INDEX ix_ft_account    ON fact_trade (account_key);
CREATE INDEX ix_ft_instrument ON fact_trade (instrument_key);
CREATE INDEX ix_ft_strategy   ON fact_trade (strategy_key);
CREATE INDEX ix_fdb_account   ON fact_daily_balance (account_key);
CREATE INDEX ix_fcf_date      ON fact_cash_flow (date_key);
CREATE INDEX ix_fcf_account   ON fact_cash_flow (account_key);
