#!/usr/bin/env bash
# Patch a wizard-created LLMInferenceService to use vLLM CPU (no CUDA).
# Usage:
#   bash examples/patch-llmisvc-cpu.sh [name] [namespace]
# Defaults: name=qwenqwen3-06b namespace=llm
set -euo pipefail

NAME="${1:-qwenqwen3-06b}"
NS="${2:-llm}"

echo "Patching LLMInferenceService/${NAME} in ${NS} -> vllm-cpu-rhel9:3.5.0"

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

echo "Waiting for rollout..."
oc rollout status "deploy/${NAME}-kserve" -n "${NS}" --timeout=10m || true
oc get llminferenceservice,pods -n "${NS}"
