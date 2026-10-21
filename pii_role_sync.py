"""
pii_role_sync.py: map the UC account group `pii` to the Postgres role `fraud_pii`.

For every member of `pii` (nested groups expanded), it computes:
  * whether a Postgres LOGIN role with that identity exists in fe_bar_db
  * whether that role is a member of fraud_pii
and builds a plan of actions:
  * none                    : role exists and is already a member of fraud_pii
  * grant_fraud_pii         : role exists, missing membership -> GRANT fraud_pii TO "<role>"
  * create_role_and_grant   : no Postgres role yet -> databricks_create_role(...) then GRANT

Modes
  dry_run (default) : print the plan only, change nothing.
  apply             : execute the plan, but only for identities passed in `apply_only`.
                      With apply_only=None it applies to everyone. That is the intended
                      production path, run as a scheduled job.

This build applies it only for alex.owen@databricks.com. It does not create Postgres
roles for anyone else. Revocation (members removed from `pii`) is reported as
`revoke_fraud_pii` but never executed in this version.
"""

import psycopg
import psycopg.sql as psql
from databricks.sdk import WorkspaceClient

ENDPOINT = "projects/fe-bar-fraud-analytics/branches/production/endpoints/primary"
DBNAME = "fe_bar_db"
UC_GROUP = "pii"
PG_ROLE = "fraud_pii"
# Roles that are members of fraud_pii by design, not by mirroring the UC group.
STRUCTURAL_MEMBERS = {"fraud_lead", "fraud_triage_agent"}


def _connect(w):
    ep = w.postgres.get_endpoint(name=ENDPOINT)
    tok = w.postgres.generate_database_credential(endpoint=ep.name).token
    conn = psycopg.connect(host=ep.status.hosts.host, dbname=DBNAME,
                           user=w.current_user.me().user_name, password=tok, sslmode="require")
    conn.autocommit = True
    return conn


def uc_group_members(w, group_name=UC_GROUP, _seen=None):
    """Return [{identity, kind}] for all users / service principals in the group, recursively."""
    _seen = _seen or set()
    groups = list(w.groups.list(filter=f'displayName eq "{group_name}"'))
    if not groups:
        raise ValueError(f"UC group '{group_name}' not found")
    out = []
    for m in (w.groups.get(groups[0].id).members or []):
        ref = (m.ref or "")
        if ref.startswith("Users/"):
            out.append({"identity": w.users.get(m.value).user_name, "kind": "USER"})
        elif ref.startswith("ServicePrincipals/"):
            out.append({"identity": w.service_principals.get(m.value).application_id, "kind": "SERVICE_PRINCIPAL"})
        elif ref.startswith("Groups/") and m.display not in _seen:
            _seen.add(m.display)
            out.extend(uc_group_members(w, m.display, _seen))
    uniq = {o["identity"]: o for o in out}
    return list(uniq.values())


def build_plan(w=None):
    w = w or WorkspaceClient()
    members = uc_group_members(w)
    conn = _connect(w)
    cur = conn.cursor()
    plan = []
    for m in members:
        cur.execute("SELECT rolcanlogin FROM pg_roles WHERE rolname = %s", (m["identity"],))
        row = cur.fetchone()
        exists = row is not None
        is_member = False
        if exists:
            cur.execute("SELECT pg_has_role(%s, %s, 'MEMBER')", (m["identity"], PG_ROLE))
            is_member = cur.fetchone()[0]
        action = "none" if (exists and is_member) else ("grant_fraud_pii" if exists else "create_role_and_grant")
        plan.append({**m, "pg_role_exists": exists, "pg_can_login": bool(row and row[0]),
                     "member_of_fraud_pii": is_member, "action": action})
    # Report direct fraud_pii members that are no longer in the UC group.
    cur.execute("""SELECT r.rolname FROM pg_auth_members am JOIN pg_roles r ON r.oid = am.member
                   WHERE am.roleid = (SELECT oid FROM pg_roles WHERE rolname = %s)""", (PG_ROLE,))
    uc_ids = {m["identity"] for m in members}
    for (rol,) in cur.fetchall():
        if rol not in uc_ids and rol not in STRUCTURAL_MEMBERS:
            plan.append({"identity": rol, "kind": "PG_ONLY", "pg_role_exists": True, "pg_can_login": None,
                         "member_of_fraud_pii": True, "action": "revoke_fraud_pii (report only)"})
    conn.close()
    return plan


def apply_plan(plan, apply_only=None, w=None):
    """Execute plan actions. apply_only: optional set of identities allowed to change."""
    w = w or WorkspaceClient()
    conn = _connect(w)
    cur = conn.cursor()
    results = []
    for p in plan:
        if apply_only is not None and p["identity"] not in apply_only:
            results.append({**p, "applied": "skipped (not in apply_only)"})
            continue
        if p["action"] == "none" or p["action"].startswith("revoke"):
            results.append({**p, "applied": "no-op"})
            continue
        if p["action"] == "create_role_and_grant":
            cur.execute("CREATE EXTENSION IF NOT EXISTS databricks_auth")
            cur.execute("SELECT databricks_create_role(%s, %s)", (p["identity"], p["kind"]))  # kind: USER or SERVICE_PRINCIPAL
        cur.execute(psql.SQL("GRANT {} TO {}").format(psql.Identifier(PG_ROLE), psql.Identifier(p["identity"])))
        results.append({**p, "applied": "yes"})
    conn.close()
    return results


def print_table(rows, cols=("identity", "kind", "pg_role_exists", "member_of_fraud_pii", "action", "applied")):
    cols = [c for c in cols if any(c in r for r in rows)]
    widths = {c: max(len(c), *(len(str(r.get(c, ""))) for r in rows)) for c in cols}
    print(" | ".join(c.ljust(widths[c]) for c in cols))
    print("-+-".join("-" * widths[c] for c in cols))
    for r in rows:
        print(" | ".join(str(r.get(c, "")).ljust(widths[c]) for c in cols))


if __name__ == "__main__":
    import argparse
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true")
    ap.add_argument("--only", nargs="*", default=None)
    a = ap.parse_args()
    plan = build_plan()
    print("DRY RUN plan:" if not a.apply else "Plan:")
    print_table(plan)
    if a.apply:
        print_table(apply_plan(plan, set(a.only) if a.only is not None else None))
