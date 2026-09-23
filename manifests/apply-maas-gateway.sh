#!/usr/bin/env bash
set -euo pipefail

CLUSTER_DOMAIN=$(oc get ingresses.config/cluster -o jsonpath='{.spec.domain}')
MAAS_HOSTNAME="maas.${CLUSTER_DOMAIN}"

CERT_NAME=$(oc get ingresscontroller default -n openshift-ingress-operator \
  -o jsonpath='{.spec.defaultCertificate.name}')
CERT_NAME=${CERT_NAME:-router-certs-default}

echo "hostname=${MAAS_HOSTNAME} cert=${CERT_NAME}"

oc apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: maas-gateway-options
  namespace: openshift-ingress
data:
  deployment: |
    spec:
      template:
        spec:
          containers:
          - name: istio-proxy
            resources:
              requests:
                cpu: 100m
                memory: 256Mi
              limits:
                cpu: "2"
                memory: 2Gi
EOF

oc apply -f - <<EOF
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: maas-default-gateway
  namespace: openshift-ingress
  annotations:
    opendatahub.io/managed: "false"
    security.opendatahub.io/authorino-tls-bootstrap: "true"
spec:
  gatewayClassName: openshift-default
  infrastructure:
    parametersRef:
      group: ""
      kind: ConfigMap
      name: maas-gateway-options
  listeners:
    - name: http
      hostname: ${MAAS_HOSTNAME}
      port: 80
      protocol: HTTP
      allowedRoutes:
        namespaces:
          from: Selector
          selector:
            matchLabels:
              maas.opendatahub.io/gateway-access: "true"
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
