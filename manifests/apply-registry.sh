#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
oc apply -k manifests/registry
oc rollout status deploy/model-registry-db -n rhoai-model-registries --timeout=180s || true
for i in $(seq 1 24); do
  ph=$(oc get modelregistry workshop -n rhoai-model-registries -o jsonpath='{.status.conditions[?(@.type=="Available")].status}' 2>/dev/null || true)
  echo "try $i ModelRegistry Available=$ph"
  [[ "$ph" == "True" ]] && break
  sleep 8
done
oc get modelregistry,pods -n rhoai-model-registries
echo "Dashboard → AI hub → Registry"
