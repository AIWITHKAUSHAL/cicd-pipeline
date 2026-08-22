"""
CI/CD Demo App - deliberately tiny.

The whole point of this app is to be BORING, so that in the video
100% of the attention goes to the pipeline, not to the code.

What the app exposes, and why each one exists:
  /            -> a full-screen coloured page (proves WHICH version is live)
  /api/info    -> JSON with version + colour + pod name (proves WHERE it runs)
  /api/add     -> a pure function with an edge case (something to TEST)
  /health/*    -> liveness + readiness probes (Kubernetes needs these)
"""

import os

from fastapi import FastAPI, HTTPException
from fastapi.responses import HTMLResponse

# These three come from the environment, never from code.
# APP_VERSION is stamped in by the Docker build (build arg -> ENV).
# APP_COLOR is set by the Kubernetes Deployment (blue or green).
# POD_NAME is injected by Kubernetes itself via the Downward API.
APP_VERSION = os.getenv("APP_VERSION", "dev")
APP_COLOR = os.getenv("APP_COLOR", "blue")
POD_NAME = os.getenv("POD_NAME", "local")

app = FastAPI(title="CI/CD Demo", version=APP_VERSION)

PALETTE = {
    "blue": ("#0b2545", "#4cc9f0"),
    "green": ("#0b2e1f", "#57d68d"),
}


@app.get("/api/info")
def info() -> dict:
    """Everything the video needs to prove, in one JSON object."""
    return {"version": APP_VERSION, "color": APP_COLOR, "pod": POD_NAME, "greeting": "render auto-deploy verified"}


@app.get("/api/add")
def add(a: int, b: int) -> dict:
    """A trivial endpoint that exists purely so the test job has work to do."""
    if abs(a) > 1_000_000 or abs(b) > 1_000_000:
        raise HTTPException(status_code=400, detail="numbers too large")
    return {"a": a, "b": b, "sum": a + b}


@app.get("/health/live")
def live() -> dict:
    """Liveness: 'the process is not wedged'. Failing this RESTARTS the pod."""
    return {"status": "alive"}


@app.get("/health/ready")
def ready() -> dict:
    """Readiness: 'send me traffic'. Failing this only REMOVES it from the Service."""
    return {"status": "ready"}


@app.get("/", response_class=HTMLResponse)
def home() -> str:
    bg, accent = PALETTE.get(APP_COLOR, PALETTE["blue"])
    return f"""<!doctype html>
<html><head><meta charset="utf-8"><title>CI/CD Demo</title>
<meta http-equiv="refresh" content="2">
<style>
  body {{ margin:0; height:100vh; display:flex; flex-direction:column;
         align-items:center; justify-content:center; background:{bg};
         color:#fff; font-family:ui-sans-serif,system-ui,sans-serif; }}
  .color {{ font-size:14vw; font-weight:800; color:{accent}; letter-spacing:-2px; }}
  .version {{ font-size:3vw; opacity:.9; }}
  .pod {{ margin-top:2rem; font-family:ui-monospace,monospace; font-size:1.2vw; opacity:.55; }}
</style></head>
<body>
  <div class="color">{APP_COLOR.upper()}</div>
  <div class="version">version {APP_VERSION}</div>
  <div class="pod">pod: {POD_NAME}</div>
</body></html>"""
