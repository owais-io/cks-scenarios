#!/usr/bin/env bash
# CKS Scenario 03 — reference solution. Read it, or run it to auto-apply.
set -euo pipefail

cat <<'EOF'
Applying reference solution (3 policies in 'secure'):
  1) default-deny-all      empty podSelector, Ingress+Egress, no rules
  2) allow-payments-ingress  payments <- (secure AND app=gateway)  OR  (monitoring ns)
  3) allow-gateway-egress    gateway -> payments:80  AND  gateway -> kube-system:53

KEY: in policy (2), the FIRST 'from' item lists namespaceSelector AND
podSelector together (both must match = secure/gateway only). The SECOND
'from' item is a separate list entry (OR) matching the whole monitoring ns.
EOF

kubectl apply -f - <<'YAML'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: secure
spec:
  podSelector: {}
  policyTypes:
    - Ingress
    - Egress
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-payments-ingress
  namespace: secure
spec:
  podSelector:
    matchLabels:
      app: payments
  policyTypes:
    - Ingress
  ingress:
    - from:
        # (a) AND: must be in namespace 'secure' AND labeled app=gateway.
        #     Both selectors live in the SAME list item -> they are AND'd.
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: secure
          podSelector:
            matchLabels:
              app: gateway
        # (b) OR: a separate list item -> any pod in the monitoring namespace.
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: monitoring
      ports:
        - protocol: TCP
          port: 80
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-gateway-egress
  namespace: secure
spec:
  podSelector:
    matchLabels:
      app: gateway
  policyTypes:
    - Egress
  egress:
    - to:
        - podSelector:
            matchLabels:
              app: payments
      ports:
        - protocol: TCP
          port: 80
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: kube-system
      ports:
        - protocol: UDP
          port: 53
        - protocol: TCP
          port: 53
YAML

echo "Done. Now run: bash ./verify.sh"
