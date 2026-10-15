#!/usr/bin/env bash
# CKS Scenario 04 — cleanup. Deleting the namespaces removes their SAs, Roles,
# RoleBindings, deployments, configmaps and secrets. Cluster-scoped objects
# (ClusterRoles / ClusterRoleBindings) are NOT namespaced, so delete them too.
set -euo pipefail

echo "=== Cleaning up CKS Scenario 04 ==="
kubectl delete clusterrolebinding platform-admins auditor-nodes --ignore-not-found
kubectl delete clusterrole deployment-reader node-reader --ignore-not-found
kubectl delete namespace finance payroll audit --ignore-not-found --wait=true
echo "Done. Namespaces 'finance', 'payroll', 'audit' and the scenario's cluster-scoped RBAC removed."
echo "(If you created ClusterRoles/ClusterRoleBindings with other names, delete those yourself.)"
echo "Re-run 'bash ./setup.sh' to start fresh."
