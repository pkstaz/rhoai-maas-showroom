#!/usr/bin/env bash
# Wire real-GPU DCGM utilization into the RHOAI Perses "GPU utilization" panel.
# Idempotent. Re-run if MonitoringStack / DSCI monitoring is recreated.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# MonitoringStack (prometheus.monitoring.rhobs) ignores monitoring.coreos.com ServiceMonitors.
oc delete servicemonitor.monitoring.coreos.com nvidia-dcgm-gpu-util -n redhat-ods-monitoring --ignore-not-found
oc delete prometheusrule.monitoring.coreos.com accelerator-gpu-utilization -n redhat-ods-monitoring --ignore-not-found
oc apply -f "${ROOT}/manifests/observability/gpu-utilization/"

echo "Waiting for DCGM_FI_DEV_GPU_UTIL (or recording rule) in data-science Prometheus..."
THANOS_HOST=$(oc get route data-science-thanos-querier-route -n redhat-ods-monitoring -o jsonpath='{.spec.host}')
TOKEN=$(oc whoami -t)
ok=0
for _ in $(seq 1 24); do
  n=$(curl -sk -G -H "Authorization: Bearer ${TOKEN}" \
    --data-urlencode 'query=count(accelerator_gpu_utilization)' \
    "https://${THANOS_HOST}/api/v1/query" | python3 -c '
import json,sys
d=json.load(sys.stdin)
res=(d.get("data") or {}).get("result") or []
print(res[0]["value"][1] if res else "0")
' 2>/dev/null || echo 0)
  if [[ "${n}" != "0" ]]; then
    echo "accelerator_gpu_utilization series: ${n}"
    ok=1
    break
  fi
  sleep 5
done
if [[ "${ok}" != "1" ]]; then
  echo "WARN: recording rule not visible yet. Generate chat traffic on gpt-oss, wait ~1 min, refresh Observe & monitor."
  echo "Check: oc get servicemonitor,prometheusrule -n redhat-ods-monitoring | grep -E 'dcgm|accelerator'"
fi
echo "Done. Filter the utilization dashboard to the CUDA model (not Qwen CPU)."
