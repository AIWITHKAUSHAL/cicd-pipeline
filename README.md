# Complete CI/CD Pipeline — teaching edition

`GitHub push → pytest → Docker build → Docker Hub push → Kubernetes deployment`
plus automated smoke testing, promotion, and rollback using **blue-green
deployment**.

The app is intentionally tiny (one Python module). Everything worth
explaining lives in the pipeline, not in the code.

## Assignment requirements and implementation evidence

All assessed parts are included in this repository:

| Requirement | Implementation |
| --- | --- |
| Automated testing | [`ci-cd.yml`](.github/workflows/ci-cd.yml) runs all 7 tests in [`tests/test_main.py`](tests/test_main.py) before any image is built. |
| Image build and push | The `build-and-push` job logs in with `docker/login-action@v3` and uses `docker/build-push-action@v6` to push both an immutable commit-SHA tag and `latest` to Docker Hub. |
| Kubernetes deployment | The workflow applies the manifests under [`k8s/`](k8s/) and waits for the Kubernetes rollout to become healthy. |
| Blue-green deployment | [`deployment-blue.yaml`](k8s/blue-green/deployment-blue.yaml) and [`deployment-green.yaml`](k8s/blue-green/deployment-green.yaml) run side by side. The [live Service](k8s/blue-green/service.yaml) and [preview Service](k8s/blue-green/service-preview.yaml) route traffic using the `color` selector. |
| GitHub Actions automation | A push to `main` automatically performs test → build → push → deploy using [`.github/workflows/ci-cd.yml`](.github/workflows/ci-cd.yml). Pull requests run tests but do not publish or deploy. |

