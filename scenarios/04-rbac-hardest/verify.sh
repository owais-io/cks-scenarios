#!/usr/bin/env bash
# CKS Scenario 04 — verifier. Uses 'kubectl auth can-i --as=...' to test the
# EFFECTIVE permissions of each identity, plus a few structural checks.
# Runs every check and prints a score.

PASS=0; FAIL=0
green() { printf '\033[32m%s\033[0m\n' "$1"; }
red()   { printf '\033[31m%s\033[0m\n' "$1"; }
yellow(){ printf '\033[33m%s\033[0m\n' "$1"; }
ok()  { green "  [PASS] $1"; PASS=$((PASS+1)); }
bad() { red   "  [FAIL] $1"; FAIL=$((FAIL+1)); }

REPORTER=system:serviceaccount:finance:reporter
AUDITOR=system:serviceaccount:audit:auditor
CI=system:serviceaccount:finance:ci

# allow/deny <desc> <as> <can-i args...>  — 'can-i --quiet' exits 0 for yes.
allow() { local d=$1 as=$2; shift 2
  if kubectl auth can-i "$@" --as="$as" --quiet 2>/dev/null; then ok "$d"; else bad "$d  (currently DENIED, should be allowed)"; fi; }
deny()  { local d=$1 as=$2; shift 2
  if kubectl auth can-i "$@" --as="$as" --quiet 2>/dev/null; then bad "$d  (currently ALLOWED, should be denied)"; else ok "$d"; fi; }

echo "=== Verifying CKS Scenario 04: RBAC Least Privilege (HARDEST) ==="
echo

for ns in finance payroll audit; do
  if ! kubectl get ns "$ns" >/dev/null 2>&1; then
    red "Namespace '$ns' not found. Run ./setup.sh first."; exit 1
  fi
done

echo "PART A — finance/reporter: required access"
allow "reporter can list pods in finance"                    "$REPORTER" list  pods -n finance
allow "reporter can watch pods in finance"                   "$REPORTER" watch pods -n finance
allow "reporter can get pods in finance"                     "$REPORTER" get   pods -n finance
allow "reporter can get pods/log in finance (subresource)"   "$REPORTER" get   pods --subresource=log -n finance
allow "reporter can get configmap/report-config in finance"  "$REPORTER" get   configmap/report-config -n finance

echo
echo "PART A — finance/reporter: everything else denied"
deny  "reporter cannot get configmap/db-config (resourceNames scoping)" "$REPORTER" get    configmap/db-config -n finance
deny  "reporter cannot list configmaps in finance"           "$REPORTER" list   configmaps -n finance
deny  "reporter cannot get secrets in finance"               "$REPORTER" get    secrets -n finance
deny  "reporter cannot delete pods in finance"               "$REPORTER" delete pods -n finance
deny  "reporter cannot exec into pods in finance"            "$REPORTER" create pods --subresource=exec -n finance
deny  "reporter cannot list pods in payroll (legacy binding gone?)" "$REPORTER" list pods -n payroll
deny  "reporter cannot get secrets in payroll"               "$REPORTER" get    secrets -n payroll
deny  "reporter cannot list pods in default"                 "$REPORTER" list   pods -n default
deny  "reporter cannot list pods cluster-wide"               "$REPORTER" list   pods -A
deny  "reporter is not cluster-admin (* on *)"               "$REPORTER" '*' '*'

echo
echo "PART B — audit/auditor"
allow "auditor can list deployments in finance"              "$AUDITOR" list  deployments.apps -n finance
allow "auditor can watch deployments in finance"             "$AUDITOR" watch deployments.apps -n finance
allow "auditor can get deployments in payroll"               "$AUDITOR" get   deployments.apps -n payroll
allow "auditor can list deployments in payroll"              "$AUDITOR" list  deployments.apps -n payroll
allow "auditor can list nodes"                               "$AUDITOR" list  nodes
allow "auditor can get nodes"                                "$AUDITOR" get   nodes
deny  "auditor cannot list deployments in default (not cluster-wide)" "$AUDITOR" list deployments.apps -n default
deny  "auditor cannot list deployments cluster-wide"         "$AUDITOR" list   deployments.apps -A
deny  "auditor cannot delete deployments in finance"         "$AUDITOR" delete deployments.apps -n finance
deny  "auditor cannot get secrets in finance"                "$AUDITOR" get    secrets -n finance
deny  "auditor cannot list pods in finance"                  "$AUDITOR" list   pods -n finance
deny  "auditor cannot delete nodes"                          "$AUDITOR" delete nodes

