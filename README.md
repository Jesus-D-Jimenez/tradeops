# TradeOps: Prop-Firm Futures Trading Operations

Semester project for **IE6750 Data Warehousing & Integration** (Northeastern University), Group 08.

TradeOps is an operational (OLTP) database for a futures trading operation that trades with capital from proprietary trading firms. One trade is copied into many evaluation and funded accounts at once, and each firm has its own rules, fees, and payout schedule. Later milestones build a data warehouse and ETL pipeline on top of this database to measure net return (payouts minus fees) and risk by firm, strategy, instrument, and session.

## Schema

16 tables in Third Normal Form:

| Static reference data | Transactional data |
|---|---|
| PropFirm, AccountPlan, Exchange, Product, Instrument, Strategy, StrategyApproval, TradingSession, EconomicEvent | Account, AccountCharge, Trade, Fill, DailyAccountBalance, RuleViolation, Payout |

Notable design choices:
- Plan rules (profit target, trailing drawdown, consistency %) live on `AccountPlan`, not `Account`, to keep 3NF.
- `Account.ParentAccountID` links a funded account to the evaluation that earned it.
- `Trade.LeaderTradeID` links each copied trade to its leader trade.
- `Fill` is a weak entity keyed by `(TradeID, LegNo)`.

## Data

Synthetic and seeded (the same data on every run), covering Jan 2025 to Aug 2026. Product tick sizes and values match real CME Group contracts; the economic calendar follows real release patterns. Firm plan rules and fees are simplified values stored as reference data.

| Table | Rows |
|---|---|
| Trade | 6,322 |
| Fill | 13,944 |
| DailyAccountBalance | 2,916 |
| Account | 134 |
| All 16 tables | see `data/` |

## Files

| File | Purpose |
|---|---|
| `schema.sql` | DDL (PostgreSQL / DuckDB syntax) |
| `add_foreign_keys_mysql.sql` | Adds table-level foreign keys for MySQL 8.0, which ignores inline `REFERENCES` |
| `generate_data.py` | Generates the CSVs in `data/` and builds `tradeops.duckdb` |
| `load_mysql.py` | Loads the CSVs into MySQL tables created from `schema.sql` |
| `data/` | One CSV per table |

## Quick start

DuckDB (builds the whole database in one step):

```bash
uv venv --python 3.12
uv pip install duckdb
.venv/Scripts/python generate_data.py      # Windows; use .venv/bin/python on macOS/Linux
```

MySQL:

1. Run `schema.sql`, then `add_foreign_keys_mysql.sql`, in a new schema.
2. `uv pip install mysql-connector-python`
3. `.venv/Scripts/python load_mysql.py` and enter the schema name when prompted.

## Author

Jesus D. Jimenez Ballestas
