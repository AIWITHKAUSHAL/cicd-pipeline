# ---------------------------------------------------------------------------
# One instruction per concept - read this file top to bottom on the video.
# ---------------------------------------------------------------------------

# 1. Base image: slim = Debian with Python, no compilers, no extras.
FROM python:3.11-slim

# 2. Build arg -> ENV. The pipeline passes the git SHA in here, so the
#    running container can tell you exactly which commit built it.
ARG APP_VERSION=dev
ENV APP_VERSION=${APP_VERSION} \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

# 3. Copy requirements FIRST, install, then copy code.
#    Layer caching: code changes every commit, dependencies almost never.
#    Doing it in this order means a code-only change reuses the pip layer.
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# 4. Now the code.
COPY app ./app

# 5. Never run as root. If the container is compromised, uid 1000 owns nothing.
RUN useradd --create-home --uid 1000 appuser
USER appuser

EXPOSE 8000

# 6. Exec form (JSON array), not shell form, so uvicorn is PID 1 and
#    receives SIGTERM directly when Kubernetes drains the pod.
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
