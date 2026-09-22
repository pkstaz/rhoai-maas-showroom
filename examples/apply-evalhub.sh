#!/usr/bin/env bash
# Enable TrustyAI + deploy workshop EvalHub (Postgres + EvalHub CR).
# Usage: bash examples/apply-evalhub.sh
set -euo pipefail

export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:${PATH:-}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

echo "=== 1. TrustyAI Managed on DataScienceCluster ==="
oc patch datasciencecluster default-dsc --type=merge \
  -p '{"spec":{"components":{"trustyai":{"managementState":"Managed"}}}}'

echo "Waiting TrustyAIReady..."
for i in $(seq 1 36); do
  ST=$(oc get dsc default-dsc -o jsonpath='{.status.conditions[?(@.type=="TrustyAIReady")].status}' 2>/dev/null || true)
  echo "try $i TrustyAIReady=$ST"
  [[ "$ST" == "True" ]] && break
  sleep 10
done

echo "=== 2. Show Evaluations in dashboard ==="
oc patch odhdashboardconfig odh-dashboard-config -n redhat-ods-applications --type=merge -p '{
  "spec": {
    "dashboardConfig": {
      "disableEvalHub": false,
      "genAiStudio": true
    }
  }
}'

echo "=== 3. EvalHub namespace + Postgres + CR ==="
oc apply -k examples/evalhub

echo "Waiting Postgres ready..."
oc rollout status deploy/evalhub-postgres -n evalhub --timeout=300s

echo "Waiting EvalHub pods..."
for i in $(seq 1 36); do
  READY=$(oc get pods -n evalhub -l app=eval-hub --no-headers 2>/dev/null | awk '{print $2,$3}' | head -1)
  echo "try $i pods=[$READY]"
  echo "$READY" | grep -q '1/1 Running' && break
  # label may vary
  oc get pods -n evalhub --no-headers 2>/dev/null | grep -i eval | head -5 || true
  sleep 10
done

oc get evalhub,pods,route -n evalhub 2>/dev/null || oc get pods -n evalhub
echo "Done. Continue with module 12 smoke eval (API/CLI)."
