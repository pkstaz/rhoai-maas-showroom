#!/usr/bin/env bash
# OpenShift Console plugin: https://github.com/eformat/openshift-skills-plugin
set -euo pipefail
WORKDIR="${WORKDIR:-/tmp/openshift-skills-plugin}"
REPO="${REPO:-https://github.com/eformat/openshift-skills-plugin.git}"

if [[ ! -d "$WORKDIR/.git" ]]; then
  git clone --depth 1 "$REPO" "$WORKDIR"
else
  git -C "$WORKDIR" pull --ff-only || true
fi

helm upgrade --install skills-plugin "$WORKDIR/chart/" \
  -n skills-plugin --create-namespace

# Enable on the cluster console (same pattern as GPU Booking).
if oc get consoleplugin skills-plugin >/dev/null 2>&1; then
  oc patch consoles.operator.openshift.io cluster --type=json \
    -p '[{"op":"add","path":"/spec/plugins/-","value":"skills-plugin"}]' 2>/dev/null || true
fi

oc adm policy add-cluster-role-to-user skills-plugin-admin "${SKILLS_ADMIN:-admin}" || true

echo "Hard refresh OpenShift console. Settings → Skills (MaaS endpoint = módulo 10)."
oc get pods,consoleplugin -n skills-plugin
