#!/bin/bash

oc create namespace "$TIER2_NS"
oc adm policy add-scc-to-group anyid system:serviceaccounts:"$TIER2_NS"
oc label namespace "$TIER2_NS" istio-injection=enabled

eval "echo \"$(cat "$ROOT"/templates/tier2gw.yaml)\"" | kubectl apply -f - 2>/dev/null >/dev/null 
#oc apply -f /tmp/tier2gw.yaml

oc -n "$TIER2_NS" apply -f "$ISTIO_DIR"/samples/bookinfo/platform/kube/bookinfo.yaml
oc rollout restart deployment -n "$TIER2_NS"
oc -n "$TIER2_NS" apply -f "$ROOT"/templates/oc_NetworkAttach.yaml 
oc wait deployments.apps/productpage-v1 -n "$TIER2_NS" --for=condition=Available --timeout=4m
oc -n "$TIER2_NS" patch deployments.apps/productpage-v1 --patch "$(cat "$ROOT"/templates/productpage_patch.yaml)"
