# Scenario 02 — NetworkPolicy (harder): Egress, DNS & Cross-Namespace

**Domain:** Cluster Hardening (15%) · **Target time:** 12 min

## Task

Namespaces: `shop`, `external`. Create NetworkPolicies in **`shop`** so that:

1. **Default-deny** both **Ingress and Egress** for every pod in `shop`.
2. The `web` pod must still **resolve DNS** (egress to `kube-system` on **UDP+TCP 53**).
3. `web` may egress to `api` pods on **TCP 80** only (plus DNS from step 2).
4. `api` may accept ingress **only from `web`** in `shop`, on **TCP 80**.

Result: `web→api:80` works, DNS works, `scanner` (in `external`) is blocked from `api`.

## Why this one is harder

- **Default-deny egress breaks DNS.** This is the #1 CKS trap. Once you deny all
  egress, pods can't reach CoreDNS, so even `curl api` (by name) fails. You must
  explicitly allow egress to `kube-system` on port 53 (both UDP and TCP).
- You need **both directions**: `web` needs an *egress* allow AND `api` needs an
  *ingress* allow — one without the other still blocks the traffic.
- **Cross-namespace isolation**: the attacker is in a *different* namespace, so a
  plain `podSelector` ingress rule (which is namespace-local) already blocks it —
  understand *why* `scanner` can't match the `from.podSelector`.

## Hints

- Namespaces carry an automatic label `kubernetes.io/metadata.name=<name>` — use it
  in a `namespaceSelector` to target `kube-system` for DNS.
- Multiple entries under `egress:` are OR'd — put the api rule and the DNS rule as
  two items in the same policy, or as two separate policies (both work; policies
  are additive).
- `policyTypes: [Ingress, Egress]` with no `ingress:`/`egress:` blocks = deny both.
- Docs: kubernetes.io → "Network Policies" has an "allow DNS" example.

## Commands

```bash
bash ./setup.sh      # build env + show task
bash ./verify.sh     # grade your solution
bash ./solution.sh   # reveal / apply reference answer
```
