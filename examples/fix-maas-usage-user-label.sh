#!/usr/bin/env bash
# Make MaaS Usage dashboard show Token consumption.
# The Perses panel filters authorized_hits_total{user!=""}; without a `user`
# label on TelemetryPolicy, the UI stays at 0 even when Limitador counts tokens.
set -euo pipefail

oc patch telemetrypolicy maas-telemetry -n openshift-ingress --type=merge -p '{
  "spec": {
    "metrics": {
      "default": {
        "labels": {
          "cost_center": "has(auth.identity.subscription_info.costCenter) ? auth.identity.subscription_info.costCenter : \"\"",
          "model": "responseBodyJSON(\"/model\")",
          "organization_id": "has(auth.identity.subscription_info.organizationId) ? auth.identity.subscription_info.organizationId : \"\"",
          "subscription": "auth.identity.selected_subscription",
          "user": "has(auth.identity.userid) ? auth.identity.userid : (has(auth.identity.preferred_username) ? auth.identity.preferred_username : (has(auth.metadata.apiKeyValidation.username) ? auth.metadata.apiKeyValidation.username : \"anonymous\"))"
        }
      }
    }
  }
}'

echo "TelemetryPolicy patched with user label."
echo "Generate a few chat completions (module 10 curl or Playground), wait ~1 min, refresh Usage."
echo "NOTE: If maas-controller reconciles TelemetryPolicy, re-run this script."
