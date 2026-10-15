#!/usr/bin/env bash
# CKS Scenario 02 — reference solution. Read it, or run it to auto-apply.
set -euo pipefail

cat <<'EOF'
Applying reference solution (3 policies in 'shop'):
  1) default-deny-all            empty podSelector, Ingress+Egress, no rules
  2) allow-web-egress            web -> api:80  AND  web -> kube-system:53 (DNS)
  3) allow-api-ingress-from-web  api <- web on TCP 80
Note: policies are additive; the allows stack on top of the default-deny.
EOF

kubectl apply -f - <<'YAML'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: shop
spec:
  podSelector: {}
  policyTypes:
    - Ingress
    - Egress
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-web-egress
  namespace: shop
spec:
  podSelector:
    matchLabels:
      app: web
  policyTypes:
    - Egress
  egress:
    # allow traffic to api pods on TCP 80
    - to:
        - podSelector:
            matchLabels:
              app: api
      ports:
        - protocol: TCP
          port: 80
    # allow DNS to kube-system (the trap: default-deny egress kills DNS otherwise)
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: kube-system
      ports:
        - protocol: UDP
          port: 53
        - protocol: TCP
          port: 53
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-api-ingress-from-web
  namespace: shop
spec:
  podSelector:
    matchLabels:
      app: api
  policyTypes:
    - Ingress
  ingress:
    - from:
        - podSelector:
            matchLabels:
              app: web
      ports:
        - protocol: TCP
          port: 80
YAML

echo "Done. Now run: bash ./verify.sh"
