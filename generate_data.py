"""
IE6750 Milestone 1 
Prop-Firm Futures Trading Operations (operational database)
"""
import csv, os, random, math
from datetime import date, datetime, time, timedelta
from decimal import Decimal, ROUND_HALF_UP

random.seed(6750)
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "data")
os.makedirs(OUT, exist_ok=True)
START, END = date(2025, 1, 2), date(2026, 8, 31)

def money(x):
    return float(Decimal(str(x)).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP))

def bdays(a, b):
    d = a
    while d <= b:
        if d.weekday() < 5:
            yield d
        d += timedelta(days=1)

def add_bdays(d, n):
    while n > 0:
        d += timedelta(days=1)
        if d.weekday() < 5:
            n -= 1
    return d

# ------------------------------------------------------------------
# STATIC REFERENCE DATA
# ------------------------------------------------------------------
firms = [
    (1, "Topstep",          "topstep.com",          5),
    (2, "Lucid Trading",    "lucidtrading.com",     5),
    (3, "MyFundedFutures",  "myfundedfutures.com",  7),
]
# PlanID, FirmID, Name, Type, Start, Target, MTD, DLL, Consistency%, MinDays, MaxCt, Split%, Fee
plans = [
    (1, 1, "50K Combine",       "Evaluation",  50000, 3000, 2000, 1000, 50, 2, 5,  None,  49),
    (2, 1, "50K Funded",        "Funded",      50000, None, 2000, 1000, None, None, 5, 90.0, 149),
    (3, 1, "150K Combine",      "Evaluation", 150000, 9000, 4500, 3000, 50, 2, 15, None, 149),
    (4, 1, "150K Funded",       "Funded",     150000, None, 4500, 3000, None, None, 15, 90.0, 149),
    (5, 2, "LucidFlex 50K Eval","Evaluation",  50000, 3000, 2000, None, 50, 1, 4,  None,  80),
    (6, 2, "LucidFlex 50K Funded","Funded",    50000, None, 2000, None, 40, None, 4, 90.0,  0),
    (7, 3, "Rapid 50K Eval",    "Evaluation",  50000, 3000, 2000, None, None, 1, 5, None,  77),
    (8, 3, "Rapid 50K Funded",  "Funded",      50000, None, 2000, None, 40, None, 5, 90.0, 129),
]
plan = {p[0]: dict(zip(["PlanID","FirmID","PlanName","PlanType","StartingBalance","ProfitTarget",
        "MaxTrailingDrawdown","DailyLossLimit","ConsistencyRulePct","MinTradingDays",
        "MaxContracts","ProfitSplitPct","PlanFee"], p)) for p in plans}
funded_plan_for = {1: 2, 3: 4, 5: 6, 7: 8}
firm_cycle = {f[0]: f[3] for f in firms}

exchanges = [
    ("CME",   "Chicago Mercantile Exchange", "America/Chicago"),
    ("CBOT",  "Chicago Board of Trade",      "America/Chicago"),
    ("NYMEX", "New York Mercantile Exchange","America/Chicago"),
    ("COMEX", "Commodity Exchange Inc.",     "America/Chicago"),
]
# Root, Name, Exch, AssetClass, TickSize, TickValue, IsMicro
products = [
    ("ES",  "E-mini S&P 500",          "CME",   "Equity Index", 0.25, 12.50, False),
    ("MES", "Micro E-mini S&P 500",    "CME",   "Equity Index", 0.25,  1.25, True),
    ("NQ",  "E-mini Nasdaq-100",       "CME",   "Equity Index", 0.25,  5.00, False),
    ("MNQ", "Micro E-mini Nasdaq-100", "CME",   "Equity Index", 0.25,  0.50, True),
    ("YM",  "E-mini Dow",              "CBOT",  "Equity Index", 1.00,  5.00, False),
    ("MYM", "Micro E-mini Dow",        "CBOT",  "Equity Index", 1.00,  0.50, True),
    ("RTY", "E-mini Russell 2000",     "CME",   "Equity Index", 0.10,  5.00, False),
    ("M2K", "Micro E-mini Russell 2000","CME",  "Equity Index", 0.10,  0.50, True),
    ("CL",  "Crude Oil",               "NYMEX", "Energy",       0.01, 10.00, False),
    ("MCL", "Micro Crude Oil",         "NYMEX", "Energy",       0.01,  1.00, True),
    ("GC",  "Gold",                    "COMEX", "Metals",       0.10, 10.00, False),
    ("MGC", "Micro Gold",              "COMEX", "Metals",       0.10,  1.00, True),
]
prod = {p[0]: dict(zip(["RootSymbol","ProductName","ExchangeCode","AssetClass","TickSize","TickValue","IsMicro"], p)) for p in products}
micro_of = {"ES":"MES","NQ":"MNQ","YM":"MYM","RTY":"M2K","CL":"MCL","GC":"MGC"}

