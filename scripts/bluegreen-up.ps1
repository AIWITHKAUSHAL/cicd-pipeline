# Stand up BOTH colours plus the live and preview Services.
#   .\scripts\bluegreen-up.ps1 -BlueVersion v1 -GreenVersion v2
param([string]$BlueVersion = "v1", [string]$GreenVersion = "v2")
$ErrorActionPreference = "Stop"

foreach ($pair in @(@("blue", $BlueVersion), @("green", $GreenVersion))) {
    $color = $pair[0]; $ver = $pair[1]; $image = "cicd-demo:$ver"
    docker build --build-arg APP_VERSION=$ver -t $image .
    kind load docker-image $image --name cicd-demo
    (Get-Content "k8s/blue-green/deployment-$color.yaml") -replace "IMAGE_PLACEHOLDER", $image | kubectl apply -f -
    kubectl -n cicd-demo set image "deploy/cicd-demo-$color" api=$image
}
kubectl apply -f k8s/blue-green/service.yaml
kubectl apply -f k8s/blue-green/service-preview.yaml
kubectl -n cicd-demo rollout status deploy/cicd-demo-blue
kubectl -n cicd-demo rollout status deploy/cicd-demo-green
Write-Host "LIVE    -> http://localhost:30080  (currently blue)" -ForegroundColor Cyan
Write-Host "PREVIEW -> http://localhost:30081  (always green)"    -ForegroundColor Green
