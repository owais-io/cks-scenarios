# Scenario 03 — NetworkPolicy (HARDEST): Combined Selectors, Egress, DNS

**Domain:** Cluster Hardening (15%) · **Target time:** 15 min

## Task

Namespaces: `secure`, `dev`, `monitoring`. Create NetworkPolicies in **`secure`** so that:

1. **Default-deny** both ingress and egress for every pod in `secure`.
2. `payments` accepts ingress on **TCP 80** from **exactly**:
   - (a) pods **in `secure` AND labeled `app=gateway`**, and
   - (b) **any pod in the `monitoring` namespace**.
3. End-to-end: `secure/gateway` must actually reach payments → it also needs
   **egress** to `payments:80` and to **DNS** (`kube-system` :53 UDP+TCP).

### Must be true afterward
| Source | → payments:80 |
|--------|---------------|
| `secure/gateway` | ✅ ALLOWED |
| `monitoring/probe` | ✅ ALLOWED |
| `dev/gateway` (decoy, same label!) | ❌ BLOCKED |
| `secure/worker` (same ns, no label!) | ❌ BLOCKED |
| DNS from `secure/gateway` | ✅ WORKS |

## The trap (this is the whole scenario)

In an ingress `from:` list:

```yaml
from:
  - namespaceSelector: {...}   # item 1
    podSelector: {...}         # still item 1  --> AND (both must match)
  - namespaceSelector: {...}   # item 2        --> OR with item 1
```

- Two selectors **in the same list item** = **AND** (source must match both).
- Two **separate list items** = **OR**.

Requirement **2(a) needs AND** (secure *and* gateway) — one list item with both
selectors. Requirement **2(b) is a separate item** (OR). If you instead write
`namespaceSelector` and `podSelector` as two separate items, you get OR and then:
- `dev/gateway` leaks in (matches the `app=gateway` item regardless of namespace), and
- `secure/worker` leaks in (matches the `secure` namespace item regardless of label).

The two "BLOCKED" rows exist specifically to catch that mistake.

> Note: under your default-deny egress, `secure/worker` can't send anything
> anyway, which would hide a leaky ingress policy. So `verify.sh` briefly adds
> a temporary allow-all-egress policy for `worker` during that one check (and
> removes it afterward). This proves `payments` ingress itself rejects it.

## Also know for the exam (not graded here)

- `ipBlock` with `cidr` + `except` for allowing/denying external CIDR ranges.
- `endPort` for port ranges.
- `namespaceSelector: {}` = all namespaces; `podSelector: {}` within a rule = all pods.
- There is no "deny" rule — you model deny by *omitting* allows under a default-deny.

## Commands

```bash
bash ./setup.sh      # build env + show task
bash ./verify.sh     # grade your solution (7 checks)
bash ./solution.sh   # reveal / apply reference answer
bash ./cleanup.sh    # delete secure/dev/monitoring namespaces
```