> **Important when submitting:** `.github` is a hidden directory on macOS and
> Linux. If files are selected manually for upload, the complete Actions
> workflow can be omitted even though it exists locally. See
> [Submission checklist](#submission-checklist) for a safe way to create the
> submission archive.

---

## What the app does

A page that fills the screen with **BLUE** or **GREEN**, and prints the version
and the pod name. That is all. Because of that, the audience can *see* which
version is live without reading a log.

| Endpoint          | Why it exists                                                           |
| ----------------- | ----------------------------------------------------------------------- |
| `/`             | Big coloured page — proves which version users are hitting             |
| `/api/info`     | `{version, color, pod, greeting}` — what the smoke test checks       |
| `/api/add`      | Something for the tests to actually test                                |
| `/health/live`  | Liveness endpoint — a failed configured probe restarts the pod       |
| `/health/ready` | Readiness endpoint — a failed probe removes the pod from the Service  |

Runtime request flow:

```text
Browser / smoke test
        |
        v
localhost:30080 (live) or :30081 (preview)
        |
        v
Kubernetes NodePort Service
        |
        | selector: app=cicd-demo,color=blue|green
        v
Ready FastAPI pod on port 8000
        |
        +-- APP_VERSION: embedded in the image during docker build
        +-- APP_COLOR:   supplied by the Kubernetes Deployment
        +-- POD_NAME:    supplied by the Kubernetes Downward API
```

---

## Repo map

```
app/main.py                     the whole application
tests/test_main.py              7 tests — the "Automated Testing" requirement
Dockerfile                      one instruction per concept, commented
.github/workflows/ci-cd.yml     test → build → push → deploy (blue-green default)
.github/workflows/blue-green.yml  the bonus: deploy idle -> smoke test -> switch
.github/workflows/k8s-in-runner.yml  full E2E inside GitHub, zero secrets needed
k8s/deployment.yaml             rolling-update Deployment (maxUnavailable: 0)
k8s/service.yaml                NodePort 30080
k8s/blue-green/                 blue + green Deployments, live + preview Services
scripts/*.ps1                   local demo on Windows/PowerShell + kind
scripts/*.sh                    blue-green demo helpers for macOS/Linux
docs/PIPELINE_EXPLAINED.md      concept-by-concept teaching notes
docs/VIDEO_SCRIPT.md            beat-by-beat recording script
```

---

## Prerequisites

- Python 3.11 and `pip`
- Docker Desktop or another running Docker engine
- `kind`
- `kubectl`
- PowerShell for the complete local helper-script flow
- A Docker Hub account and GitHub repository secrets only for the registry
  pipeline; the self-contained E2E workflow needs neither

## Run it locally

```powershell
pip install -r requirements.txt
pytest -v                       # 7 passing tests
.\scripts\kind-up.ps1           # local Kubernetes cluster
.\scripts\deploy-local.ps1 -Version v1
# open http://localhost:30080
```

Blue-green demo:

```powershell
# Free NodePort 30080 if the rolling-update demo above is still running.
kubectl -n cicd-demo delete svc cicd-demo --ignore-not-found
.\scripts\bluegreen-up.ps1 -BlueVersion v1 -GreenVersion v2
# live    -> http://localhost:30080   (blue)
# preview -> http://localhost:30081   (green, no real users)
.\scripts\switch-color.ps1            # flip live traffic to green
.\scripts\switch-color.ps1 -To blue   # rollback in under a second
```

On macOS/Linux, after creating the `cicd-demo` kind cluster and namespace, the
equivalent blue-green commands are:

```bash
kubectl -n cicd-demo delete svc cicd-demo --ignore-not-found
./scripts/bluegreen-up.sh v1 v2
./scripts/watch-live.sh                 # optional traffic monitor
./scripts/switch-color.sh               # promote the idle colour
./scripts/switch-color.sh blue          # roll back to blue
```

To remove the local cluster on Windows, run `.\scripts\teardown.ps1`. On
macOS/Linux, run `kind delete cluster --name cicd-demo`.

---

## Automatic GitHub Actions flow

The main workflow is [`.github/workflows/ci-cd.yml`](.github/workflows/ci-cd.yml).
It runs automatically for pushes to `main`, runs its test job for pull requests
to `main`, and can also be started with the **Run workflow** button.

```text
push to main
    |
    v
1. test (GitHub-hosted Ubuntu runner)
   checkout -> Python 3.11 -> install dependencies -> pytest
    |
    | only if tests pass
    v
2. build-and-push (GitHub-hosted Ubuntu runner)
   derive 7-character SHA tag
   -> log in to Docker Hub
   -> build linux/amd64 + linux/arm64 image
   -> push docker.io/<user>/cicd-demo:<sha> and :latest
    |
    | immutable image reference passed as a job output
    v
3. deploy-bluegreen (self-hosted runner with access to kind)
   find live colour -> deploy image to idle colour
   -> wait for Ready pods -> point preview Service at idle colour
   -> smoke-test version and colour on port 30081
   -> switch live Service selector
   -> verify port 30080
   -> switch back to the previous colour if verification fails
```

Blue-green is the default strategy for both automatic pushes and manual runs.
For a rolling update, select `rolling` in the manual workflow input. The
rolling job applies [`k8s/deployment.yaml`](k8s/deployment.yaml), updates the
container image, waits for rollout completion, tests the live Service, and runs
`kubectl rollout undo` on failure.

The separate [`.github/workflows/blue-green.yml`](.github/workflows/blue-green.yml)
is a manual release workflow for an image that has already been built. Its
optional `image` input accepts a complete image reference; when left blank, it
releases `docker.io/<DOCKERHUB_USERNAME>/cicd-demo:latest`.

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

## Where the workflows run

| Workflow                | Runs on GitHub?                 | Needs                                             | Deploys to                               |
| ----------------------- | ------------------------------- | ------------------------------------------------- | ---------------------------------------- |
| `k8s-in-runner.yml`   | **fully, out of the box** | nothing                                           | a kind cluster created inside the runner |
| `ci-cd.yml` jobs 1–2 | yes                             | Docker Hub variable + secret                      | nothing (build + push only)              |
| `ci-cd.yml` job 3     | on a **self-hosted runner**, not GitHub's cloud | a runner registered on a machine that can reach the cluster | this repo's local kind cluster |
| `blue-green.yml`      | on the same **self-hosted runner** | an already-pushed image and the Docker Hub username variable | this repo's local kind cluster |

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
- **`maxUnavailable: 0`** — the optional rolling update never deliberately
  removes an old pod before a replacement is available.
- **`kubectl rollout status`** — turns "kubectl accepted my YAML" into "the new
  pods are actually healthy". Without it the job goes green on a broken deploy.
- **Rollback on failure** — rolling deployment uses `kubectl rollout undo`;
  blue-green deployment switches the live Service back to the previous colour.

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

4. Both deployment jobs in `ci-cd.yml` already target this runner
   (`runs-on: [self-hosted, macOS, kind]`) and run
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

# 3. For the default blue-green flow, find the live colour and running image
LIVE_COLOR=$(kubectl -n cicd-demo get svc cicd-demo-live \
  -o jsonpath='{.spec.selector.color}')
kubectl -n cicd-demo get deploy "cicd-demo-${LIVE_COLOR}" \
  -o jsonpath='{.spec.template.spec.containers[0].image}'
echo

# 4. The live app reports the same version
curl -s http://localhost:30080/api/info

# 5. Confirm the job ran on your machine, not GitHub's cloud
gh api repos/OWNER/REPO/actions/runners --jq '.runners[] | {name,status}'
```

End-to-end check for the default blue-green flow. This compares the local
commit, the live Deployment's image tag, and the version reported by the app:

```bash
GIT_VERSION=$(git rev-parse --short=7 HEAD)
LIVE_COLOR=$(kubectl -n cicd-demo get svc cicd-demo-live \
  -o jsonpath='{.spec.selector.color}')
IMAGE=$(kubectl -n cicd-demo get deploy "cicd-demo-${LIVE_COLOR}" \
  -o jsonpath='{.spec.template.spec.containers[0].image}')
IMAGE_VERSION=${IMAGE##*:}
APP_VERSION=$(curl -fsS http://localhost:30080/api/info | \
  python3 -c "import json,sys; print(json.load(sys.stdin)['version'])")

printf 'git=%s image=%s app=%s\n' "$GIT_VERSION" "$IMAGE_VERSION" "$APP_VERSION"
test "$GIT_VERSION" = "$IMAGE_VERSION" && \
  test "$IMAGE_VERSION" = "$APP_VERSION" && \
  echo "MATCH — the live pod was built from this commit"
```

For a manually selected rolling deployment, inspect `deploy/cicd-demo`
instead of `deploy/cicd-demo-${LIVE_COLOR}`.

---

## Submission checklist

The grader feedback saying that the workflow and manifests were absent normally
means those directories were not included in the submitted archive. They are
present and tracked in this repository. Confirm that Git sees them:

```bash
git ls-files .github/workflows k8s
```

After committing the final changes, create the submission archive from tracked
files instead of selecting files in Finder. This preserves the hidden `.github`
directory:

```bash
git archive --format=zip --output=cicd-pipeline-submission.zip HEAD
unzip -l cicd-pipeline-submission.zip | \
  grep -E '(\.github/workflows/ci-cd\.yml|k8s/blue-green/deployment-(blue|green)\.yaml|k8s/blue-green/service\.yaml)'
```

Before submitting, open the archive and confirm it contains at least:

```text
.github/workflows/ci-cd.yml
.github/workflows/blue-green.yml
.github/workflows/k8s-in-runner.yml
k8s/deployment.yaml
k8s/service.yaml
k8s/blue-green/deployment-blue.yaml
k8s/blue-green/deployment-green.yaml
k8s/blue-green/service.yaml
k8s/blue-green/service-preview.yaml
Dockerfile
requirements.txt
app/main.py
tests/test_main.py
```

If submission is by GitHub URL, also confirm the repository's **Actions** tab
shows the CI/CD workflow and that the files above are visible on the selected
branch. A README description is supporting evidence; the grader must receive
the actual `.github` and `k8s` files for the pipeline to be reproducible.
