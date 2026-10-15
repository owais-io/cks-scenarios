# Scenario 04 — RBAC Least Privilege (HARDEST)

**Domain:** Cluster Hardening (15%) · **Target time:** 15 min

## Task

Namespaces: `finance`, `payroll`, `audit`.

**Part A — SA `finance/reporter`.** It has far too much access, granted from
**more than one place**. Afterwards it must be able to do exactly this, and nothing more:

| Verb | Resource | Namespace |
|------|----------|-----------|
| get, list, watch | pods | finance |
| get | pod logs | finance |
| get | ConfigMap `report-config` only (no other ConfigMaps, no listing) | finance |

Use Role `reporter-role` + RoleBinding `reporter-binding` in `finance`. Remove **all**
of reporter's other access anywhere in the cluster, **without removing anyone else's access**.

**Part B — SA `audit/auditor`.**
- get, list, watch **Deployments** in `finance` **and** `payroll` only. Use **one**
  ClusterRole `deployment-reader`, bound by a RoleBinding `auditor-deployments` in each namespace.
- get, list **Nodes**: ClusterRole `node-reader` + ClusterRoleBinding `auditor-nodes`.

**Part C — Don't break anything.**
- User `platform-lead` stays cluster-admin.
- SA `finance/ci` can still create/update Deployments in `finance`.
- No `*` wildcards in `reporter-role`.

## The traps

1. **Hidden bindings.** Find *all* of reporter's access first:
   ```bash
   kubectl get rolebindings,clusterrolebindings -A -o wide | grep reporter
   ```
   There's one in a *different namespace* too.
2. **Shared binding.** One of them also grants `platform-lead` cluster-admin. Deleting it
   breaks Part C. Remove only reporter from `subjects:` (`kubectl edit clusterrolebinding ...`).
3. **Subresources.** `pods` does **not** cover `pods/log` (or `pods/exec`). Grant `pods/log` explicitly.
4. **resourceNames** limits verbs that name one object (`get`, `update`, `delete`...). It can't
   restrict `list`/`watch`, so a "get only `report-config`" rule gets `verbs: [get]`.
5. **`kubectl create role --resource-name`** applies the name restriction to *every* resource
   in that command. You need separate rules → write YAML (or start from `--dry-run=client -o yaml`).
6. **API groups.** Deployments are in `apps`, not core `""`. Wrong group = the rule silently matches nothing.
7. **Scope.**
   - ClusterRole + **RoleBinding** → those rules granted only in that one namespace (reusable role).
   - ClusterRole + **ClusterRoleBinding** → granted in **every** namespace. That's wrong for Deployments here.
   - **Nodes** are cluster-scoped, so only a ClusterRoleBinding can grant them.
8. **ServiceAccount vs User subject.** `--user=reporter` binds a *User* named `reporter`,
   which is not the SA. The SA's identity is `system:serviceaccount:finance:reporter`. Use:
   ```bash
   kubectl -n finance create rolebinding reporter-binding --role=reporter-role \
     --serviceaccount=finance:reporter
   ```
   In YAML the subject is `kind: ServiceAccount` + `name` + `namespace` (no `apiGroup`).
9. **Exact resource names, with no validation.** RBAC accepts any string, so a typo
   silently matches nothing:
   - The subresource is `pods/log` (singular), **not** `pods/logs`.
   - Use full plural names (`configmaps`, `deployments`, `pods`), **not** short names
     (`cm`, `deploy`, `po`). Short names only work on the kubectl command line.

   Check exact names with `kubectl api-resources` (the NAME column). Always confirm a rule
   with `kubectl auth can-i`.

## Test yourself

```bash
kubectl auth can-i get pods --subresource=log -n finance --as=system:serviceaccount:finance:reporter
kubectl auth can-i get configmap/db-config    -n finance --as=system:serviceaccount:finance:reporter
kubectl auth can-i --list -n payroll                   --as=system:serviceaccount:finance:reporter
kubectl auth can-i list deployments.apps -n default    --as=system:serviceaccount:audit:auditor
```

## Commands

```bash
bash ./setup.sh      # build env + show task
bash ./verify.sh     # grade your solution
bash ./solution.sh   # reveal / apply reference answer
bash ./cleanup.sh    # delete namespaces + the scenario's cluster-scoped RBAC
```
