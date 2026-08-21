# Build the image locally and run the ROLLING UPDATE version in kind.
#   .\scripts\deploy-local.ps1 -Version v1
param([string]$Version = "v1")
$ErrorActionPreference = "Stop"

$image = "cicd-demo:$Version"
docker build --build-arg APP_VERSION=$Version -t $image .
kind load docker-image $image --name cicd-demo    # kind has its own image store

kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/service.yaml
(Get-Content k8s/deployment.yaml) -replace "IMAGE_PLACEHOLDER", $image | kubectl apply -f -
kubectl -n cicd-demo set image deploy/cicd-demo api=$image
kubectl -n cicd-demo rollout status deploy/cicd-demo
Write-Host "Open http://localhost:30080" -ForegroundColor Green
