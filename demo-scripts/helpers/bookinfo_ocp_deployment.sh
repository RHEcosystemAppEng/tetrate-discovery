#!/bin/bash

# set -x
oc create namespace "$TIER2_NS"
oc adm policy add-scc-to-group privileged system:serviceaccounts:"$TIER2_NS"
oc label namespace "$TIER2_NS" istio-injection=enabled

eval "echo \"$(cat "$ROOT"/templates/tier2gw.yaml)\"" | kubectl apply -f - 2>/dev/null >/dev/null
#oc apply -f /tmp/tier2gw.yaml

oc -n "$TIER2_NS" apply -f "$ROOT"/templates/oc_NetworkAttach.yaml
kubectl -n $TIER2_NS apply -f https://raw.githubusercontent.com/istio/istio/release-1.11/samples/bookinfo/platform/kube/bookinfo.yaml  
oc rollout restart deployment -n "$TIER2_NS"

oc wait deployments.apps/productpage-v1 -n "$TIER2_NS" --for=condition=Available --timeout=4m
oc -n "$TIER2_NS" patch deployments.apps/productpage-v1 --patch "$(cat "$ROOT"/templates/productpage_patch.yaml)"


while [[ -z ${TSB_GATEWAY} ]]; do
    TSB_GATEWAY=$(kubectl -n "$TIER2_NS" get service "tsb-gateway-${TIER2_NS}" -o=jsonpath="{.status.loadBalancer.ingress[0]['hostname','ip']}" 2>/dev/null)   
    sleep 5
done

if [[ -z "$TSB_GATEWAY" ]]; then
    echo "Unable to obtain Bookinfo IP"
    exit 1
else
    echo "Bookinfo LB Address " "$TSB_GATEWAY"
fi
eval "echo \"$(cat "$ROOT"/templates/traffic_generator_local.yaml)\"" >/tmp/traffic_generator.yaml
kubectl apply -f /tmp/traffic_generator.yaml