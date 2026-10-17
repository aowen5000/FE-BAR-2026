# Lakebase Sync Evidence — SNAPSHOT Read Path

**Date:** 2026-10-17  
**Workspace:** fevm-workshop-guy

## Infrastructure

| Component | Value |
| --- | --- |
| Project | `fe-bar-fraud-analytics` |
| Branch | `projects/fe-bar-fraud-analytics/branches/production` |
| Endpoint | `primary` (host: `ep-aged-sky-d2afekn0.database.us-east-1.cloud.databricks.com`) |
| Database | `fe_bar_db` |
| Scale-to-zero | 300s suspend timeout, 1 CU min/max |
| UC Catalog | `fe_bar_lakebase` (MANAGED_ONLINE_CATALOG) |
| Sync Pipeline | `f8690359-4bb1-45b9-8fdb-5bd892239db2` |

## Synced Tables

| Table | Source | Target | PK | Mode | State | Rows |
| --- | --- | --- | --- | --- | --- | --- |
| txn_features | `workshop_guy_catalog.fe_bar_a0.txn_features_gold` | `fe_bar_lakebase.fraud.txn_features` | txn_id | SNAPSHOT | ONLINE | 464,679 |
| customer_risk_profile | `workshop_guy_catalog.fe_bar_a0.customer_risk_profile_gold` | `fe_bar_lakebase.fraud.customer_risk_profile` | customer_id | SNAPSHOT | ONLINE | 9,289 |

## Row Count Validation

Row counts match exactly between UC gold tables and Postgres synced tables.

## Read Latency (200 PK lookups, reused connection)

| Metric | Value |
| --- | --- |
| p50 | 2.42 ms |
| p95 | 5.44 ms |
| p99 | 15.65 ms |

## History

### Failed Triggered Sync Attempt

The first sync attempt used TRIGGERED scheduling_policy. Both synced tables failed with:

```
MATERIALIZED_VIEW_CDF_REQUIRES_EXTERNAL_METADATA
```

This error occurs because TRIGGERED mode reads Change Data Feed (CDF) from the source MV, but MVs require the Beta `pipelines.externalMetadata.enabled` feature for automatic CDF. The pipeline channel was CURRENT, not PREVIEW.

Synced tables created: `workshop_guy_catalog.fe_bar_a0.synced_txn_features` and `synced_customer_risk_profile` (pipeline `692044ca`). Both auto-cleaned up after failures.

### First SNAPSHOT Sync in databricks-postgres

A SNAPSHOT sync was created in the default `databricks-postgres` database (pipeline `4837f221`). The txn_features table reached ONLINE briefly. However, an attempt to create a UC catalog failed, and the synced tables and pipeline were deleted for a clean rebuild in `fe_bar_db`.

### Cleanup of db-8p13-al3theu8go

The `db-8p13-al3theu8go` database resource was a leftover from the first sync attempt. It mapped to a Postgres database named `databricks-postgres` (hyphen) containing only empty `public` and `fe_bar_a0` schemas. It was deleted after confirming no user tables.

### Final SNAPSHOT Sync in fe_bar_db

Two synced tables created in `fe_bar_db` with SNAPSHOT mode, sharing pipeline `f8690359`. Both reached ONLINE. The second table (`customer_risk_profile`) required a manual pipeline trigger after the first update only synced `txn_features`.

### Why SNAPSHOT

The gold materialized views are fully recomputed on each pipeline refresh. A full snapshot copy is therefore equivalent to an incremental sync and avoids the Beta automatic-CDF dependency.
