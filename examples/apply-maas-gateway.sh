#!/usr/bin/env bash
set -euo pipefail

CLUSTER_DOMAIN=$(oc get ingresses.config/cluster -o jsonpath='{.spec.domain}')
MAAS_HOSTNAME="maas.${CLUSTER_DOMAIN}"

CERT_NAME=$(oc get secret -n openshift-ingress -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' \
  | grep -E '^(router-certs-default|router-certs)$' | head -1)
CERT_NAME=${CERT_NAME:-router-certs-default}

echo "hostname=${MAAS_HOSTNAME} cert=${CERT_NAME}"

oc apply -f - <<EOF
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: openshift-default
spec:
  controllerName: openshift.io/gateway-controller/v1
EOF

oc apply -f - <<EOF
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: maas-default-gateway
  namespace: openshift-ingress
  labels:
    kuadrant.io/gateway: "true"
  annotations:
    opendatahub.io/managed: "false"
    security.opendatahub.io/authorino-tls-bootstrap: "true"
spec:
  gatewayClassName: openshift-default
  listeners:
    - name: https
      hostname: ${MAAS_HOSTNAME}
      port: 443
      protocol: HTTPS
      allowedRoutes:
        namespaces:
          from: Selector
          selector:
            matchLabels:
              maas.opendatahub.io/gateway-access: "true"
      tls:
        mode: Terminate
        certificateRefs:
          - group: ""
            kind: Secret
            name: ${CERT_NAME}
EOF

oc wait --for=condition=Programmed gateway/maas-default-gateway -n openshift-ingress --timeout=180s
echo "Gateway ready: https://${MAAS_HOSTNAME}"
