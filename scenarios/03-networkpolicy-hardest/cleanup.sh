#!/usr/bin/env bash
# CKS Scenario 03 — cleanup. Removes everything the scenario, the user, or
# solution.sh created. Deleting the namespaces removes all pods, services, and
# NetworkPolicies inside them.
set -euo pipefail

echo "=== Cleaning up CKS Scenario 03 ==="
kubectl delete namespace secure dev monitoring --ignore-not-found --wait=true
echo "Done. Namespaces 'secure', 'dev', 'monitoring' removed."
echo "Re-run 'bash ./setup.sh' to start fresh."