# Instruments: quarterly (H,M,U,Z) for index products, monthly for CL/GC families
MCODE = "FGHJKMNQUVXZ"
def third_friday(y, m):
    d = date(y, m, 15)
    while d.weekday() != 4:
        d += timedelta(days=1)
    return d
instruments = []
for root in prod:
    quarterly = prod[root]["AssetClass"] == "Equity Index"
    for y in (2024, 2025, 2026, 2027):
        for m in range(1, 13):
            if quarterly and m not in (3, 6, 9, 12):
                continue
            if root in ("GC","MGC") and m not in (2, 4, 6, 8, 10, 12):
                continue
            cm = date(y, m, 1)
            if quarterly:
                exp = third_friday(y, m)
            elif root in ("CL","MCL"):           # simplified: ~20th of prior month
                py, pm = (y, m-1) if m > 1 else (y-1, 12)
                exp = date(py, pm, 20)
            else:                                # gold: ~last business day of prior month
                exp = date(y, m, 1) - timedelta(days=3)
            if date(2024, 12, 1) <= exp <= date(2027, 3, 31):
                instruments.append((f"{root}{MCODE[m-1]}{y%10}", root, cm, exp))
inst_by_root = {}
for s, r, cm, exp in instruments:
    inst_by_root.setdefault(r, []).append((exp, s))
for r in inst_by_root:
    inst_by_root[r].sort()
def front_symbol(root, d):
    for exp, s in inst_by_root[root]:
        if exp - timedelta(days=8) > d:          # roll ~8 days before expiry
            return s
    raise ValueError(root, d)

strategies = [
    (1, "Opening Range Breakout", "Breakout",       "5m",  "Trades the break of the first 15-minute range after the NY open."),
    (2, "VWAP Reversion",         "Mean Reversion", "1m",  "Fades stretched moves back toward session VWAP during midday."),
    (3, "Trend Pullback",         "Trend Following","15m", "Enters pullbacks to the 20 EMA in the direction of the daily trend."),
    (4, "London Breakout",        "Breakout",       "5m",  "Trades the London session break of the Asia range in metals and energy."),
    (5, "News Fade",              "Event-Driven",   "1m",  "Fades the first spike after high-impact 8:30 ET releases."),
]
approved_roots = {
    1: ["NQ","ES","YM"], 2: ["ES","RTY"], 3: ["NQ","GC","CL"], 4: ["GC","CL"], 5: ["NQ","ES"],
}
approvals = []
for sid, roots in approved_roots.items():
    for r in roots:
        en = date(2024, 12, 2) + timedelta(days=7*sid)
        approvals.append((sid, r, 3 if r in ("NQ","ES","GC","CL") else 4, en))
        approvals.append((sid, micro_of[r], 15, en))

sessions = [
    (1, "Asia",      time(18, 0), time(2, 0)),
    (2, "London",    time(2, 0),  time(9, 30)),
    (3, "NY Open",   time(9, 30), time(11, 30)),
    (4, "NY Midday", time(11, 30),time(14, 0)),
    (5, "NY Close",  time(14, 0), time(17, 0)),
]