echo
echo "PART C — nothing else broken"
allow "platform-lead is still cluster-admin"                 platform-lead '*' '*'
allow "ci can still create deployments in finance"           "$CI" create deployments.apps -n finance
allow "ci can still update deployments in finance"           "$CI" update deployments.apps -n finance

echo
echo "Structure — required object names"
RB=$(kubectl -n finance get rolebinding reporter-binding -o jsonpath='{.roleRef.kind}/{.roleRef.name}' 2>/dev/null)
if kubectl -n finance get role reporter-role >/dev/null 2>&1 && [ "$RB" = "Role/reporter-role" ]; then
  ok "Role reporter-role + RoleBinding reporter-binding -> Role/reporter-role in finance"
else
  bad "need Role 'reporter-role' and RoleBinding 'reporter-binding' (roleRef Role/reporter-role) in finance"
fi

RULES=$(kubectl -n finance get role reporter-role -o jsonpath='{.rules[*].apiGroups} {.rules[*].resources} {.rules[*].verbs}' 2>/dev/null)
if [ -n "$RULES" ] && [[ "$RULES" != *'*'* ]]; then
  ok "reporter-role contains no wildcards"
else
  bad "reporter-role is missing or contains '*' wildcards"
fi

for ns in finance payroll; do
  REF=$(kubectl -n "$ns" get rolebinding auditor-deployments -o jsonpath='{.roleRef.kind}/{.roleRef.name}' 2>/dev/null)
  if [ "$REF" = "ClusterRole/deployment-reader" ]; then
    ok "RoleBinding auditor-deployments in $ns -> ClusterRole/deployment-reader"
  else
    bad "need RoleBinding 'auditor-deployments' in $ns with roleRef ClusterRole/deployment-reader (got: ${REF:-missing})"
  fi
done

REF=$(kubectl get clusterrolebinding auditor-nodes -o jsonpath='{.roleRef.kind}/{.roleRef.name}' 2>/dev/null)
if [ "$REF" = "ClusterRole/node-reader" ]; then
  ok "ClusterRoleBinding auditor-nodes -> ClusterRole/node-reader"
else
  bad "need ClusterRoleBinding 'auditor-nodes' with roleRef ClusterRole/node-reader (got: ${REF:-missing})"
fi

if kubectl get clusterrolebinding platform-admins >/dev/null 2>&1; then
  ok "ClusterRoleBinding platform-admins still exists (edited, not deleted)"
else
  bad "ClusterRoleBinding platform-admins was deleted — you should only have removed reporter from its subjects"
fi

# --- Diagnostics (not scored) -------------------------------------------------
# The API server never validates RBAC names: typos like 'cm', 'pods/logs' or a
# wrong apiGroup are stored and silently match nothing. Lint the scenario's
# roles and bindings against API discovery to explain WHY a check failed.
HINTS=()
hint() { HINTS+=("$1"); }

declare -A DISC        # "g:<apiGroup>" -> discovery JSON (empty = group doesn't exist).
                       # Keys are prefixed because bash forbids an empty key and core is "".
load_group() {         # $1 = apiGroup ("" = core)
  local g=$1 gv
  [ -n "${DISC[g:$g]+x}" ] && return
  if [ -z "$g" ]; then
    DISC[g:$g]=$(kubectl get --raw /api/v1 2>/dev/null)
  else
    gv=$(kubectl get --raw "/apis/$g" 2>/dev/null | jq -r '.preferredVersion.groupVersion // empty' 2>/dev/null)
    if [ -n "$gv" ]; then DISC[g:$g]=$(kubectl get --raw "/apis/$gv" 2>/dev/null); else DISC[g:$g]=""; fi
  fi
}

