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

| Endpoint          | Why it exists                                                           |
| ----------------- | ----------------------------------------------------------------------- |
| `/`             | Big coloured page — proves which version users are hitting             |
| `/api/info`     | `{version, color, pod}` — what the smoke test checks                 |
| `/api/add`      | Something for the tests to actually test                                |
| `/health/live`  | Liveness probe — failing it**restarts** the pod                  |
| `/health/ready` | Readiness probe — failing it only**removes it from the Service** |

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

## Secrets and variables the pipeline needs

Repo → Settings → Secrets and variables → Actions:

| Name                    | Kind         | Value                                                 |
| ------------------------ | ------------ | ------------------------------------------------------ |
| `DOCKERHUB_USERNAME`   | **Variable** | your Docker Hub username — not sensitive, so it's a plain variable, not a secret |
| `DOCKERHUB_TOKEN`      | **Secret**   | Docker Hub **access token**, never your password      |

> Why `DOCKERHUB_USERNAME` is a variable, not a secret: GitHub Actions silently
> **empties any job output that contains a secret substring** once it crosses a
> job boundary (logged as `Skip output 'image' since it may contain secret`).
> The `build-and-push` job's `image` output embeds the username, so as a secret
> it broke the `deploy` job's `needs.build-and-push.outputs.image` — always,
> invisibly, until the deploy job actually started running. A Docker Hub
> username isn't sensitive, so moving it to `vars` fixes this cleanly.

`KUBE_CONFIG` is **not used** in this repo anymore — `ci-cd.yml`'s deploy job
runs on a self-hosted runner instead of an internet-reachable cluster. See
"Connecting your local kind cluster to GitHub Actions" at the end of this file.

> A kind/minikube cluster on your laptop is **not** reachable from a GitHub-hosted
> runner — that is a network fact, not a config mistake. A self-hosted runner
> (below) is how you work around it without a cloud cluster or a credit card.

---

## "Can the whole thing actually run on GitHub?" — yes, three ways

| Workflow                | Runs on GitHub?                 | Needs                                             | Deploys to                               |
| ----------------------- | ------------------------------- | ------------------------------------------------- | ---------------------------------------- |
| `k8s-in-runner.yml`   | **fully, out of the box** | nothing                                           | a kind cluster created inside the runner |
| `ci-cd.yml` jobs 1–2 | yes                             | Docker Hub variable + secret                      | nothing (build + push only)              |
| `ci-cd.yml` job 3     | on a **self-hosted runner**, not GitHub's cloud | a runner registered on a machine that can reach the cluster | this repo: your local kind cluster |

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

---

## Connecting your local kind cluster to GitHub Actions

`ci-cd.yml`'s deploy job needs to reach a real cluster, and a GitHub-hosted
runner physically cannot reach `localhost` on your laptop — that's a network
fact, not something a kubeconfig fixes. Without a cloud cluster (which every
provider gates behind a credit card), the fix is a **self-hosted runner**: you
register your own machine as a GitHub Actions runner, so the deploy job
executes *on your Mac* and can talk to your local kind cluster directly, using
the kubeconfig that's already sitting there.

### One-time setup

1. **Generate a registration token and download the runner** (from the repo
   root; `OWNER/REPO` is this repo):

   ```bash
   gh api -X POST repos/OWNER/REPO/actions/runners/registration-token --jq '.token'

   mkdir -p ~/actions-runner-cicd-pipeline && cd ~/actions-runner-cicd-pipeline
   curl -o actions-runner.tar.gz -L \
     https://github.com/actions/runner/releases/latest/download/actions-runner-osx-arm64-<version>.tar.gz
   tar xzf actions-runner.tar.gz
   ```

   (Use the `osx-x64` asset instead of `osx-arm64` on an Intel Mac.)

2. **Register it against this repo**, using the token from step 1:

   ```bash
   ./config.sh --url https://github.com/OWNER/REPO \
     --token <TOKEN> \
     --name kaushal-mac \
     --labels self-hosted,macOS,kind \
     --work _work \
     --unattended
   ```

3. **Start it** — either in a terminal you leave open:

   ```bash
   ./run.sh
   ```

   or as a persistent background service that survives reboots:

   ```bash
   ./svc.sh install
   ./svc.sh start
   ```

4. `ci-cd.yml`'s `deploy` job already targets this runner
   (`runs-on: [self-hosted, macOS, kind]`) and runs
   `kubectl config use-context kind-cicd-demo` before applying anything, so no
   further workflow changes are needed — just make sure `kind get clusters`
   shows `cicd-demo` and the runner is online before you push.

### Security note (this repo is public)

A self-hosted runner on a public repo executes whatever code a triggered
workflow contains, on your actual machine. Two things keep that safe here:

- GitHub requires **your explicit approval** before a first-time outside
  contributor's workflow run is allowed to execute (repo default, on by
  default for public repos) — don't approve runs from PRs you don't trust.
- Only start the runner (`./run.sh` / `./svc.sh start`) when you're actively
  using it; stop it (`./svc.sh stop` or Ctrl+C) otherwise.

### Verifying the deploy actually happened on your kind cluster

Run these after any pipeline run — they don't depend on me or on GitHub's UI:

```bash
# 1. The cluster exists and is the active context
kind get clusters
kubectl config current-context          # -> kind-cicd-demo

# 2. What's actually running right now
kubectl -n cicd-demo get deploy,pods,svc

# 3. The running image tag matches the exact commit that triggered the pipeline
kubectl -n cicd-demo get deploy cicd-demo \
  -o jsonpath='{.spec.template.spec.containers[0].image}'
echo
git log -1 --format=%h

# 4. The live app reports the same version
curl -s http://localhost:30080/api/info

# 5. Confirm the job ran on your machine, not GitHub's cloud
gh api repos/OWNER/REPO/actions/runners --jq '.runners[] | {name,status}'
```

One-liner that proves it end to end — commit SHA, the running image, and the
live app's own reported version, all cross-checked at once:

```bash
diff <(git log -1 --format=%h) \
     <(curl -s http://localhost:30080/api/info | python3 -c "import json,sys;print(json.load(sys.stdin)['version'])") \
  && echo "MATCH — this pod was deployed by this pipeline run"
```
