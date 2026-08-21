# YouTube script — Complete CI/CD Pipeline (target 18–22 min)

Recording setup: browser (GitHub repo + Docker Hub) on the left, terminal on the
right, `http://localhost:30080` in a third tab. Font size 16+.

**00:00 — The promise (45s)**
Show the coloured page. "By the end of this video, I push one commit and this
page changes by itself — tested, built, pushed and deployed, no human." Show the
Actions tab with a green run.

**00:45 — The app, fast (2 min)**
`app/main.py` end to end. Emphasise it is deliberately trivial. Point out the
three env vars and where each one comes from (build, manifest, Kubernetes).

**02:45 — Tests (2 min)**
Run `pytest -v` locally. Explain: this exact command is job 1. Break `add()`
on purpose, run again, red.

**04:45 — Dockerfile (3 min)**
Read it top to bottom. Spend most time on layer-cache ordering — rebuild twice
to show `CACHED` in the output. Then non-root and exec-form CMD.

**07:45 — Chapter: the workflow file (4 min)**
Open `ci-cd.yml`. Vocabulary table from PIPELINE_EXPLAINED §2. Then walk the
three jobs, stressing `needs:` and "each job is a fresh machine".

**11:45 — Secrets (1.5 min)**
Settings → Secrets. Create the Docker Hub token live. Show a secret being masked
as `***` in an old log.

**13:15 — The live run (3 min)**
Change a string in the app, commit, push. Narrate the run as it goes: tests →
build → push. Refresh Docker Hub, show the SHA tag appear. `kubectl get pods -w`
in the terminal as the new pods roll in. Refresh the browser: new version.

**16:15 — Failure and rollback (1.5 min)**
Push a broken test. Pipeline stops at job 1. State the payoff: "the broken image
does not exist, so it cannot be deployed."

**17:15 — Everything running on GitHub itself (1.5 min)**
Open the `E2E (Kubernetes inside the runner)` run. Scroll the log: pytest,
docker build, a kind cluster booting *inside* the runner, rollout status, the
curl output showing `{"version": ..., "color": "blue"}`, then the switch to
green and the rollback. Say the rule: the runner is a VM in GitHub's data
centre — it reaches the internet, never your laptop.

**18:45 — BONUS: blue-green live (3.5 min)**
`.\scripts\bluegreen-up.ps1`. Two tabs: 30080 blue (users), 30081 green (you).
`kubectl get pods -L color`. Then `.\scripts\switch-color.ps1` — 30080 turns
green mid-sentence. Immediately roll back with `-To blue`. Show the one-line
diff in `kubectl get svc cicd-demo-live -o yaml`.

**22:15 — Limits and close (1 min)**
2x cost, in-flight requests, database migrations, and the honest note about
GitHub-hosted runners not reaching a laptop cluster. Repo link, subscribe.

## Chapter markers to paste in the description
```
00:00 What we are building
00:45 The demo app
02:45 Automated testing
04:45 The Dockerfile, layer by layer
07:45 GitHub Actions: workflow, jobs, steps, runners
11:45 Secrets and Docker Hub tokens
13:15 One push, all the way to Kubernetes
16:15 When tests fail: the pipeline stops
17:15 Running the whole pipeline on GitHub (no cluster needed)
18:45 BONUS: Blue-Green deployment and instant rollback
22:15 Limitations you should know
```
