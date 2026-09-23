#!/usr/bin/env bash
# Mount OpenShift service-CA into Authorino so it can validate API keys
# against maas-api (HTTPS :8443). Without this, /v1/models and chat return
# AUTH_FAILURE / "Exception thrown while generating token".
set -euo pipefail

NS="${AUTHORINO_NAMESPACE:-kuadrant-system}"
NAME="${AUTHORINO_NAME:-authorino}"

echo "Patching Authorino/${NAME} in ${NS} with openshift-service-ca.crt..."
oc patch authorino "${NAME}" -n "${NS}" --type=merge -p '{
  "spec": {
    "volumes": {
      "defaultMode": 420,
      "items": [
        {
          "name": "openshift-service-ca",
          "mountPath": "/etc/pki/tls/certs/maas-ca",
          "configMaps": ["openshift-service-ca.crt"]
        }
      ]
    }
  }
}'

oc set env "deploy/${NAME}" -n "${NS}" \
  SSL_CERT_DIR=/etc/ssl/certs:/etc/pki/tls/certs:/etc/pki/tls/certs/maas-ca

oc rollout status "deploy/${NAME}" -n "${NS}" --timeout=120s
echo "Authorino ready. Re-test MaaS /v1/models with a valid sk-oai- API key."
