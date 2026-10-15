#!/usr/bin/env bash
# CKS Scenario 03 — NetworkPolicy (HARDEST): combined selectors, egress, DNS, 3 namespaces
# Domain: Cluster Hardening (15%)
#
# This is the one that actually looks like the exam. The crux is the
# namespaceSelector + podSelector "AND vs OR" trap. Get that wrong and a decoy
# pod sneaks through.

set -euo pipefail

echo "=== Setting up CKS Scenario 03: NetworkPolicy (HARDEST) ==="

kubectl delete namespace secure dev monitoring --ignore-not-found --wait=true >/dev/null 2>&1 || true

kubectl create namespace secure     >/dev/null
kubectl create namespace dev        >/dev/null
kubectl create namespace monitoring >/dev/null

# --- secure namespace (the production-like, locked-down zone) ----------------
# payments: the sensitive service (nginx :80) + a Service so DNS resolves.
kubectl -n secure run payments --image=nginx:alpine --labels="app=payments" --port=80 >/dev/null
kubectl -n secure expose pod payments --name=payments --port=80 >/dev/null

# gateway (secure): the ONLY in-namespace pod allowed to call payments.
kubectl -n secure run gateway --image=nicolaka/netshoot --labels="app=gateway" --command -- sleep 1d >/dev/null

# worker (secure): another pod in the SAME namespace that must NOT reach payments.
kubectl -n secure run worker --image=nicolaka/netshoot --labels="app=worker" --command -- sleep 1d >/dev/null

# --- dev namespace -----------------------------------------------------------
# gateway (dev): a DECOY. Same label app=gateway, but WRONG namespace.
# It must stay BLOCKED. This is what breaks naive (OR) policies.
kubectl -n dev run gateway --image=nicolaka/netshoot --labels="app=gateway" --command -- sleep 1d >/dev/null

# --- monitoring namespace ----------------------------------------------------
# probe: scraper that must be ALLOWED to reach payments (any pod in monitoring).
kubectl -n monitoring run probe --image=nicolaka/netshoot --labels="app=probe" --command -- sleep 1d >/dev/null

echo "Waiting for pods to become Ready (~30-60s)..."
for ns in secure dev monitoring; do
  kubectl -n "$ns" wait --for=condition=Ready pod --all --timeout=120s >/dev/null
done

echo
for ns in secure dev monitoring; do
  echo "## namespace: $ns"
  kubectl -n "$ns" get pods -o wide --show-labels
  echo
done

cat <<'TASK'
======================================================================
                              YOUR TASK
======================================================================
Namespaces: secure, dev, monitoring

Create NetworkPolicies in the 'secure' namespace so that:

1. DEFAULT-DENY: every pod in 'secure' denies BOTH ingress and egress
   by default.

2. The 'payments' pod accepts ingress on TCP 80 from EXACTLY these two
   sources, and no others:
     (a) pods that are BOTH in namespace 'secure' AND labeled app=gateway
     (b) ANY pod in the 'monitoring' namespace

3. Keep it working end-to-end: the 'secure/gateway' pod must actually be
   able to reach payments, which means it also needs EGRESS allowed to
   payments:80 and to DNS (kube-system :53 UDP+TCP).

MUST hold true after your policies (this is what verify.sh checks):
  - secure/gateway     -> payments:80   ALLOWED
  - monitoring/probe   -> payments:80   ALLOWED
  - dev/gateway        -> payments:80   BLOCKED   (same label, wrong ns!)
  - secure/worker      -> payments:80   BLOCKED   (same ns, wrong label!)
  - secure/gateway DNS resolution WORKS
  - default-deny ingress AND egress policies exist

THE TRAP: in an ingress 'from:' list, two list items are OR'd, but
namespaceSelector + podSelector INSIDE ONE list item are AND'd. Requirement
2(a) needs them AND'd (one item); 2(b) is a second item. Mix this up and
either dev/gateway OR worker will leak through.

Hints: cat ./task.md      Reveal: cat ./solution.sh
Verify: bash ./verify.sh   Clean: bash ./cleanup.sh
======================================================================
TASK
