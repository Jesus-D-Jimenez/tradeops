-- ============================================================
-- TradeOps: add foreign keys
-- ============================================================
USE ie6750;

ALTER TABLE AccountPlan
  ADD CONSTRAINT fk_plan_firm        FOREIGN KEY (FirmID)          REFERENCES PropFirm(FirmID);

ALTER TABLE Product
  ADD CONSTRAINT fk_product_exchange FOREIGN KEY (ExchangeCode)    REFERENCES Exchange(ExchangeCode);

ALTER TABLE Instrument
  ADD CONSTRAINT fk_instr_product    FOREIGN KEY (RootSymbol)      REFERENCES Product(RootSymbol);

ALTER TABLE StrategyApproval
  ADD CONSTRAINT fk_appr_strategy    FOREIGN KEY (StrategyID)      REFERENCES Strategy(StrategyID),
  ADD CONSTRAINT fk_appr_product     FOREIGN KEY (RootSymbol)      REFERENCES Product(RootSymbol);

ALTER TABLE Account
  ADD CONSTRAINT fk_acct_plan        FOREIGN KEY (PlanID)          REFERENCES AccountPlan(PlanID),
  ADD CONSTRAINT fk_acct_parent      FOREIGN KEY (ParentAccountID) REFERENCES Account(AccountID);

ALTER TABLE AccountCharge
  ADD CONSTRAINT fk_charge_acct      FOREIGN KEY (AccountID)       REFERENCES Account(AccountID);

ALTER TABLE Trade
  ADD CONSTRAINT fk_trade_acct       FOREIGN KEY (AccountID)       REFERENCES Account(AccountID),
  ADD CONSTRAINT fk_trade_strategy   FOREIGN KEY (StrategyID)      REFERENCES Strategy(StrategyID),
  ADD CONSTRAINT fk_trade_instr      FOREIGN KEY (Symbol)          REFERENCES Instrument(Symbol),
  ADD CONSTRAINT fk_trade_leader     FOREIGN KEY (LeaderTradeID)   REFERENCES Trade(TradeID);

ALTER TABLE Fill
  ADD CONSTRAINT fk_fill_trade       FOREIGN KEY (TradeID)         REFERENCES Trade(TradeID);

ALTER TABLE DailyAccountBalance
  ADD CONSTRAINT fk_bal_acct         FOREIGN KEY (AccountID)       REFERENCES Account(AccountID);

ALTER TABLE RuleViolation
  ADD CONSTRAINT fk_viol_acct        FOREIGN KEY (AccountID)       REFERENCES Account(AccountID);

ALTER TABLE Payout
  ADD CONSTRAINT fk_payout_acct      FOREIGN KEY (AccountID)       REFERENCES Account(AccountID);

-- Check: should list 16 foreign keys
SELECT TABLE_NAME, CONSTRAINT_NAME, REFERENCED_TABLE_NAME
FROM information_schema.KEY_COLUMN_USAGE
WHERE TABLE_SCHEMA = 'ie6750' AND REFERENCED_TABLE_NAME IS NOT NULL
ORDER BY TABLE_NAME;
