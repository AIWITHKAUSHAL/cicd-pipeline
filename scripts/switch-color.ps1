# THE money shot for the video: flip 100% of live traffic in one command.
#   .\scripts\switch-color.ps1            -> switch to whichever colour is idle
#   .\scripts\switch-color.ps1 -To blue   -> force a colour (this is a rollback)
param([ValidateSet("blue","green","")] [string]$To = "")
$ErrorActionPreference = "Stop"

$live = kubectl -n cicd-demo get svc cicd-demo-live -o jsonpath="{.spec.selector.color}"
if ($To -eq "") { $To = if ($live -eq "blue") { "green" } else { "blue" } }
Write-Host "live=$live  ->  switching to $To"

$patch = '{"spec":{"selector":{"app":"cicd-demo","color":"' + $To + '"}}}'
kubectl -n cicd-demo patch svc cicd-demo-live -p $patch
kubectl -n cicd-demo get svc cicd-demo-live -o jsonpath="{.spec.selector}"
Write-Host "`nRefresh http://localhost:30080 - the page is now $To." -ForegroundColor Green