# Economic calendar (rule-based, approximate dates)
events = []
fomc_months = {1, 3, 5, 6, 7, 9, 10, 12}
d = date(2025, 1, 1)
while d <= END:
    if d.weekday() < 5:
        if d.weekday() == 4 and d.day <= 7:
            events.append((d, time(8, 30), "Nonfarm Payrolls", "High"))
        if d.day in (10, 11, 12, 13, 14) and not any(e[2] == "CPI" and e[0].month == d.month and e[0].year == d.year for e in events) and d.weekday() in (1, 2):
            events.append((d, time(8, 30), "CPI", "High"))
        if d.day in (15, 16, 17) and not any(e[2] == "Retail Sales" and e[0].month == d.month and e[0].year == d.year for e in events):
            events.append((d, time(8, 30), "Retail Sales", "Medium"))
        if d.month in fomc_months and d.weekday() == 2 and 15 <= d.day <= 21 and d.month != 2:
            events.append((d, time(14, 0), "FOMC Rate Decision", "High"))
        if d.weekday() == 3:
            events.append((d, time(8, 30), "Initial Jobless Claims", "Low"))
        if d.weekday() == 2:
            events.append((d, time(10, 30), "EIA Crude Inventories", "Medium"))
    d += timedelta(days=1)
events = [(i+1,) + e for i, e in enumerate(sorted(events))]
high_830 = {e[1] for e in events if e[4] == "High" and e[2] == time(8, 30)}

# ------------------------------------------------------------------
# TRANSACTIONAL SIMULATION
# ------------------------------------------------------------------
price = {"ES": 5900.0, "NQ": 21000.0, "YM": 42500.0, "RTY": 2250.0, "CL": 72.0, "GC": 2650.0}
vol   = {"ES": 0.009, "NQ": 0.012, "YM": 0.008, "RTY": 0.013, "CL": 0.02, "GC": 0.009}
drift = {"ES": 0.0004, "NQ": 0.0005, "YM": 0.0003, "RTY": 0.0002, "CL": -0.0002, "GC": 0.0009}
stop_pts = {"ES": 6.0, "NQ": 25.0, "YM": 60.0, "RTY": 6.0, "CL": 0.30, "GC": 6.0}
commission_rt = {False: 4.00, True: 1.00}
platforms = {1: "TopstepX", 2: "Tradovate", 3: "Tradovate"}

accounts, charges, trades, fills, balances, violations, payouts = [], [], [], [], [], [], []
acct_state = {}
next_acct = [1001]; next_charge = [1]; next_trade = [1]; next_viol = [1]; next_payout = [1]
label_seq = {}

def rtick(x, root):
    ts = prod[root]["TickSize"]
    return round(round(x / ts) * ts, 4)

def open_account(plan_id, d, parent=None):
    aid = next_acct[0]; next_acct[0] += 1
    p = plan[plan_id]
    firm_abbr = {1: "TS", 2: "LF", 3: "MFF"}[p["FirmID"]]
    key = (firm_abbr, p["PlanType"])
    label_seq[key] = label_seq.get(key, 0) + 1
    label = f"{firm_abbr}-{int(p['StartingBalance']/1000)}K-{p['PlanType'][0]}-{label_seq[key]:03d}"
    accounts.append(dict(AccountID=aid, PlanID=plan_id, ParentAccountID=parent, AccountLabel=label,
                         Platform=platforms[p["FirmID"]], OpenDate=d, CloseDate=None, Status="Active"))
    acct_state[aid] = dict(plan=p, bal=p["StartingBalance"], hwm=p["StartingBalance"], days=0,
                           daily=[], resets=0, last_payout_day=0, next_monthly=d + timedelta(days=30),
                           consistency_flagged=False, open=d)
    ctype = "Evaluation" if p["PlanType"] == "Evaluation" else "Activation"
    if p["PlanFee"] > 0:
        charges.append((next_charge[0], aid, d, ctype, money(p["PlanFee"]))); next_charge[0] += 1
    return aid

def close_account(aid, d, status):
    for a in accounts:
        if a["AccountID"] == aid:
            a["Status"], a["CloseDate"] = status, d
    acct_state.pop(aid, None)

def add_violation(aid, d, rule, details):
    violations.append((next_viol[0], aid, d, rule, details)); next_viol[0] += 1

