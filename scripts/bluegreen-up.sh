#!/usr/bin/env bash
# Stand up BOTH colours plus the live and preview Services.
# macOS/Linux twin of bluegreen-up.ps1.
#   ./scripts/bluegreen-up.sh v1 v2
set -euo pipefail

BLUE_VERSION="${1:-v1}"
GREEN_VERSION="${2:-v2}"

# The rolling-update demo's Service already owns nodePort 30080, and two
# Services cannot share one nodePort. Free it before cicd-demo-live claims it,
# otherwise kubectl fails with "provided port is already allocated".
if kubectl -n cicd-demo get svc cicd-demo >/dev/null 2>&1; then
  echo "Releasing nodePort 30080 from the rolling-update Service..."
  kubectl -n cicd-demo delete svc cicd-demo
fi

# Build one image per colour and side-load it into kind. No registry, no
# push, no network - kind reads the image straight out of the Docker daemon.
for pair in "blue:${BLUE_VERSION}" "green:${GREEN_VERSION}"; do
  color="${pair%%:*}"; ver="${pair##*:}"; image="cicd-demo:${ver}"
  docker build --build-arg "APP_VERSION=${ver}" -t "${image}" .
  kind load docker-image "${image}" --name cicd-demo
  sed "s|IMAGE_PLACEHOLDER|${image}|" "k8s/blue-green/deployment-${color}.yaml" | kubectl apply -f -
  # set image too, so re-running with a new version actually rolls the pods.
  kubectl -n cicd-demo set image "deploy/cicd-demo-${color}" "api=${image}"
done

kubectl apply -f k8s/blue-green/service.yaml
kubectl apply -f k8s/blue-green/service-preview.yaml

kubectl -n cicd-demo rollout status deploy/cicd-demo-blue  --timeout=120s
kubectl -n cicd-demo rollout status deploy/cicd-demo-green --timeout=120s

echo
echo "LIVE    -> http://localhost:30080  (currently blue)"
echo "PREVIEW -> http://localhost:30081  (always green)"
