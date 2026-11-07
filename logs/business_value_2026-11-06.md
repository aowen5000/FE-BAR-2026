### B.2 Model vs baseline rule, governed view (excludes amount > 10000), 463,881 txns

| Metric | Baseline rule (cross_border AND new_device) | Model (block + review) | Difference |
|---|---|---|---|
| Transactions flagged | 33,723 | 24,201 | -9,522 |
| Fraud transactions caught | 2,767 | 6,571 | +3,804 |
| Fraud $ caught | $933,889.13 | $7,010,482.03 | $6,076,592.90 |
| Fraud $ missed | $7,052,318.79 | $975,725.89 | -$6,076,592.90 |
| False positives (count) | 30,956 | 17,630 | -13,326 |
| False positive rate (FP / legitimate txns) | 6.83% | 3.89% | -2.94 pts |
| Precision of flags (fraud / flagged) | 8.21% | 27.15% | +18.95 pts |

### B.3a Analyst hours per month, governed view (assumption: 15 to 20 min manual, 2 to 3 min with agent)

| Queue | Cases per month (measured / 5.90 months) | Minutes per case | Analyst hours per month |
|---|---|---|---|
| Baseline rule queue, manual review | 5,713 | 15 to 20 (assumption) | 1,428 to 1,904 |
| Model queue (block + review), manual review | 4,100 | 15 to 20 (assumption) | 1,025 to 1,367 |
| Model queue (block + review), with agent | 4,100 | 2 to 3 (assumption) | 137 to 205 |

### B.3b Measured agent end-to-end latency vs assumption

| Measure | Runs | Median | Range | Assumption it sits next to |
|---|---|---|---|---|
| Agent run, end to end (explain, act, guardrail) | 9 | 19.9 s | 16.0 to 51.1 s | 2 to 3 min per case (assumption includes analyst reading time) |

### B.4 Illustrative issuer at 10,000,000 card txns/month (scale factor 127.0x, full synthetic set)

| Row | Synthetic set per month (measured) | Illustrative issuer per month (scaled) | Assumption on this row |
|---|---|---|---|
| Card transactions per month | 78,711 | 10,000,000 | Assumption: example volume |
| Model flags per month | 4,219 | 536,037 | Assumption: same flag rate as synthetic set |
| Baseline rule flags per month | 5,721 | 726,833 | Assumption: same flag rate as synthetic set |
| Fraud $ caught per month, model | $1,795,566.52 | $228,120,640.64 | Assumption: same fraud rate and amount mix |
| Fraud $ caught per month, baseline rule | $188,839.86 | $23,991,464.21 | Assumption: same fraud rate and amount mix |
| Fraud $ missed per month, model | $181,520.53 | $23,061,567.86 | Assumption: same fraud rate and amount mix |
| False positives per month, model | 3,072 | 390,309 | Assumption: same legitimate mix |
| False positives per month, baseline rule | 5,250 | 667,044 | Assumption: same legitimate mix |
| Analyst hours per month, rule queue, manual | 1,430 to 1,907 | 181,708 to 242,278 | Assumption: 15 to 20 min per case |
| Analyst hours per month, model queue, with agent | 141 to 211 | 17,868 to 26,802 | Assumption: 2 to 3 min per case |

### B.4b-1 High-value slice: amount > 10000, model flags (block or review), full synthetic set

| Measure | Value (scope: amount > 10000, full synthetic set) |
|---|---|
| Transactions with amount > 10000 | 751 |
| Flagged by model (block or review) | 705 |
| Fraud among flagged | 200 |
| Fraud $ among flagged | $3,588,732.92 |
| False positives among flagged | 505 |
| Visible in Genie / dashboard / App (fraud_dash views) | 0 (views filter amount > 10000 for everyone) |

### B.4b-2 High-value slice by band (scope: amount > 10000)

| band | txns | fraud | fraud_usd | legit |
|---|---|---|---|---|
| approve | 46 | 4 | 95788.35 | 42 |
| block | 71 | 21 | 394748.59 | 50 |
| review | 634 | 179 | 3193984.33 | 455 |

### B.4b-3 Headline KPIs in two scopes

| Headline KPI | governed view (excludes amount > 10000), 463,881 txns | full synthetic set, 464,632 txns |
|---|---|---|
| Fraud $ caught, model | $7,010,482.03 | $10,599,214.95 |
| Fraud $ caught, baseline rule | $933,889.13 | $1,114,720.20 |
| Fraud $ missed, model | $975,725.89 | $1,071,514.24 |
| False positives, model | 17,630 | 18,135 |
| False positives, baseline rule | 30,956 | 30,993 |
| False positive rate, model | 3.89% | 3.99% |
| False positive rate, baseline rule | 6.83% | 6.83% |

### B.5 Final KPI table

| KPI | Baseline | With the build | Scope | Source cell or assumption |
|---|---|---|---|---|
| Time to flag and explain a risky transaction | Hours (assumption: manual queue, original plan) | Scored in batch; agent explains in 19.9 s median (16.0 to 51.1 s, 9 runs) | Agent traces | B.3b, measured |
| Analyst time per case | 15 to 20 min (assumption) | 2 to 3 min (assumption) | Per case | Original plan assumption |
| Analyst hours per month | 1,428 to 1,904 (rule queue, manual) | 137 to 205 (model queue, with agent) | Governed view | B.3a, measured volume x assumed minutes |
| False positive rate | 6.83% | 3.89% | Governed view | B.2, measured |
| False positives (count) | 30,956 | 17,630 | Governed view | B.2, measured |
| Fraud $ caught (flagged before approval) | $933,889.13 | $7,010,482.03 | Governed view | B.2, measured |
| Fraud $ caught (flagged before approval) | $1,114,720.20 | $10,599,214.95 | Full synthetic set | B.4b-3, measured |
| Fraud $ missed | $7,052,318.79 | $975,725.89 | Governed view | B.2, measured |
| Fraud $ missed | $10,556,008.99 | $1,071,514.24 | Full synthetic set | B.4b-3, measured |
| High-value flagged txns not triageable in Genie / dashboard / App | n/a | 705 txns, 200 fraud, $3,588,732.92 | amount > 10000 | B.4b-1, measured (open gap) |
