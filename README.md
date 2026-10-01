# TradeOps: Prop-Firm Futures Trading Operations

Semester project for **IE6750 Data Warehousing & Integration** (Northeastern University), Group 08.

TradeOps is an operational (OLTP) database for a futures trading operation that trades with capital from proprietary trading firms. One trade is copied into many evaluation and funded accounts at once, and each firm has its own rules, fees, and payout schedule. Later milestones build a data warehouse and ETL pipeline on top of this database to measure net return (payouts minus fees) and risk by firm, strategy, instrument, and session.

## Schema

16 tables in Third Normal Form, implemented in PostgreSQL 16 (schema `tradeops`):

| Static reference data | Transactional data |
|---|---|
| PropFirm, AccountPlan, Exchange, Product, Instrument, Strategy, StrategyApproval, TradingSession, EconomicEvent | Account, AccountCharge, Trade, Fill, DailyAccountBalance, RuleViolation, Payout |

Notable design choices:
- `AccountPlan` is a disjoint, total specialization (Evaluation | Funded) stored as one table; `ck_accountplan_eval` and `ck_accountplan_funded` enforce which subtype columns are used.
- `Account.ParentAccountID` links a funded account to the evaluation that earned it.
- `Trade.LeaderTradeID` links each copied trade to its leader trade.
- `Product.FullSizeRoot` links each micro contract to its full-size product (MNQ to NQ).
- `Fill` (TradeID, LegNo) and `DailyAccountBalance` (AccountID, TradeDate) are weak entities.
- Every constraint is named: 16 primary keys, 17 foreign keys, 7 unique, 30 check, plus 15 indexes.
- Net P&L is not stored; the view `v_trade_pnl` calculates it from prices, tick size, and tick value.

## Data

Synthetic and seeded (the same data on every run), covering Jan 2025 to Aug 2026. Product tick sizes and values match real CME Group contracts; the economic calendar follows real release patterns. Firm plan rules and fees are simplified values stored as reference data. 24,228 rows in total, including 134 accounts, 6,322 trades, 13,944 fills, and 2,916 daily balances.

## Files

| File | Purpose |
|---|---|
| `sql/01_schema.sql` | Drops and recreates schema `tradeops`: 16 tables, all constraints, 15 indexes |
| `sql/02_load.sql` | Loads the 16 CSVs with `\copy` in one transaction, then sets `FullSizeRoot` |
| `sql/03_views.sql` | Creates `v_trade_pnl` (P&L in ticks and dollars, net of commission, holding time) |
| `sql/04_checks.sql` | Row counts, constraint inventory, and integrity checks |
| `sql/04_checks_output.txt` | Output of `04_checks.sql` |
| `TradeOps_Diagrams.drawio` | Editable diagrams: EER Diagram and Relational Model pages |
| `TradeOps_EER.png`, `TradeOps_Relational.png` | Exported diagrams |
| `generate_data.py` | Generates the CSVs in `data/` (and a DuckDB copy, `tradeops.duckdb`) |
| `data/` | One CSV per table |
| `schema.sql`, `add_foreign_keys_mysql.sql`, `load_mysql.py` | Milestone 1 DuckDB / MySQL versions |
| `Milestone 1/`, `Milestone 2/` | Submitted reports |

## Quick start (PostgreSQL)

Run from the project folder:

```bash
createdb tradeops
psql -d tradeops -f sql/01_schema.sql
psql -d tradeops -f sql/02_load.sql
psql -d tradeops -f sql/03_views.sql
psql -d tradeops -f sql/04_checks.sql
```

Without a local PostgreSQL install, Docker works too:

```bash
docker run -d --name tradeops-pg -e POSTGRES_PASSWORD=pg -e POSTGRES_DB=tradeops -v "$PWD:/work" -w /work postgres:16
docker exec -w /work tradeops-pg psql -U postgres -d tradeops -f sql/01_schema.sql -f sql/02_load.sql -f sql/03_views.sql -f sql/04_checks.sql
```

To regenerate the CSVs:

```bash
uv venv --python 3.12
uv pip install duckdb
.venv/Scripts/python generate_data.py      # Windows; use .venv/bin/python on macOS/Linux
```

## Author

Jesus D. Jimenez Ballestas
