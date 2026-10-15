#!/usr/bin/env bash
# CKS Scenario 01 — reference solution.
# Run this to auto-apply the correct manifests, OR just read it to learn.

set -euo pipefail
NS=prod

cat <<'EOF'
Applying the reference solution:
  1) default-deny-ingress  (empty podSelector, Ingress, no rules)
  2) allow-api-to-db       (db <- api on TCP 80)
EOF

kubectl apply -f - <<YAML
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-ingress
  namespace: ${NS}
spec:
  podSelector: {}
  policyTypes:
    - Ingress
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-api-to-db
  namespace: ${NS}
spec:
  podSelector:
    matchLabels:
      app: db
  policyTypes:
    - Ingress
  ingress:
    - from:
        - podSelector:
            matchLabels:
              app: api
      ports:
        - protocol: TCP
          port: 80
YAML

echo "Done. Now run: bash ./verify.sh"
