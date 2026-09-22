"""
Load the TradeOps CSVs (./data) into MySQL tables already created by schema.sql.

Usage (from the project folder):
    uv pip install mysql-connector-python
    .venv\\Scripts\\python.exe load_mysql.py

Rerunnable: it clears the tables first (children before parents), then loads
parents before children so every foreign key resolves.
"""
import csv, os, getpass
import mysql.connector

HERE = os.path.dirname(os.path.abspath(__file__))
DATA = os.path.join(HERE, "data")
ORDER = ["PropFirm", "AccountPlan", "Exchange", "Product", "Instrument", "Strategy",
         "StrategyApproval", "TradingSession", "EconomicEvent", "Account", "AccountCharge",
         "Trade", "Fill", "DailyAccountBalance", "RuleViolation", "Payout"]

def clean(v):
    if v == "":
        return None          # empty CSV cell -> SQL NULL
    if v == "True":
        return 1             # BOOLEAN is TINYINT(1) in MySQL
    if v == "False":
        return 0
    return v

host = input("Host [localhost]: ").strip() or "localhost"
port = int(input("Port [3306]: ").strip() or 3306)
user = input("User [root]: ").strip() or "root"
pwd = getpass.getpass("Password: ")
db = input("Schema/database name where you ran schema.sql: ").strip()

con = mysql.connector.connect(host=host, port=port, user=user, password=pwd, database=db)
cur = con.cursor()

for t in reversed(ORDER):                      # make the script safe to rerun
    cur.execute(f"DELETE FROM `{t}`")
con.commit()

for t in ORDER:
    with open(os.path.join(DATA, f"{t}.csv"), newline="", encoding="utf-8") as f:
        rdr = csv.reader(f)
        cols = next(rdr)
        rows = [tuple(clean(v) for v in r) for r in rdr]
    sql = (f"INSERT INTO `{t}` ({', '.join(f'`{c}`' for c in cols)}) "
           f"VALUES ({', '.join(['%s'] * len(cols))})")
    for i in range(0, len(rows), 1000):          # batches keep packets small
        cur.executemany(sql, rows[i:i + 1000])
    con.commit()
    cur.execute(f"SELECT COUNT(*) FROM `{t}`")
    print(f"{t:22s}{cur.fetchone()[0]:>8,}")

cur.close()
con.close()
print("Done.")
