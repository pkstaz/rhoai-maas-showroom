#!/usr/bin/env bash
# MinIO + DataSciencePipelinesApplication in llm (AutoML / AutoRAG).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

oc get ns llm >/dev/null

echo "=== Dashboard AutoML + AutoRAG ==="
oc patch odhdashboardconfig odh-dashboard-config -n redhat-ods-applications --type merge -p '{
  "spec":{"dashboardConfig":{"automl":true,"autorag":true,"genAiStudio":true,"externalVectorStores":true}}
}'

echo "=== MinIO + DSPA ==="
oc apply -k manifests/pipelines
oc rollout status deploy/pipeline-minio -n llm --timeout=180s || true
oc wait -n llm --for=condition=complete job/pipeline-minio-buckets --timeout=180s || \
  oc logs -n llm job/pipeline-minio-buckets || true

echo "Waiting DSPA pods..."
for i in $(seq 1 36); do
  n=$(oc get pods -n llm --no-headers 2>/dev/null | grep -ci pipeline || true)
  echo "try $i pipeline-ish pods=$n"
  oc get dspa dspa -n llm -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}{"\n"}' 2>/dev/null || true
  sleep 8
done

oc get dspa,pods -n llm | head -40
echo "UI: Develop & train → AutoML / Gen AI studio → AutoRAG (proyecto llm)"
