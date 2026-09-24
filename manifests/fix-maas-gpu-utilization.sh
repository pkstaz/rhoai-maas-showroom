#!/usr/bin/env bash
# Wire real-GPU DCGM utilization into RHOAI Perses GPU panels.
# Observe cluster/model dashboards query cluster Prometheus; LLM-d utilization
# queries the RHOAI MonitoringStack. Idempotent.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# MonitoringStack (prometheus.monitoring.rhobs) ignores monitoring.coreos.com ServiceMonitors.
oc delete servicemonitor.monitoring.coreos.com nvidia-dcgm-gpu-util -n redhat-ods-monitoring --ignore-not-found
oc delete prometheusrule.monitoring.coreos.com accelerator-gpu-utilization -n redhat-ods-monitoring --ignore-not-found
oc apply -f "${ROOT}/manifests/observability/gpu-utilization/"

query_count() {
  local host="$1"
  local token="$2"
  curl -sk -G -H "Authorization: Bearer ${token}" \
    --data-urlencode 'query=count(accelerator_gpu_utilization)' \
    "https://${host}/api/v1/query" | python3 -c '
import json,sys
d=json.load(sys.stdin)
res=(d.get("data") or {}).get("result") or []
print(res[0]["value"][1] if res else "0")
' 2>/dev/null || echo 0
}

TOKEN=$(oc whoami -t)
CLUSTER_THANOS=$(oc get route thanos-querier -n openshift-monitoring -o jsonpath='{.spec.host}')
DS_THANOS=$(oc get route data-science-thanos-querier-route -n redhat-ods-monitoring -o jsonpath='{.spec.host}')

echo "Waiting for accelerator_gpu_utilization on cluster Thanos (Observe GPU panels)..."
ok_cluster=0
for _ in $(seq 1 24); do
  n=$(query_count "${CLUSTER_THANOS}" "${TOKEN}")
  if [[ "${n}" != "0" ]]; then
    echo "cluster accelerator_gpu_utilization series: ${n}"
    ok_cluster=1
    break
  fi
  sleep 5
done

echo "Waiting for accelerator_gpu_utilization on data-science Thanos (LLM-d utilization)..."
ok_ds=0
for _ in $(seq 1 12); do
  n=$(query_count "${DS_THANOS}" "${TOKEN}")
  if [[ "${n}" != "0" ]]; then
    echo "data-science accelerator_gpu_utilization series: ${n}"
    ok_ds=1
    break
  fi
  sleep 5
done

if [[ "${ok_cluster}" != "1" ]]; then
  echo "WARN: cluster recording rule not visible yet."
  echo "Check: oc get prometheusrule nvidia-dcgm-accelerator -n nvidia-gpu-operator"
fi
if [[ "${ok_ds}" != "1" ]]; then
  echo "WARN: RHOBS recording rule not visible yet."
  echo "Check: oc get servicemonitor,prometheusrule -n redhat-ods-monitoring | grep -E 'dcgm|accelerator'"
fi
echo "Done. Filter model dashboards to the CUDA model (not Qwen CPU). Idle L4 is 0%."