def signals_for(d):
    """Leader signals for the day: (strategy, root, entry_dt, direction, entry_px, exit_px, hold_min, won)."""
    sig = []
    cands = [(1, time(9, 46)), (2, time(12, 10)), (3, time(10, 20)), (4, time(3, 15))]
    if d in high_830:
        cands.append((5, time(8, 33)))
    for sid, t in cands:
        if random.random() > (0.55 if sid != 5 else 0.9):
            continue
        root = random.choice(approved_roots[sid])
        base = price[root]
        direction = random.choice(["Long", "Short"])
        sgn = 1 if direction == "Long" else -1
        entry = rtick(base * (1 + random.gauss(0, vol[root] / 3)), root)
        win_p = {1: 0.41, 2: 0.50, 3: 0.37, 4: 0.42, 5: 0.47}[sid]
        rr = {1: 1.8, 2: 1.0, 3: 2.2, 4: 1.6, 5: 1.2}[sid]
        won = random.random() < win_p
        stop = stop_pts[root] * random.uniform(0.8, 1.2)
        move = stop * rr * random.uniform(0.7, 1.1) if won else -stop * random.uniform(0.9, 1.05)
        exitp = rtick(entry + sgn * move, root)
        mins = random.randint(4, 25) if sid in (2, 5) else random.randint(8, 95)
        entry_dt = datetime.combine(d, t) + timedelta(minutes=random.randint(0, 20), seconds=random.randint(0, 59))
        sig.append((sid, root, entry_dt, direction, entry, exitp, mins))
    return sig

def place_trade(aid, st, s, leader_id):
    sid, root, entry_dt, direction, entry, exitp, mins = s
    p = st["plan"]
    use_root = micro_of[root] if p["StartingBalance"] <= 50000 else root
    pr = prod[use_root]
    risk_target = 300 if p["StartingBalance"] <= 50000 else 750
    per_ct = stop_pts[root] / pr["TickSize"] * pr["TickValue"]
    cts = max(1, min(p["MaxContracts"] * (10 if pr["IsMicro"] else 1), round(risk_target / per_ct)))
    slip = pr["TickSize"] * random.choice([-1, 0, 0, 0, 1]) if leader_id else 0.0
    sgn = 1 if direction == "Long" else -1
    e_px = rtick(entry + sgn * abs(slip), root)
    x_px = rtick(exitp - sgn * abs(slip) * random.choice([0, 1]), root)
    e_dt = entry_dt + timedelta(seconds=random.randint(0, 3) if leader_id else 0)
    x_dt = e_dt + timedelta(minutes=mins, seconds=random.randint(0, 59))
    tid = next_trade[0]; next_trade[0] += 1
    comm = money(commission_rt[pr["IsMicro"]] * cts)
    # fills: one entry leg; exit in one leg or scaled out in two
    fills.append((tid, 1, e_dt, "Buy" if sgn == 1 else "Sell", cts, e_px, random.choice(["Market", "Limit"])))
    exit_side = "Sell" if sgn == 1 else "Buy"
    won = (x_px - e_px) * sgn > 0
    if cts >= 2 and won and random.random() < 0.5:
        q1 = cts // 2
        p1 = rtick(e_px + (x_px - e_px) * 0.6, root)
        q2 = cts - q1
        p2 = rtick((x_px * cts - p1 * q1) / q2, root)
        fills.append((tid, 2, e_dt + (x_dt - e_dt) / 2, exit_side, q1, p1, "Limit"))
        fills.append((tid, 3, x_dt, exit_side, q2, p2, "Limit"))
        avg_x = round((p1 * q1 + p2 * q2) / cts, 4)
    else:
        fills.append((tid, 2, x_dt, exit_side, cts, x_px, "Limit" if won else "Stop"))
        avg_x = x_px
    sym = front_symbol(use_root, e_dt.date())
    trades.append((tid, aid, sid, sym, leader_id, direction, cts, e_dt, x_dt, e_px, avg_x, comm))
    gross = (avg_x - e_px) * sgn / pr["TickSize"] * pr["TickValue"] * cts
    return tid, gross - comm

