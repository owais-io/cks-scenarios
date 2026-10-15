#!/usr/bin/env bash
# CKS Scenario 01 — NetworkPolicy: Default-Deny + Selective Allow
# Domain: Cluster Hardening (15%)
#
# Run this on the Killercoda Kubernetes playground to build the environment
# and print the task. Then solve it, then run ./verify.sh to check yourself.

set -euo pipefail

NS=prod

echo "=== Setting up CKS Scenario 01: NetworkPolicy ==="

# Clean slate if re-running
kubectl delete namespace "$NS" --ignore-not-found --wait=true >/dev/null 2>&1 || true

kubectl create namespace "$NS" >/dev/null

# Backend "database" — should ONLY be reachable from the api pod.
kubectl -n "$NS" run db \
  --image=nginx:alpine \
  --labels="app=db" \
  --port=80 >/dev/null

# Legit client that SHOULD reach the db.
kubectl -n "$NS" run api \
  --image=nicolaka/netshoot \
  --labels="app=api" \
  --command -- sleep 1d >/dev/null

# Unauthorized client that should NOT reach the db.
kubectl -n "$NS" run attacker \
  --image=nicolaka/netshoot \
  --labels="app=attacker" \
  --command -- sleep 1d >/dev/null

echo "Waiting for pods to become Ready (pulling images, ~30-60s)..."
kubectl -n "$NS" wait --for=condition=Ready pod --all --timeout=120s >/dev/null

echo
echo "Current pods:"
kubectl -n "$NS" get pods -o wide --show-labels

cat <<'TASK'

======================================================================
                              YOUR TASK
======================================================================
Namespace: prod

1. Apply a DEFAULT-DENY INGRESS policy so that, by default, no pod in
   the 'prod' namespace accepts any incoming traffic.

2. Add a NetworkPolicy that allows the 'db' pod (label app=db) to
   receive ingress on TCP port 80 ONLY from pods labeled app=api,
   within the same namespace.

Requirements checked by verify.sh:
  - pod 'api'      CAN reach db on port 80
  - pod 'attacker' CANNOT reach db on port 80
  - a default-deny ingress policy exists in the namespace

Do NOT modify the pods. Create NetworkPolicy objects only.

When done:   bash ./verify.sh
Need a hint: cat ./task.md
Reveal all:  cat ./solution.sh
======================================================================
TASK
