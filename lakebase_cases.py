"""
lakebase_cases.py — Fraud case management on Lakebase (fe_bar_db).

All operations run against the `cases` schema in the Postgres database `fe_bar_db`
on the Lakebase project fe-bar-fraud-analytics, production branch.

Re-usable by the fraud triage agent and validation notebooks.
"""

import time
import psycopg
from databricks.sdk import WorkspaceClient

_BRANCH = "projects/fe-bar-fraud-analytics/branches/production"
_ENDPOINT_NAME = f"{_BRANCH}/endpoints/primary"
_DBNAME = "fe_bar_db"
_TOKEN_LIFETIME_S = 3500  # refresh before the 1-hour expiry


class LakebaseCases:
    """Manages fraud cases and actions in Lakebase Postgres."""

    def __init__(self):
        self._w = WorkspaceClient()
        self._ep = self._w.postgres.get_endpoint(name=_ENDPOINT_NAME)
        self._host = self._ep.status.hosts.host
        self._username = self._w.current_user.me().user_name
        self._token = None
        self._token_time = 0
        self._conn = None

    # ------------------------------------------------------------------
    # Connection management
    # ------------------------------------------------------------------

    def _refresh_token_if_needed(self):
        if self._token is None or (time.time() - self._token_time) > _TOKEN_LIFETIME_S:
            self._token = self._w.postgres.generate_database_credential(
                endpoint=self._ep.name
            ).token
            self._token_time = time.time()

    def _get_conn(self):
        """Return a live connection, reconnecting on staleness or scale-to-zero wake."""
        for attempt in range(2):
            try:
                self._refresh_token_if_needed()
                if self._conn is None or self._conn.closed:
                    self._conn = psycopg.connect(
                        host=self._host,
                        dbname=_DBNAME,
                        user=self._username,
                        password=self._token,
                        sslmode="require",
                    )
                # Quick liveness check
                with self._conn.cursor() as cur:
                    cur.execute("SELECT 1")
                return self._conn
            except (psycopg.OperationalError, psycopg.InterfaceError):
                self._conn = None
                self._token = None  # force token refresh on retry
                if attempt == 1:
                    raise
                time.sleep(2)

    def close(self):
        if self._conn and not self._conn.closed:
            self._conn.close()

    # ------------------------------------------------------------------
    # Write operations
    # ------------------------------------------------------------------

    def create_fraud_case(
        self,
        txn_id: str,
        recommended_action: str,
        assigned_queue: str,
        notes: str | None,
        created_by: str,
    ) -> str:
        """Create a fraud case. Returns existing case_id if an open case exists."""
        conn = self._get_conn()
        with conn.cursor() as cur:
            # Check txn_id exists in synced fraud.txn_features
            cur.execute(
                "SELECT 1 FROM fraud.txn_features WHERE txn_id = %s LIMIT 1",
                (txn_id,),
            )
            if cur.fetchone() is None:
                raise ValueError(
                    f"txn_id '{txn_id}' not found in fraud.txn_features"
                )

            # Check for existing open case
            cur.execute(
                "SELECT case_id FROM cases.fraud_cases WHERE txn_id = %s AND status <> 'closed'",
                (txn_id,),
            )
            row = cur.fetchone()
            if row is not None:
                conn.commit()
                return str(row[0])

            # Insert case + opening action in one transaction
            cur.execute(
                """
                INSERT INTO cases.fraud_cases
                    (txn_id, recommended_action, assigned_queue, notes, created_by)
                VALUES (%s, %s, %s, %s, %s)
                RETURNING case_id
                """,
                (txn_id, recommended_action, assigned_queue, notes, created_by),
            )
            case_id = str(cur.fetchone()[0])

            cur.execute(
                """
                INSERT INTO cases.case_actions
                    (case_id, action_type, outcome, actor)
                VALUES (%s, 'case_opened', %s, %s)
                """,
                (case_id, f"Recommended: {recommended_action}, Queue: {assigned_queue}", created_by),
            )
            conn.commit()
            return case_id

    def add_case_action(
        self,
        case_id: str,
        action_type: str,
        outcome: str | None,
        actor: str,
    ) -> str:
        """Add an action to a case and update its updated_at. Returns action_id."""
        conn = self._get_conn()
        with conn.cursor() as cur:
            cur.execute(
                """
                INSERT INTO cases.case_actions (case_id, action_type, outcome, actor)
                VALUES (%s, %s, %s, %s)
                RETURNING action_id
                """,
                (case_id, action_type, outcome, actor),
            )
            action_id = str(cur.fetchone()[0])
            cur.execute(
                "UPDATE cases.fraud_cases SET updated_at = now() WHERE case_id = %s",
                (case_id,),
            )
            conn.commit()
            return action_id

    def update_case_status(self, case_id: str, status: str, actor: str) -> None:
        """Update a case's status and log the matching action."""
        action_type = "case_closed" if status == "closed" else "analyst_decision"
        conn = self._get_conn()
        with conn.cursor() as cur:
            cur.execute(
                "UPDATE cases.fraud_cases SET status = %s, updated_at = now() WHERE case_id = %s",
                (status, case_id),
            )
            cur.execute(
                """
                INSERT INTO cases.case_actions (case_id, action_type, outcome, actor)
                VALUES (%s, %s, %s, %s)
                """,
                (case_id, action_type, f"Status changed to {status}", actor),
            )
            conn.commit()

    # ------------------------------------------------------------------
    # Read operations
    # ------------------------------------------------------------------

    def get_case(self, case_id: str) -> dict | None:
        """Return a case with its actions, or None."""
        conn = self._get_conn()
        with conn.cursor() as cur:
            cur.execute(
                """
                SELECT case_id, txn_id, status, assigned_queue,
                       recommended_action, notes, created_by, created_at, updated_at
                FROM cases.fraud_cases WHERE case_id = %s
                """,
                (case_id,),
            )
            row = cur.fetchone()
            if row is None:
                return None
            case = {
                "case_id": str(row[0]),
                "txn_id": row[1],
                "status": row[2],
                "assigned_queue": row[3],
                "recommended_action": row[4],
                "notes": row[5],
                "created_by": row[6],
                "created_at": str(row[7]),
                "updated_at": str(row[8]),
            }
            cur.execute(
                """
                SELECT action_id, action_type, outcome, actor, created_at
                FROM cases.case_actions
                WHERE case_id = %s ORDER BY created_at
                """,
                (case_id,),
            )
            case["actions"] = [
                {
                    "action_id": str(r[0]),
                    "action_type": r[1],
                    "outcome": r[2],
                    "actor": r[3],
                    "created_at": str(r[4]),
                }
                for r in cur.fetchall()
            ]
            return case

    def get_cases_for_txn(self, txn_id: str) -> list[dict]:
        """Return all cases (with actions) for a transaction."""
        conn = self._get_conn()
        with conn.cursor() as cur:
            cur.execute(
                "SELECT case_id FROM cases.fraud_cases WHERE txn_id = %s ORDER BY created_at",
                (txn_id,),
            )
            case_ids = [str(r[0]) for r in cur.fetchall()]
        return [self.get_case(cid) for cid in case_ids]