VALID_VERBS=" get list watch create update patch delete deletecollection use bind escalate impersonate approve sign "

lint_resource() {      # $1 = label  $2 = apiGroup  $3 = resource
  local label=$1 g=$2 r=$3 names base sub long subs lc c other gq
  [[ $r == *'*'* ]] && return
  names=$(jq -r '.resources[].name' <<<"${DISC[g:$g]}")
  grep -qxF -- "$r" <<<"$names" && return
  gq="\"$g\""; [ -z "$g" ] && gq='"" (core)'
  base=${r%%/*}; sub=""; [[ $r == */* ]] && sub=${r#*/}

  # kubectl short name (cm, po, deploy...)
  long=$(jq -r --arg r "$base" '.resources[] | select((.shortNames // []) | index($r)) | .name' <<<"${DISC[g:$g]}" | head -1)
  if [ -n "$long" ]; then
    hint "$label: '$base' is a kubectl short name. RBAC needs the full name '$long${sub:+/$sub}'."; return
  fi
  # bad subresource on a valid resource (pods/logs)
  if [ -n "$sub" ] && grep -qxF -- "$base" <<<"$names"; then
    if grep -qxF -- "$base/${sub%s}" <<<"$names"; then
      hint "$label: '$r' doesn't exist. Did you mean '$base/${sub%s}'?"
    else
      subs=$(grep -- "^$base/" <<<"$names" | paste -sd' ' -)
      hint "$label: '$r' isn't a subresource of $base. Valid: ${subs:-none}"
    fi
    return
  fi
  # wrong case / singular (Pod, configmap)
  lc=$(tr '[:upper:]' '[:lower:]' <<<"$base")
  for c in "$lc" "${lc}s" "${lc}es"; do
    if [ "$c" != "$base" ] && grep -qxF -- "$c" <<<"$names"; then
      hint "$label: '$base' should be '$c${sub:+/$sub}' (resource names are lowercase plural)."; return
    fi
  done
  # right name, wrong apiGroup (deployments in "")
  if [ -z "$g" ]; then
    other=$(grep -m1 -- "^$base\." <<<"$ALL_RES" | cut -d. -f2-)
  elif grep -qxF -- "$base" <<<"$ALL_RES"; then
    other='"" (core)'
  else
    other=$(grep -m1 -- "^$base\." <<<"$ALL_RES" | cut -d. -f2-)
  fi
  if [ -n "$other" ]; then
    hint "$label: '$base' isn't in apiGroup $gq. It's in apiGroup '$other'."; return
  fi
  hint "$label: resource '$r' doesn't exist in apiGroup $gq (check the NAME column of 'kubectl api-resources')."
}

lint_role() {          # $1 = Role|ClusterRole  $2 = namespace ("" for cluster)  $3 = name
  local kind=$1 ns=$2 name=$3 J n i v g r label nsarg=()
  [ -n "$ns" ] && nsarg=(-n "$ns")
  J=$(kubectl get "$kind" "$name" "${nsarg[@]}" -o json 2>/dev/null) || return
  label="$kind $name"
  n=$(jq '.rules | length' <<<"$J")
  for ((i=0; i<n; i++)); do
    local -a groups resources verbs
    mapfile -t groups    < <(jq -r ".rules[$i].apiGroups[]?" <<<"$J")
    mapfile -t resources < <(jq -r ".rules[$i].resources[]?" <<<"$J")
    mapfile -t verbs     < <(jq -r ".rules[$i].verbs[]?"     <<<"$J")
    for v in "${verbs[@]}"; do
      [ "$v" = '*' ] && continue
      [[ $VALID_VERBS == *" $v "* ]] || hint "$label: '$v' isn't a Kubernetes verb (use get, list, watch, create, update, patch, delete...)."
    done
    for g in "${groups[@]}"; do
      [ "$g" = '*' ] && continue
      load_group "$g"
      if [ -z "${DISC[g:$g]}" ]; then hint "$label: apiGroup '$g' doesn't exist on this cluster."; continue; fi
      for r in "${resources[@]}"; do lint_resource "$label" "$g" "$r"; done
    done
  done
}