target_active_evals = 6
for d in bdays(START, END):
    # daily price move
    for r in price:
        price[r] *= math.exp(drift[r] + random.gauss(0, vol[r]))

    # buy new evaluations to keep the pipeline full (max one per day)
    n_eval = sum(1 for a, st in acct_state.items() if st["plan"]["PlanType"] == "Evaluation")
    if n_eval < target_active_evals and random.random() < 0.6:
        open_account(random.choices([1, 3, 5, 7], weights=[3, 1, 3, 3])[0], d)

    # monthly subscription charges on evaluations
    for aid, st in acct_state.items():
        if st["plan"]["PlanType"] == "Evaluation" and d >= st["next_monthly"]:
            charges.append((next_charge[0], aid, d, "Monthly", money(st["plan"]["PlanFee"]))); next_charge[0] += 1
            st["next_monthly"] += timedelta(days=30)

    # trading: first active account (oldest) leads, the rest copy
    active = sorted(a for a, st in acct_state.items() if st["open"] < d or st["open"] == d)
    day_pnl = {a: 0.0 for a in active}
    traded = set()
    for s in signals_for(d):
        leader_id = None
        for aid in active:
            if random.random() < 0.08:            # copier skipped / account paused
                continue
            tid, net = place_trade(aid, acct_state[aid], s, leader_id)
            if leader_id is None:
                leader_id = tid
            day_pnl[aid] += net
            traded.add(aid)

    # end-of-day statements and rule checks
    for aid in active:
        st = acct_state[aid]; p = st["plan"]
        start_bal = st["bal"]
        st["bal"] = money(st["bal"] + day_pnl[aid])
        if aid in traded:
            st["days"] += 1
            st["daily"].append(day_pnl[aid])
        st["hwm"] = max(st["hwm"], st["bal"])
        floor = min(st["hwm"] - p["MaxTrailingDrawdown"], p["StartingBalance"]) \
            if p["PlanType"] == "Funded" else st["hwm"] - p["MaxTrailingDrawdown"]
        balances.append((aid, d, money(start_bal), st["bal"], money(st["hwm"]), money(floor)))

        if p["DailyLossLimit"] and day_pnl[aid] <= -p["DailyLossLimit"]:
            add_violation(aid, d, "DailyLossLimit", f"Day P&L {day_pnl[aid]:.2f} exceeded limit {p['DailyLossLimit']}")

        if st["bal"] <= floor:
            add_violation(aid, d, "TrailingDrawdown", f"Balance {st['bal']:.2f} hit floor {floor:.2f}")
            if p["PlanType"] == "Evaluation" and st["resets"] < 2 and random.random() < 0.35:
                st["resets"] += 1
                charges.append((next_charge[0], aid, d, "Reset", money(p["PlanFee"] * 0.8))); next_charge[0] += 1
                st.update(bal=p["StartingBalance"], hwm=p["StartingBalance"], days=0, daily=[], consistency_flagged=False)
            else:
                close_account(aid, d, "Failed" if p["PlanType"] == "Evaluation" else "Breached")
            continue

        profit = st["bal"] - p["StartingBalance"]
        if p["PlanType"] == "Evaluation" and profit >= p["ProfitTarget"] and st["days"] >= (p["MinTradingDays"] or 0):
            best = max(st["daily"]) if st["daily"] else 0
            if p["ConsistencyRulePct"] and best > profit * p["ConsistencyRulePct"] / 100:
                if not st["consistency_flagged"]:
                    add_violation(aid, d, "Consistency", f"Best day {best:.2f} > {p['ConsistencyRulePct']}% of profit {profit:.2f}")
                    st["consistency_flagged"] = True
                continue
            close_account(aid, d, "Passed")
            open_account(funded_plan_for[p["PlanID"]], add_bdays(d, 1), parent=aid)
            continue

        if p["PlanType"] == "Funded" and st["days"] - st["last_payout_day"] >= firm_cycle[p["FirmID"]] and profit >= 1000:
            gross = money(math.floor(profit * 0.5 / 100) * 100)
            status = "Denied" if random.random() < 0.06 else "Paid"
            paid = add_bdays(d, random.randint(1, 3)) if status == "Paid" else None
            payouts.append((next_payout[0], aid, d, gross, money(gross * p["ProfitSplitPct"] / 100), status, paid))
            next_payout[0] += 1
            st["last_payout_day"] = st["days"]
            if status == "Paid":
                st["bal"] = money(st["bal"] - gross)

