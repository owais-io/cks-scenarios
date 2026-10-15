#!/usr/bin/env bash
# CKS Scenario 02 — NetworkPolicy (harder): default-deny egress, DNS, cross-namespace
# Domain: Cluster Hardening (15%)
#
# Harder than 01: you must lock down BOTH ingress and egress, keep DNS working
# (the classic trap), AND block a pod in a DIFFERENT namespace.

set -euo pipefail

echo "=== Setting up CKS Scenario 02: NetworkPolicy (harder) ==="

# Clean slate if re-running
kubectl delete namespace shop external --ignore-not-found --wait=true >/dev/null 2>&1 || true

kubectl create namespace shop     >/dev/null
kubectl create namespace external >/dev/null

# --- shop namespace ----------------------------------------------------------
# api: the sensitive service (nginx on :80)
kubectl -n shop run api \
  --image=nginx:alpine \
  --labels="app=api" \
  --port=80 >/dev/null

# web: legit client that should reach api, and must resolve DNS
kubectl -n shop run web \
  --image=nicolaka/netshoot \
  --labels="app=web" \
  --command -- sleep 1d >/dev/null

# ClusterIP service so DNS name 'api.shop.svc.cluster.local' resolves
# (used to test that DNS egress still works after your default-deny).
kubectl -n shop expose pod api --name=api --port=80 >/dev/null

# --- external namespace ------------------------------------------------------
# scanner: an attacker in a DIFFERENT namespace. Must NOT reach api.
kubectl -n external run scanner \
  --image=nicolaka/netshoot \
  --labels="app=scanner" \
  --command -- sleep 1d >/dev/null

echo "Waiting for pods to become Ready (~30-60s)..."
kubectl -n shop     wait --for=condition=Ready pod --all --timeout=120s >/dev/null
kubectl -n external wait --for=condition=Ready pod --all --timeout=120s >/dev/null

echo
kubectl -n shop     get pods -o wide --show-labels
kubectl -n external get pods -o wide --show-labels

cat <<'TASK'

======================================================================
                              YOUR TASK
======================================================================
Namespaces involved: shop, external

In the 'shop' namespace, create NetworkPolicies so that:

1. DEFAULT-DENY: by default every pod in 'shop' denies BOTH ingress
   and egress traffic.

2. DNS must still work: the 'web' pod must be able to resolve cluster
   DNS names (allow egress to kube-system on port 53, UDP and TCP).

3. 'web' may make egress connections to 'api' pods on TCP 80 — and to
   nothing else (besides DNS from step 2).

4. 'api' may accept ingress ONLY from 'web' pods in 'shop', on TCP 80.

Net effect checked by verify.sh:
  - web  -> api:80         ALLOWED
  - web  DNS resolution    WORKS (nslookup api.shop.svc.cluster.local)
  - scanner(external) -> api:80   BLOCKED
  - a default-deny ingress AND a default-deny egress policy exist

Hints: cat ./task.md        Reveal: cat ./solution.sh
Verify: bash ./verify.sh
======================================================================
TASK
