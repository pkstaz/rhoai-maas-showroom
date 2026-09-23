#!/usr/bin/env bash
# Patch a wizard-created LLMInferenceService to use vLLM CPU (no CUDA).
# Always Stop → patch → Start; editing a running service leaves pods Pending.
# Usage:
#   bash manifests/patch-llmisvc-cpu.sh [name] [namespace]
# Defaults: name=qwenqwen3-06b namespace=llm
set -euo pipefail

NAME="${1:-qwenqwen3-06b}"
NS="${2:-llm}"

echo "=== Stop LLMInferenceService/${NAME} (replicas=0) ==="
oc patch llminferenceservice "${NAME}" -n "${NS}" --type=merge \
  -p '{"spec":{"replicas":0}}'
oc wait --for=delete pod -n "${NS}" -l "app.kubernetes.io/name=${NAME}" \
  --timeout=180s 2>/dev/null || true
# Also clear leftover kserve pods if labels differ
oc delete pod -n "${NS}" -l "serving.kserve.io/inferenceservice=${NAME}" \
  --wait=false --ignore-not-found 2>/dev/null || true
sleep 5
oc get pods -n "${NS}" || true

echo "=== Patch image/env/args -> vllm-cpu-rhel9:3.5.0 ==="
oc patch llminferenceservice "${NAME}" -n "${NS}" --type=merge -p '{
  "spec": {
    "template": {
      "containers": [{
        "name": "main",
        "image": "registry.redhat.io/rhaiis/vllm-cpu-rhel9:3.5.0",
        "command": ["python", "-m", "vllm.entrypoints.openai.api_server"],
        "args": [
          "--served-model-name={{.Name}}",
          "--model=/mnt/models",
          "--max-model-len=2048",
          "--enable-ssl-refresh",
          "--ssl-certfile=/var/run/kserve/tls/tls.crt",
          "--ssl-keyfile=/var/run/kserve/tls/tls.key",
          "--enable-force-include-usage"
        ],
        "env": [
          {"name": "HF_HOME", "value": "/tmp/hf_home"},
          {"name": "HF_HUB_DISABLE_XET", "value": "1"},
          {"name": "VLLM_CPU_KVCACHE_SPACE", "value": "4"}
        ],
        "resources": {
          "requests": {"cpu": "1", "memory": "8Gi"},
          "limits": {"cpu": "2", "memory": "8Gi"}
        }
      }]
    }
  }
}'

echo "=== Start LLMInferenceService/${NAME} (replicas=1) ==="
oc patch llminferenceservice "${NAME}" -n "${NS}" --type=merge \
  -p '{"spec":{"replicas":1}}'

echo "Waiting for rollout..."
oc rollout status "deploy/${NAME}-kserve" -n "${NS}" --timeout=10m || true
oc get llminferenceservice,pods -n "${NS}"
oc get deploy -n "${NS}" -o custom-columns=\
'NAME:.metadata.name,IMAGE:.spec.template.spec.containers[0].image' 2>/dev/null || true
