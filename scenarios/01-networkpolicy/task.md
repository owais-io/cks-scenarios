# Scenario 01 — NetworkPolicy: Default-Deny + Selective Allow

**Domain:** Cluster Hardening (15%) · **Target time:** 8 min

## Task

In namespace `prod`:

1. Apply a **default-deny ingress** policy — by default no pod in `prod` accepts incoming traffic.
2. Allow the `db` pod (`app=db`) to receive ingress on **TCP 80 only from pods labeled `app=api`** in the same namespace.

The `attacker` pod must NOT reach `db`; the `api` pod MUST reach `db:80`. Don't modify the pods.

## Hints

- Empty `podSelector: {}` selects every pod in the namespace.
- `policyTypes: [Ingress]` with no `ingress:` block = deny all ingress.
- The allow policy's `podSelector` = destination (db); `from.podSelector` = source (api).
- NetworkPolicies are **additive** (union of allow rules on top of deny).
- Docs: search "Network Policies" on kubernetes.io — the example YAML is copy-paste ready.

## Commands

```bash
bash ./setup.sh      # build the environment + show the task
# ...solve it...
bash ./verify.sh     # check your solution
bash ./solution.sh   # reveal/apply the reference answer
```
