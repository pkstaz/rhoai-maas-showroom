#!/usr/bin/env bash
# Enable TrustyAI + MLflow + EvalHub so Develop & train → Evaluations works in the UI.
# Usage: bash examples/apply-evalhub.sh
set -euo pipefail

export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:${PATH:-}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

echo "=== 1. TrustyAI + MLflow operators on DataScienceCluster ==="
oc patch datasciencecluster default-dsc --type=merge -p '{
  "spec": {
    "components": {
      "trustyai": {"managementState": "Managed"},
      "mlflowoperator": {"managementState": "Managed"}
    }
  }
}'

echo "Waiting TrustyAIReady / MLflowOperatorReady..."
for i in $(seq 1 48); do
  T=$(oc get dsc default-dsc -o jsonpath='{.status.conditions[?(@.type=="TrustyAIReady")].status}' 2>/dev/null || true)
  M=$(oc get dsc default-dsc -o jsonpath='{.status.conditions[?(@.type=="MLflowOperatorReady")].status}' 2>/dev/null || true)
  echo "try $i TrustyAIReady=$T MLflowOperatorReady=$M"
  [[ "$T" == "True" && "$M" == "True" ]] && break
  sleep 10
done

echo "=== 2. Dashboard: Evaluations + Gen AI Studio ==="
oc patch odhdashboardconfig odh-dashboard-config -n redhat-ods-applications --type=merge -p '{
  "spec": {
    "dashboardConfig": {
      "disableLMEval": false,
      "genAiStudio": true
    }
  }
}'

echo "=== 3. MLflow instance (sqlite + PVC lab) ==="
oc apply -f examples/evalhub/mlflow.yaml

echo "Waiting MLflow pods..."
for i in $(seq 1 36); do
  R=$(oc get deploy -n redhat-ods-applications -l app.kubernetes.io/name=mlflow -o jsonpath='{.items[0].status.readyReplicas}' 2>/dev/null || true)
  echo "try $i mlflow readyReplicas=$R"
  [[ "$R" == "1" ]] && break
  oc get pods -n redhat-ods-applications 2>/dev/null | grep -i mlflow | head -5 || true
  sleep 10
done

# Discover service port for EvalHub env
MLFLOW_HOST=$(oc get svc mlflow -n redhat-ods-applications -o jsonpath='{.metadata.name}' 2>/dev/null || echo mlflow)
MLFLOW_PORT=$(oc get svc mlflow -n redhat-ods-applications -o jsonpath='{.spec.ports[0].port}' 2>/dev/null || echo 8443)
MLFLOW_SCHEME=https
[[ "$MLFLOW_PORT" == "8080" || "$MLFLOW_PORT" == "5000" ]] && MLFLOW_SCHEME=http
MLFLOW_URI="${MLFLOW_SCHEME}://${MLFLOW_HOST}.redhat-ods-applications.svc.cluster.local:${MLFLOW_PORT}"
echo "MLFLOW_TRACKING_URI=${MLFLOW_URI}"

echo "=== 4. EvalHub namespace + Postgres + CR ==="
oc apply -k examples/evalhub

# Ensure EvalHub points at discovered MLflow URI
oc patch evalhub evalhub -n evalhub --type=merge -p "{
  \"spec\": {
    \"env\": [
      {\"name\": \"MLFLOW_TRACKING_URI\", \"value\": \"${MLFLOW_URI}\"}
    ]
  }
}" 2>/dev/null || true

echo "Waiting Postgres + EvalHub..."
oc rollout status deploy/evalhub-postgres -n evalhub --timeout=300s || true
for i in $(seq 1 36); do
  READY=$(oc get pods -n evalhub -l app=eval-hub --no-headers 2>/dev/null | awk '{print $2,$3}' | head -1)
  echo "try $i evalhub=[$READY]"
  echo "$READY" | grep -q '1/1 Running\|2/2 Running' && break
  oc get pods -n evalhub --no-headers 2>/dev/null | head -8 || true
  sleep 10
done

oc get evalhub,pods,route -n evalhub 2>/dev/null || oc get pods -n evalhub
oc get mlflow mlflow -o jsonpath='{.status.phase}{"\n"}' 2>/dev/null || true
echo
echo "UI: hard-refresh dashboard → Develop & train → Evaluations"
echo "Create an MLflow experiment first (Develop & train → Experiments), then Start evaluation run."
