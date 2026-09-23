#!/usr/bin/env bash
# MCP Lifecycle Operator + OpenShift MCP server + Playground ConfigMap.
# Docs: MCP operator wants OpenShift 4.22+. On 4.20 the CRD may be missing —
# the script falls back to a plain Deployment.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

echo "=== mcplifecycleoperator Managed ==="
oc patch dsc default-dsc --type=merge -p '{
  "spec":{"components":{"mcplifecycleoperator":{"managementState":"Managed"}}}
}' || echo "WARN: patch mcplifecycleoperator failed (field may not exist on this DSC CRD)"

echo "=== Dashboard mcpCatalog ==="
oc patch odhdashboardconfig odh-dashboard-config -n redhat-ods-applications --type merge -p '{
  "spec":{"dashboardConfig":{"mcpCatalog":true,"mcpRegistry":true,"genAiStudio":true}}
}'

oc apply -f manifests/mcp/rbac.yaml

if oc get crd mcpservers.mcp.x-k8s.io >/dev/null 2>&1; then
  echo "=== MCPServer openshift-mcp ==="
  oc apply -f manifests/mcp/mcpserver.yaml
else
  echo "WARN: CRD MCPServer missing — Deployment fallback"
  oc apply -f manifests/mcp/deployment-fallback.yaml
fi

oc apply -f manifests/mcp/playground-cm.yaml
echo "Hard refresh dashboard → AI hub → MCP servers / Gen AI studio → AI asset endpoints → MCPs"
