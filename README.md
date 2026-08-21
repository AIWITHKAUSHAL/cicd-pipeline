# Complete CI/CD Pipeline — teaching edition

`GitHub → Testing → Docker Build → Docker Hub → Kubernetes Deployment`
plus the bonus: **Blue-Green Deployment**.

The app is intentionally tiny (one file, ~60 lines). Everything worth
explaining lives in the pipeline, not in the code.

---

## What the app does

A page that fills the screen with **BLUE** or **GREEN**, and prints the version
and the pod name. That is all. Because of that, the audience can *see* which
version is live without reading a log.

| Endpoint | Why it exists |
|---|---|
| `/` | Big coloured page — proves which version users are hitting |
| `/api/info` | `{version, color, pod}` — what the smoke test checks |
| `/api/add` | Something for the tests to actually test |
| `/health/live` | Liveness probe — failing it **restarts** the pod |
| `/health/ready` | Readiness probe — failing it only **removes it from the Service** |

---

## Repo map

```
app/main.py                     the whole application
tests/test_main.py              6 tests — the "Automated Testing" requirement
Dockerfile                      one instruction per concept, commented
.github/workflows/ci-cd.yml     test → build → push → deploy (rolling update)
.github/workflows/blue-green.yml  the bonus: deploy idle -> smoke test -> switch
.github/workflows/k8s-in-runner.yml  full E2E inside GitHub, zero secrets needed
k8s/deployment.yaml             rolling-update Deployment (maxUnavailable: 0)
k8s/service.yaml                NodePort 30080
k8s/blue-green/                 blue + green Deployments, live + preview Services
scripts/*.ps1                   local demo on Windows + kind
docs/PIPELINE_EXPLAINED.md      concept-by-concept teaching notes
docs/VIDEO_SCRIPT.md            beat-by-beat recording script
```

---

## Run it locally in 4 commands

```powershell
pip install -r requirements.txt
pytest -v                       # 6 passing tests
.\scripts\kind-up.ps1           # local Kubernetes cluster
.\scripts\deploy-local.ps1 -Version v1
# open http://localhost:30080
```

Blue-green demo:

```powershell
.\scripts\bluegreen-up.ps1 -BlueVersion v1 -GreenVersion v2
# live    -> http://localhost:30080   (blue)
# preview -> http://localhost:30081   (green, no real users)
.\scripts\switch-color.ps1            # flip live traffic to green
.\scripts\switch-color.ps1 -To blue   # rollback in under a second
```

---

## Secrets the pipeline needs

Repo → Settings → Secrets and variables → Actions:

| Secret | Value |
|---|---|
| `DOCKERHUB_USERNAME` | your Docker Hub username |
| `DOCKERHUB_TOKEN` | Docker Hub **access token**, never your password |
| `KUBE_CONFIG` | `kubectl config view --raw --minify` output, base64-encoded |

If `KUBE_CONFIG` is missing, the deploy job skips cleanly instead of failing —
so the repo stays green for students who only have a local cluster.

> A kind/minikube cluster on your laptop is **not** reachable from a GitHub-hosted
> runner — that is a network fact, not a config mistake. See the next section.

---

## "Can the whole thing actually run on GitHub?" — yes, three ways

| Workflow | Runs on GitHub? | Needs | Deploys to |
|---|---|---|---|
| `k8s-in-runner.yml` | **fully, out of the box** | nothing | a kind cluster created inside the runner |
| `ci-cd.yml` jobs 1–2 | yes | Docker Hub secrets | nothing (build + push only) |
| `ci-cd.yml` job 3 | yes | `KUBE_CONFIG` for a **reachable** cluster | EKS/GKE/AKS, or a self-hosted runner |

**`k8s-in-runner.yml` is the one to demo first.** It runs pytest, builds the
image with Docker (preinstalled on `ubuntu-latest`), creates a real Kubernetes
cluster *inside the runner* with `helm/kind-action`, loads the image, deploys,
curls the Service to prove it answers, then stands up blue **and** green,
switches live traffic, and rolls back — every step visible in the Actions log.
Fork it, push, it goes green. No account, no secrets, no cluster.

The trade-off to say out loud: that cluster is deleted when the job ends, so it
verifies the pipeline rather than serving users. `ci-cd.yml` is the real one, and
its deploy job needs a cluster a runner can actually reach — a managed cloud
cluster, or a self-hosted runner on the machine that has your kind cluster.

---

## Why each piece is there (short version)

- **`needs: test`** — a failing test means no image is ever built. That single
  keyword is the entire argument for CI.
- **`if: github.event_name != 'pull_request'`** — PRs get tested, never published.
- **Tag = git SHA** — `:latest` is a moving target; a SHA tag is immutable, so a
  rollback means redeploying a tag that definitely still exists.
- **`maxUnavailable: 0`** — the rolling update never dips below full capacity.
- **`kubectl rollout status`** — turns "kubectl accepted my YAML" into "the new
  pods are actually healthy". Without it the job goes green on a broken deploy.
- **`rollout undo` on failure** — automatic rollback, `if: failure()`.

Full explanations: `docs/PIPELINE_EXPLAINED.md`.
