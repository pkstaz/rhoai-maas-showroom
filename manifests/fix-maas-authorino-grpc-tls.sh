#!/usr/bin/env bash
# Align Authorino gRPC with EnvoyFilter openshift-ai-inference-authn-ssl.
# Without this, POST /maas-api/v1/api-keys returns HTTP 500 (wasm gRPC not OK):
# Envoy talks TLS to Authorino :50051 while the Authorino listener is plaintext.
# DestinationRule tls.mode=DISABLE and EnvoyFilter MERGE→raw_buffer do NOT win.
set -euo pipefail

NS="${AUTHORINO_NAMESPACE:-kuadrant-system}"
NAME="${AUTHORINO_NAME:-authorino}"
SVC="${AUTHORINO_AUTH_SVC:-authorino-authorino-authorization}"
SECRET="${AUTHORINO_TLS_SECRET:-authorino-server-cert}"

echo "Annotating ${SVC} in ${NS} for OpenShift serving cert ${SECRET}..."
oc annotate svc "${SVC}" -n "${NS}" \
  "service.beta.openshift.io/serving-cert-secret-name=${SECRET}" --overwrite

echo "Waiting for secret ${SECRET}..."
for _ in $(seq 1 30); do
  oc get secret "${SECRET}" -n "${NS}" >/dev/null 2>&1 && break
  sleep 2
done
oc get secret "${SECRET}" -n "${NS}" >/dev/null

echo "Enabling Authorino listener TLS..."
oc patch authorino "${NAME}" -n "${NS}" --type=merge -p "{
  \"spec\": {
    \"listener\": {
      \"tls\": {
        \"enabled\": true,
        \"certSecretRef\": { \"name\": \"${SECRET}\" }
      }
    }
  }
}"

oc rollout status "deploy/${NAME}" -n "${NS}" --timeout=180s

echo "Restarting MaaS gateway so Envoy reconnects to Authorino gRPC..."
oc delete pod -n openshift-ingress \
  -l gateway.networking.k8s.io/gateway-name=maas-default-gateway --ignore-not-found
oc rollout status -n openshift-ingress deploy/maas-default-gateway-openshift-default --timeout=180s

echo "Authorino gRPC TLS enabled. Re-test POST /maas-api/v1/api-keys (expect HTTP 201)."
