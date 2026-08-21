# Create the local Kubernetes cluster.  Usage: .\scripts\kind-up.ps1
$ErrorActionPreference = "Stop"
kind create cluster --name cicd-demo --config k8s/kind-cluster.yaml
kubectl cluster-info --context kind-cicd-demo
kubectl apply -f k8s/namespace.yaml
Write-Host "Cluster ready. App will appear at http://localhost:30080" -ForegroundColor Green