# ------------------------------------------------------------------
# WRITE CSVs
# ------------------------------------------------------------------
def write(name, header, rows):
    with open(os.path.join(OUT, f"{name}.csv"), "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(header)
        for r in rows:
            w.writerow(["" if v is None else v for v in r])
    return len(rows)

counts = {}
counts["PropFirm"] = write("PropFirm", ["FirmID","FirmName","Website","PayoutCycleDays"], firms)
counts["AccountPlan"] = write("AccountPlan", list(plan[1].keys()), [list(p.values()) for p in plan.values()])
counts["Exchange"] = write("Exchange", ["ExchangeCode","ExchangeName","TimeZone"], exchanges)
counts["Product"] = write("Product", list(prod["ES"].keys()), [list(p.values()) for p in prod.values()])
counts["Instrument"] = write("Instrument", ["Symbol","RootSymbol","ContractMonth","ExpirationDate"], instruments)
counts["Strategy"] = write("Strategy", ["StrategyID","StrategyName","Style","Timeframe","Description"], strategies)
counts["StrategyApproval"] = write("StrategyApproval", ["StrategyID","RootSymbol","MaxContracts","EnabledDate"], approvals)
counts["TradingSession"] = write("TradingSession", ["SessionID","SessionName","StartTimeET","EndTimeET"], sessions)
counts["EconomicEvent"] = write("EconomicEvent", ["EventID","EventDate","EventTimeET","EventName","Impact"], events)
counts["Account"] = write("Account", list(accounts[0].keys()), [list(a.values()) for a in accounts])
counts["AccountCharge"] = write("AccountCharge", ["ChargeID","AccountID","ChargeDate","ChargeType","Amount"], charges)
counts["Trade"] = write("Trade", ["TradeID","AccountID","StrategyID","Symbol","LeaderTradeID","Direction","Contracts",
                                  "EntryTime","ExitTime","AvgEntryPrice","AvgExitPrice","Commission"], trades)
counts["Fill"] = write("Fill", ["TradeID","LegNo","FillTime","Side","Quantity","Price","OrderType"], fills)
counts["DailyAccountBalance"] = write("DailyAccountBalance", ["AccountID","TradeDate","StartBalance","EndBalance",
                                      "HighWaterMark","DrawdownFloor"], balances)
counts["RuleViolation"] = write("RuleViolation", ["ViolationID","AccountID","ViolationDate","RuleType","Details"], violations)
counts["Payout"] = write("Payout", ["PayoutID","AccountID","RequestDate","GrossAmount","TraderShare","Status","PaidDate"], payouts)

# ------------------------------------------------------------------
# LOAD INTO DUCKDB
# ------------------------------------------------------------------
if __name__ == "__main__":
    import duckdb
    db = os.path.join(os.path.dirname(OUT), "tradeops.duckdb")
    if os.path.exists(db):
        os.remove(db)
    con = duckdb.connect(db)
    con.execute(open(os.path.join(os.path.dirname(OUT), "schema.sql")).read())
    order = ["PropFirm","AccountPlan","Exchange","Product","Instrument","Strategy","StrategyApproval",
             "TradingSession","EconomicEvent","Account","AccountCharge","Trade","Fill",
             "DailyAccountBalance","RuleViolation","Payout"]
    selfref = {"Account": "ParentAccountID", "Trade": "LeaderTradeID"}
    for t in order:
        src = f"read_csv_auto('{OUT}/{t}.csv', header=true, nullstr='')"
        if t in selfref:   # load parents (NULL self-reference) before children
            c = selfref[t]
            con.execute(f"INSERT INTO {t} SELECT * FROM {src} WHERE {c} IS NULL")
            con.execute(f"INSERT INTO {t} SELECT * FROM {src} WHERE {c} IS NOT NULL")
        else:
            con.execute(f"INSERT INTO {t} SELECT * FROM {src}")
    for t in order:
        print(f"{t:22s}{con.execute(f'SELECT COUNT(*) FROM {t}').fetchone()[0]:>8,}")
    con.close()
