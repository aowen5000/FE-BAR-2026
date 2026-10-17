-- =============================================================================
-- Lakebase Write Path DDL: cases schema
-- Database: fe_bar_db (Lakebase project fe-bar-fraud-analytics)
-- Idempotent: all statements use IF NOT EXISTS
-- =============================================================================

CREATE SCHEMA IF NOT EXISTS cases;

-- ---------------------------------------------------------------------------
-- fraud_cases: one row per fraud investigation case
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS cases.fraud_cases (
    case_id             UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    txn_id              TEXT            NOT NULL,
    status              TEXT            NOT NULL DEFAULT 'open'
                                        CHECK (status IN ('open', 'in_review', 'closed')),
    assigned_queue      TEXT            NOT NULL
                                        CHECK (assigned_queue IN ('auto_block', 'analyst_review', 'auto_approve')),
    recommended_action  TEXT            NOT NULL
                                        CHECK (recommended_action IN ('approve', 'review', 'block')),
    notes               TEXT,
    created_by          TEXT            NOT NULL,
    created_at          TIMESTAMPTZ     NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ     NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------------
-- case_actions: audit log of every action taken on a case
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS cases.case_actions (
    action_id           UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    case_id             UUID            NOT NULL
                                        REFERENCES cases.fraud_cases(case_id) ON DELETE CASCADE,
    action_type         TEXT            NOT NULL
                                        CHECK (action_type IN ('case_opened', 'recommendation', 'routed',
                                                               'analyst_decision', 'note', 'case_closed')),
    outcome             TEXT,
    actor               TEXT            NOT NULL,
    created_at          TIMESTAMPTZ     NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------------
-- Indexes
-- ---------------------------------------------------------------------------

-- Lookup cases by transaction
CREATE INDEX IF NOT EXISTS idx_fraud_cases_txn_id
    ON cases.fraud_cases (txn_id);

-- Filter cases by status + time
CREATE INDEX IF NOT EXISTS idx_fraud_cases_status_created
    ON cases.fraud_cases (status, created_at);

-- Audit trail by case + time
CREATE INDEX IF NOT EXISTS idx_case_actions_case_created
    ON cases.case_actions (case_id, created_at);

-- Prevent two open cases for the same transaction
CREATE UNIQUE INDEX IF NOT EXISTS idx_fraud_cases_txn_open
    ON cases.fraud_cases (txn_id)
    WHERE status <> 'closed';
