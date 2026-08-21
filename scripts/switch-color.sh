#!/usr/bin/env bash
# Same as switch-color.ps1, for Linux/macOS students.
set -euo pipefail
LIVE=$(kubectl -n cicd-demo get svc cicd-demo-live -o jsonpath='{.spec.selector.color}')
TO=${1:-$([ "$LIVE" = "blue" ] && echo green || echo blue)}
echo "live=$LIVE -> switching to $TO"
kubectl -n cicd-demo patch svc cicd-demo-live \
  -p "{\"spec\":{\"selector\":{\"app\":\"cicd-demo\",\"color\":\"$TO\"}}}"
