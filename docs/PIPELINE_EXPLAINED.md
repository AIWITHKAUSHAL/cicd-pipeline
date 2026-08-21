# Every concept, in the order you should teach it

Use this as your speaking notes. Each section is one idea, one screen.

## 1. CI vs CD (60 seconds, no slides)
- **CI (Continuous Integration):** every push is automatically built and tested.
  Answers *"did I break anything?"*
- **CD (Continuous Delivery):** every good build is automatically packaged and
  ready to ship. Answers *"is it releasable?"*
- **CD (Continuous Deployment):** it actually ships, with no human clicking.
  Answers *"is it live?"*
- Our pipeline does all three. The line where delivery becomes deployment is the
  `deploy` job — and the `environment: production` key is where you'd put a
  human approval if you wanted delivery only.

## 2. The vocabulary of GitHub Actions
| Term | In our file | One-line meaning |
|---|---|---|
| Workflow | `ci-cd.yml` | one YAML file = one pipeline |
| Event / trigger | `on: push` | what starts it |
| Job | `test`, `build-and-push`, `deploy` | runs on its own fresh machine |
| Step | `- uses: actions/checkout@v4` | one command or one action |
| Runner | `runs-on: ubuntu-latest` | the throwaway VM |
| Action | `docker/login-action@v3` | reusable step someone else wrote |
| Secret | `${{ secrets.DOCKERHUB_TOKEN }}` | encrypted value, masked in logs |

Key point students miss: **jobs do not share a filesystem.** Each one starts
empty, which is why every job repeats `actions/checkout`.

## 3. Testing (job 1)
- Tests run on the runner, not in Docker — fastest possible failure.
- `cache: pip` keeps dependency installs off the critical path.
- Demo: push a commit that breaks `add()`, watch the pipeline stop at job 1 and
  the image never appear on Docker Hub.

## 4. Docker build (job 2)
- **Layer caching / instruction order:** `COPY requirements.txt` → `pip install`
  → `COPY app`. Reversing those two makes every commit reinstall FastAPI.
- **Build arg → ENV:** `--build-arg APP_VERSION=<sha>` bakes the commit into the
  image, so `/api/info` can tell you exactly what is running.
- **Non-root user:** `USER appuser`.
- **Exec-form CMD:** uvicorn is PID 1 and gets `SIGTERM` for a clean shutdown.
- **`cache-from: type=gha`:** layer cache that survives between workflow runs.

## 5. Image push (job 2 continued)
- Log in with an **access token**, not a password (revocable, scoped).
- Two tags, on purpose:
  - `:a1b2c3d` — immutable, exactly one commit. **This is what Kubernetes gets.**
  - `:latest` — a moving pointer, human convenience only.
- Ask the class: *if the Deployment says `:latest`, what does "roll back" even
  mean?* (Nothing — you cannot name the previous image.)

## 6. Kubernetes deployment (job 3)
- `kubectl apply` = declarative; `kubectl set image` = the one imperative line
  that swaps the tag.
- `IMAGE_PLACEHOLDER` in the YAML: manifests stay in git without a hardcoded tag.
- `rollout status --timeout=120s` — this is what makes CD *safe*. Without it the
  job goes green as soon as the API server accepts the object, even if every new
  pod is crash-looping.
- `readinessProbe` is what `rollout status` is really watching.
- `if: failure()` → `rollout undo` = automatic rollback.

## 7. Rolling update vs Blue-Green (the bonus)
| | Rolling update | Blue-Green |
|---|---|---|
| Versions live at once | both, mixed | both, but only one gets traffic |
| Switch | gradual, pod by pod | instant, one label |
| Rollback | another rollout (minutes) | flip the label back (seconds) |
| Cost | 1x capacity + surge | **2x capacity** |
| Test before users | no | yes, via the preview Service |

The mechanism is one label. `Service.spec.selector.color` decides everything:

```
        cicd-demo-live  (selector: color=blue)  ->  blue pods   <- real users
        cicd-demo-preview (selector: color=green) -> green pods <- only you
```

`kubectl patch svc ... color=green` moves every user in one API call, because a
Service selector is re-evaluated continuously by the endpoints controller.

## 8. What to say about limitations (ends the video well)
- 2x pods means 2x cost — nobody runs blue-green for a background worker.
- In-flight requests on blue are **not** drained by the switch; production
  systems pair this with connection draining.
- Database migrations do not switch with a label. Blue-green only works cleanly
  when the schema is backward-compatible with both colours.
- A GitHub-hosted runner cannot reach a laptop cluster — say this plainly rather
  than faking it.

## 9. Where does each piece actually execute? (ask this before recording)
Students get confused about *where* things run. One table fixes it:

| Piece | Where it runs | Needs credentials? |
|---|---|---|
| pytest | on the runner VM | no |
| `docker build` | on the runner (Docker is preinstalled) | no |
| `docker push` | runner → Docker Hub over the internet | yes, token |
| `kubectl ...` | runner → **whatever cluster the kubeconfig points at** | yes, kubeconfig |
| kind cluster in `k8s-in-runner.yml` | inside the runner VM itself | no |

The one rule to state plainly: **the runner is a fresh VM in GitHub's data
centre.** It can reach anything on the public internet, and nothing on your
laptop. That is why `k8s-in-runner.yml` builds its cluster locally instead of
connecting to yours — and why the real `ci-cd.yml` deploy job needs either a
cloud cluster or a self-hosted runner.
