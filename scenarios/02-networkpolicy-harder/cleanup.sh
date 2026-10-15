#!/usr/bin/env bash
# CKS Scenario 02 — cleanup. Removes everything the scenario, the user, or
# solution.sh created. Deleting the namespaces removes their pods, services,
# and ALL NetworkPolicies inside them in one shot.
set -euo pipefail

echo "=== Cleaning up CKS Scenario 02 ==="
kubectl delete namespace shop external --ignore-not-found --wait=true
echo "Done. Namespaces 'shop' and 'external' (pods, services, NetworkPolicies) removed."
echo "Re-run 'bash ./setup.sh' to start fresh."
