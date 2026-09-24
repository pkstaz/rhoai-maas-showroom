#!/usr/bin/env bash
# GPU Booking on a hybrid cluster (real NVIDIA + Fake GPU).
# Auto-discovery only lists nvidia.com/gpu.present=true; Fake GPU forces present=false.
# Disable discovery and feed a static gpu-config.json built from both node types.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHART_DIR="${GPU_BOOKING_CHART:-/tmp/gpu-booking-app-plugin}"
NS=gpu-booking-app-plugin
VALUES="$(mktemp)"
trap 'rm -f "${VALUES}"' EXIT

if [[ ! -d "${CHART_DIR}/chart" ]]; then
  echo "Cloning gpu-booking-app-plugin..."
  git clone --depth 1 https://github.com/rhai-code/gpu-booking-app-plugin.git "${CHART_DIR}"
fi

echo "Building gpu-config from real + Fake GPU nodes..."
oc get nodes -o json | python3 -c '
import json, sys, math, re

data = json.load(sys.stdin)
mig_re = re.compile(r"^nvidia\.com/mig-(\d+g)\.(\d+)gb$")

full = {}          # product -> {count, memory_mib}
mig = {}           # resource -> {count, mem_gb}
total_cpu = 0
total_mem_gi = 0
full_mem_mib = 0

def parse_cpu(s):
    s = (s or "").strip()
    if not s:
        return 0
    if s.endswith("m"):
        return int(s[:-1]) // 1000
    return int(float(s))

def parse_mem_gi(s):
    s = (s or "").strip()
    if s.endswith("Ki"):
        return int(s[:-2]) // (1024 * 1024)
    if s.endswith("Mi"):
        return int(s[:-2]) // 1024
    if s.endswith("Gi"):
        return int(s[:-2])
    if s.endswith("Ti"):
        return int(s[:-2]) * 1024
    return 0

def is_fake(n):
    l = n.get("metadata", {}).get("labels") or {}
    return l.get("run.ai/fake.gpu") == "true" or "run.ai/simulated-gpu-node-pool" in l

def is_real(n):
    l = n.get("metadata", {}).get("labels") or {}
    return l.get("nvidia.com/gpu.present") == "true" and not is_fake(n)

for n in data.get("items", []):
    if not (is_real(n) or is_fake(n)):
        continue
    labels = n.get("metadata", {}).get("labels") or {}
    alloc = n.get("status", {}).get("allocatable") or {}
    product = labels.get("nvidia.com/gpu.product") or ("Fake GPU" if is_fake(n) else "GPU")
    mem = int(labels.get("nvidia.com/gpu.memory") or "0")
    gpu_n = int(alloc.get("nvidia.com/gpu") or "0")
    if gpu_n > 0:
        slot = full.setdefault(product, {"count": 0, "memory_mib": mem})
        slot["count"] += gpu_n
        if mem > 0:
            slot["memory_mib"] = mem
            full_mem_mib = max(full_mem_mib, mem)
    for key, val in alloc.items():
        m = mig_re.match(key)
        if not m:
            continue
        c = int(val or "0")
        if c <= 0:
            continue
        mem_gb = int(m.group(2))
        slot = mig.setdefault(key, {"count": 0, "mem_gb": mem_gb})
        slot["count"] += c
    total_cpu += parse_cpu(alloc.get("cpu"))
    total_mem_gi += parse_mem_gi(alloc.get("memory"))

resources = []
# Plugin UI keys cards by type; both real and Fake advertise nvidia.com/gpu.
# Collapse full GPUs into one card so L4 + Fake are both bookable units.
full_count = sum(v["count"] for v in full.values())
if full_count:
    name = " / ".join(full.keys()) + " Full GPU"
    resources.append({
        "name": name,
        "type": "nvidia.com/gpu",
        "count": full_count,
        "gpuEquivalent": 1.0,
    })

full_mem_gb = (full_mem_mib / 1024.0) if full_mem_mib else 140.0
for key, info in sorted(mig.items(), key=lambda kv: -kv[1]["mem_gb"]):
    parts = key.replace("nvidia.com/", "")
    equiv = info["mem_gb"] / full_mem_gb if full_mem_gb else 0.125
    resources.append({
        "name": "MIG " + parts.replace("mig-", ""),
        "type": key,
        "count": info["count"],
        "gpuEquivalent": round(equiv, 3),
    })

total_equiv = sum(r["count"] * r["gpuEquivalent"] for r in resources) or 1.0
for r in resources:
    r["share"] = r["gpuEquivalent"] / total_equiv

if not resources:
    sys.stderr.write("ERROR: no real or Fake GPU nodes found\n")
    sys.exit(1)

out = {
    "gpuDiscovery": {"enabled": False},
    "enablePlugin": False,
    "gpuConfig": {
        "resources": resources,
        "totalCpu": total_cpu or 1,
        "totalMemory": total_mem_gi or 1,
    },
}
print(json.dumps(out, indent=2))
print("GPU Booking resources:", file=sys.stderr)
for r in resources:
    print("  %s: type=%s count=%s" % (r["name"], r["type"], r["count"]), file=sys.stderr)
' > "${VALUES}"

echo "Helm installing GPU Booking (discovery off, --no-hooks)..."
helm upgrade -i gpu-booking-plugin "${CHART_DIR}/chart/" \
  -n "${NS}" --create-namespace --no-hooks \
  -f "${VALUES}"

PLUGINS=$(oc get consoles.operator.openshift.io cluster -o jsonpath='{.spec.plugins}' || echo '[]')
if ! echo "${PLUGINS}" | grep -q 'gpu-booking-plugin'; then
  oc patch consoles.operator.openshift.io cluster --type=json \
    -p '[{"op":"add","path":"/spec/plugins/-","value":"gpu-booking-plugin"}]'
fi

oc rollout status -n "${NS}" deploy/gpu-booking-plugin --timeout=180s
oc get pods,consoleplugin -n "${NS}"
echo "Done. Hard-refresh OpenShift console → GPU Booking → Discover is disabled; cards come from the static config (real + Fake)."
