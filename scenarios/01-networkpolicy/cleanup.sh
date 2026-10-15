#!/usr/bin/env bash
# CKS Scenario 01 — cleanup. Removes everything the scenario, the user, or
# solution.sh created. Deleting the namespace removes its pods, services, and
# ALL NetworkPolicies inside it in one shot.
set -euo pipefail

NS=prod
echo "=== Cleaning up CKS Scenario 01 ==="
kubectl delete namespace "$NS" --ignore-not-found --wait=true
echo "Done. Namespace '$NS' (pods + NetworkPolicies) removed."
echo "Re-run 'bash ./setup.sh' to start fresh."