lint_binding() {       # $1 = RoleBinding|ClusterRoleBinding  $2 = ns  $3 = name  $4 = SA ns  $5 = SA name
  local kind=$1 ns=$2 name=$3 sans=$4 sa=$5 J label rk rn wrongns nsarg=()
  [ -n "$ns" ] && nsarg=(-n "$ns")
  J=$(kubectl get "$kind" "$name" "${nsarg[@]}" -o json 2>/dev/null) || return
  label="$kind $name${ns:+ ($ns)}"

  # roleRef to a role that doesn't exist is also accepted silently
  rk=$(jq -r '.roleRef.kind' <<<"$J"); rn=$(jq -r '.roleRef.name' <<<"$J")
  if [ "$rk" = Role ]; then
    kubectl -n "$ns" get role "$rn" >/dev/null 2>&1 || hint "$label: roleRef points to Role '$rn', which doesn't exist in '$ns'."
  else
    kubectl get clusterrole "$rn" >/dev/null 2>&1 || hint "$label: roleRef points to ClusterRole '$rn', which doesn't exist."
  fi

  jq -e --arg n "$sa" --arg ns "$sans" \
    '.subjects[]? | select(.kind=="ServiceAccount" and .name==$n and .namespace==$ns)' <<<"$J" >/dev/null && return
  if jq -e --arg n "$sa" '.subjects[]? | select(.kind=="User" and .name==$n)' <<<"$J" >/dev/null; then
    hint "$label: subject is User '$sa', not the ServiceAccount $sans/$sa. Use --serviceaccount=$sans:$sa (kind: ServiceAccount + namespace: $sans)."
  elif wrongns=$(jq -er --arg n "$sa" '.subjects[]? | select(.kind=="ServiceAccount" and .name==$n) | (.namespace // "<none>")' <<<"$J" | head -1) && [ -n "$wrongns" ]; then
    hint "$label: ServiceAccount subject '$sa' has namespace '$wrongns'; it must be '$sans'."
  else
    hint "$label: no subject for ServiceAccount $sans/$sa."
  fi
}

if command -v jq >/dev/null 2>&1; then
  ALL_RES=$(kubectl api-resources -o name 2>/dev/null)
  lint_role    Role        finance reporter-role
  lint_role    ClusterRole ""      deployment-reader
  lint_role    ClusterRole ""      node-reader
  lint_binding RoleBinding        finance reporter-binding    finance reporter
  lint_binding RoleBinding        finance auditor-deployments audit   auditor
  lint_binding RoleBinding        payroll auditor-deployments audit   auditor
  lint_binding ClusterRoleBinding ""      auditor-nodes       audit   auditor
  if [ "${#HINTS[@]}" -gt 0 ]; then
    echo
    yellow "Diagnostics — likely causes (RBAC stores these mistakes without any error):"
    for h in "${HINTS[@]}"; do yellow "  -> $h"; done
  fi
else
  echo
  yellow "  [SKIP] RBAC diagnostics need jq."
fi

echo
echo "----------------------------------------------------------------------"
TOTAL=$((PASS+FAIL))
if [ "$FAIL" -eq 0 ]; then
  green "RESULT: $PASS/$TOTAL checks passed. Scenario SOLVED. Least privilege, exam-grade!"
  exit 0
else
  red "RESULT: $PASS/$TOTAL checks passed, $FAIL failing."
  echo "Fix the failures and re-run ./verify.sh. (cat ./task.md for hints, ./solution.sh to reveal.)"
  exit 1
fi
