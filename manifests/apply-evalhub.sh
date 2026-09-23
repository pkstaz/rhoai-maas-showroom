#!/usr/bin/env bash
# Enable TrustyAI + MLflow + EvalHub (lm-eval, Garak, garak-kfp) for Evaluations.
# Order matters: MLflow CR must be Ready before EvalHub (RHOAIENG-67534).
# Usage: bash manifests/apply-evalhub.sh
set -euo pipefail

export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:${PATH:-}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

DSP_NS="${DSP_NS:-llm}"

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

echo "=== 3. MLflow instance (sqlite + PVC lab) — BEFORE EvalHub ==="
oc apply -f manifests/evalhub/mlflow.yaml

echo "Waiting MLflow pods..."
for i in $(seq 1 36); do
  R=$(oc get deploy -n redhat-ods-applications -l app.kubernetes.io/name=mlflow -o jsonpath='{.items[0].status.readyReplicas}' 2>/dev/null || true)
  echo "try $i mlflow readyReplicas=$R"
  [[ "$R" == "1" ]] && break
  oc get pods -n redhat-ods-applications 2>/dev/null | grep -i mlflow | head -5 || true
  sleep 10
done

# Discover service + static-prefix /mlflow (required for workspaces_enabled=true)
MLFLOW_HOST=$(oc get svc mlflow -n redhat-ods-applications -o jsonpath='{.metadata.name}' 2>/dev/null || echo mlflow)
MLFLOW_PORT=$(oc get svc mlflow -n redhat-ods-applications -o jsonpath='{.spec.ports[0].port}' 2>/dev/null || echo 8443)
MLFLOW_SCHEME=https
[[ "$MLFLOW_PORT" == "8080" || "$MLFLOW_PORT" == "5000" ]] && MLFLOW_SCHEME=http
MLFLOW_URI="${MLFLOW_SCHEME}://${MLFLOW_HOST}.redhat-ods-applications.svc.cluster.local:${MLFLOW_PORT}/mlflow"
echo "MLFLOW_TRACKING_URI=${MLFLOW_URI}"
echo "MLFLOW_WORKSPACE=${DSP_NS}"

echo "=== 4. EvalHub namespace + Postgres + CR ==="
oc apply -k manifests/evalhub

oc patch evalhub evalhub -n evalhub --type=merge -p "{
  \"spec\": {
    \"env\": [
      {\"name\": \"MLFLOW_TRACKING_URI\", \"value\": \"${MLFLOW_URI}\"},
      {\"name\": \"MLFLOW_WORKSPACE\", \"value\": \"${DSP_NS}\"}
    ]
  }
}" 2>/dev/null || true

echo "=== 5. RBAC + tenant label: EvalHub SA → MLflow workspace ${DSP_NS} ==="
# Dashboard Evaluations discovers EvalHub via ConfigMap evalhub-discovery in the
# selected DSP. TrustyAI only injects it into namespaces with this tenant label.
if oc get ns "${DSP_NS}" >/dev/null 2>&1; then
  oc label ns "${DSP_NS}" evalhub.trustyai.opendatahub.io/tenant=true --overwrite
fi

# roleRef is immutable: recreate the RoleBinding if it already exists with another ref.
ensure_mlflow_workspace_rbac() {
  local ns="$1"
  local rb="evalhub-mlflow-workspace-${ns}"
  if oc get rolebinding "${rb}" -n "${ns}" >/dev/null 2>&1; then
    local kind name
    kind=$(oc get rolebinding "${rb}" -n "${ns}" -o jsonpath='{.roleRef.kind}')
    name=$(oc get rolebinding "${rb}" -n "${ns}" -o jsonpath='{.roleRef.name}')
    if [[ "${kind}/${name}" != "ClusterRole/edit" ]]; then
      echo "Recreating ${rb} (roleRef was ${kind}/${name}, need ClusterRole/edit)"
      oc delete rolebinding "${rb}" -n "${ns}"
    fi
  fi
}

if [[ "${DSP_NS}" == "llm" ]] && oc get ns llm >/dev/null 2>&1; then
  ensure_mlflow_workspace_rbac llm
  oc apply -f manifests/evalhub/mlflow-workspace-rbac.yaml
elif oc get ns "${DSP_NS}" >/dev/null 2>&1; then
  ensure_mlflow_workspace_rbac "${DSP_NS}"
  oc -n "${DSP_NS}" create rolebinding "evalhub-mlflow-workspace-${DSP_NS}" \
    --clusterrole=edit \
    --serviceaccount=evalhub:evalhub-service \
    --dry-run=client -o yaml | oc apply -f -
else
  echo "WARN: namespace ${DSP_NS} missing — create the DSP first, then:"
  echo "  oc label ns ${DSP_NS} evalhub.trustyai.opendatahub.io/tenant=true --overwrite"
  echo "  oc apply -f manifests/evalhub/mlflow-workspace-rbac.yaml"
fi

echo "Waiting for evalhub-discovery ConfigMap in ${DSP_NS}..."
for i in $(seq 1 24); do
  if oc get cm evalhub-discovery -n "${DSP_NS}" >/dev/null 2>&1; then
    echo "OK: evalhub-discovery in ${DSP_NS}"
    oc get cm evalhub-discovery -n "${DSP_NS}" -o jsonpath='{.data}{"\n"}' 2>/dev/null || true
    break
  fi
  echo "try $i: waiting for tenant reconcile..."
  sleep 5
done

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
oc get mlflow mlflow -o jsonpath='{.status.conditions[?(@.type=="Available")].status}{"\n"}' 2>/dev/null || true
echo
echo "UI: hard-refresh dashboard → Develop & train → Evaluations"
echo "Create an MLflow experiment in project ${DSP_NS}, then Start evaluation run."
