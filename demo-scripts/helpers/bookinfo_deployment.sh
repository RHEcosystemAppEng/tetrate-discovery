#!/bin/bash

kubectl create namespace $TIER2_NS >/dev/null 2>/dev/null
kubectl label namespace $TIER2_NS istio-injection=enabled >/dev/null 2>/dev/null
sleep 60
eval "echo \"$(cat "$ROOT"/templates/tier2gw.yaml)\"" | kubectl apply -f - 2>/dev/null >/dev/null 

kubectl -n $TIER2_NS apply -f https://raw.githubusercontent.com/istio/istio/release-1.11/samples/bookinfo/platform/kube/bookinfo.yaml  >/dev/null 2>/dev/null
kubectl wait deployments.apps/productpage-v1 -n $TIER2_NS --for=condition=Available --timeout=4m >/dev/null 2>/dev/null
kubectl -n $TIER2_NS patch deployments.apps/productpage-v1 --patch "$(cat "$ROOT"/templates/productpage_patch.yaml)" >/dev/null 2>/dev/null

kubectl rollout restart deployment -n $TIER2_NS >/dev/null 2>/dev/null
