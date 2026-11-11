# Step 12b: EVIDENCE.md split (2026-11-10)

Reason: the AI scorer reads only the first 9,000 characters of each file. After Step 12, EVIDENCE.md was 11,914 characters, so the Databricks App, AI/BI dashboard, High-value triage and Job run blocks were past the cut.

Built in Claude Code, session e8a841d3-121f-4b6f-8b8a-ba79eff53651. Docs only: no SQL, App, notebook, pipeline, Genie space, dashboard, job, model or permission change. No notebook or job run.

## Character counts

| File | Before (main 582d2d9) | After |
|---|---|---|
| README.md | 8,886 | 8,990 |
| EVIDENCE.md | 11,914 | 8,592 |
| EVIDENCE_APP.md | (new) | 3,837 |
| EVIDENCE_INDEX.md | 4,856 (in docs/) | 4,923 |

## Changes

* Moved word for word from EVIDENCE.md to the new top-level EVIDENCE_APP.md: "Databricks App (surface it to the business)", "AI/BI dashboard", "High-value triage (Step 11)", "Job run (Step 10, Part C)".
* EVIDENCE.md: intro now links EVIDENCE_APP.md and EVIDENCE_INDEX.md; one closing line points to EVIDENCE_APP.md.
* docs/EVIDENCE_INDEX.md moved to the top level as EVIDENCE_INDEX.md (git mv); one sentence updated to name both evidence files.
* README.md: EVIDENCE_APP.md added as reading-order item 3 (9 items); stage 6 and job run links point to EVIDENCE_APP.md; evidence index link updated; reasons for items 8 and 9 shortened to stay under 9,000.
* docs/RESOURCES.md: short reading set lists EVIDENCE_APP.md and EVIDENCE_INDEX.md.
* docs/CONVERSATION_IDS.md: Step 12b row.
* Older logs that mention docs/EVIDENCE_INDEX.md are historical records and were not edited.

## Checks

| # | Check | Result | Value |
|---|---|---|---|
| 1 | README.md <= 9,000 | PASS | 8,990 |
| 2 | EVIDENCE.md <= 9,000 | PASS | 8,592 |
| 3 | EVIDENCE_APP.md <= 9,000 | PASS | 3,837 |
| 4 | Blocks: EVIDENCE.md has Business value, Lakeflow, Unity Catalog, Lakebase, ML and Gen AI, Genie Agent; EVIDENCE_APP.md has Databricks App, AI/BI dashboard, High-value triage, Job run | PASS | 6 + 4 |
| 5 | Moved text identical to the original; "Source:" lines before = after | PASS | 23 = 17 + 6 |
| 6 | Every "Source:" file exists in git ls-files | PASS | 23 checked, 0 missing |
| 7 | Every relative link and anchor in the changed files resolves | PASS | 0 broken |
| 8 | 9 reading-list files total <= 90,000 | PASS | 65,742 |
| 9 | 0 em-dashes and 0 token patterns in changed files | PASS | 0 |
