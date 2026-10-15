# CKS Practice Scenarios (Killercoda)

Hands-on, self-grading practice scenarios for the **Certified Kubernetes Security
Specialist (CKS)** exam. Each scenario is a folder with scripts:

- `setup.sh`   — builds the environment and prints the task
- `verify.sh`  — checks your solution and gives pass/fail feedback + a score
- `solution.sh`— the reference answer (read it, or run it to auto-apply)
- `cleanup.sh` — deletes the scenario's namespaces (and everything in them)
- `task.md`    — the task text + hints

## Workflow: GitHub → Killercoda

**1. Push this folder to your own GitHub repo (one time, from your PC):**

```bash
cd D:\cks-scenarios
git init
git add .
git commit -m "CKS practice scenarios"
git branch -M main
git remote add origin https://github.com/<your-username>/cks-scenarios.git
git push -u origin main
```

**2. On the Killercoda playground, clone and run:**

Open https://killercoda.com/playgrounds/scenario/kubernetes → Start, then in the terminal:

```bash
git clone https://github.com/<your-username>/cks-scenarios.git
cd cks-scenarios/scenarios/01-networkpolicy

bash ./setup.sh      # creates resources + prints YOUR TASK
#  ... solve the task in the terminal ...
bash ./verify.sh     # grades your solution and prints feedback
bash ./solution.sh   # reveal / auto-apply the reference answer
bash ./cleanup.sh    # remove the scenario's namespaces when done
```

That's it. Re-run `setup.sh` any time to reset the scenario cleanly.

> **Line endings:** this repo ships a `.gitattributes` that forces LF on `*.sh`,
> so the scripts run correctly on the Linux playground even though they were
> authored on Windows. If you ever hit a `bad interpreter` error, run
> `sed -i 's/\r$//' *.sh` in the scenario folder.

## Scenarios

| # | Title | Domain | Folder |
|---|-------|--------|--------|
| 01 | NetworkPolicy: Default-Deny + Selective Allow | Cluster Hardening | `scenarios/01-networkpolicy` |
| 02 | NetworkPolicy (harder): Egress, DNS & Cross-Namespace | Cluster Hardening | `scenarios/02-networkpolicy-harder` |
| 03 | NetworkPolicy (hardest): Combined Selectors (AND/OR trap) | Cluster Hardening | `scenarios/03-networkpolicy-hardest` |
| 04 | RBAC (hardest): Least Privilege, Hidden & Shared Bindings | Cluster Hardening | `scenarios/04-rbac-hardest` |

_More on request: Pod Security Admission, seccomp/AppArmor,
Falco runtime detection, Trivy image scanning, apiserver audit logging, etcd
encryption at rest, Gatekeeper/Kyverno admission._
