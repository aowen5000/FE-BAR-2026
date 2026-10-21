# Agent Case Round-Trip Log — 2026-10-21

## Case for TXN-0234209
**case_id:** 2319d4b7-bea3-412b-ba6b-8325e1a7a71d

## Case Row (via LakebaseCases as fraud_lead)
```json
{
  "case_id": "2319d4b7-bea3-412b-ba6b-8325e1a7a71d",
  "txn_id": "TXN-0234209",
  "status": "open",
  "assigned_queue": "auto_block",
  "recommended_action": "block",
  "notes": "Model action: block (risk 0.9844, HIGH confidence, routed to auto_block). Top signals: new device never seen before (SHAP +2.57), 450.6 km from home region US-East (+1.87), online txn (+1.20). Customer CUST-08669 has 3 prior confirmed fraud cases, 0 not-fraud; amount $323.96 vs 30d avg $100.44. No override.",
  "created_by": "fraud_triage_copilot:agent",
  "created_at": "2026-10-21 00:02:21.031588+00:00",
  "updated_at": "2026-10-21 00:02:21.031588+00:00",
  "actions": [
    {
      "action_id": "7482db53-9fa3-4f66-9cf7-f803a676d37b",
      "action_type": "case_opened",
      "outcome": "Recommended: block, Queue: auto_block",
      "actor": "fraud_triage_copilot:agent",
      "created_at": "2026-10-21 00:02:21.031588+00:00"
    }
  ]
}
```

## Via UC (fe_bar_lakebase.cases.fraud_cases)
**Result: 0 rows** — FORCE ROW LEVEL SECURITY is active and the UC query Postgres role is not
in any RLS policy. This is expected behavior: the case tables are governed by RLS and
only direct Postgres connections with SET ROLE can read them.

## Idempotency Result
- Second call to open a case for TXN-0234209 returned the same case_id: 2319d4b7
- Only 1 open case exists for TXN-0234209 after two "open case" requests
- The partial unique index (status != 'closed') prevents duplicate open cases

## E.7 FGAC Through the Agent
- fraud_lead can see the case via LakebaseCases(pg_role='fraud_lead'): YES
- fraud_analyst can see the case if it is in analyst_review and amount <= 10000:
  - TXN-0234209 is in auto_block (not analyst_review), so fraud_analyst cannot see it
  - Cases in analyst_review with amount <= 10000 are visible to fraud_analyst
