#!/bin/bash

ROOT=$(git rev-parse --show-toplevel)/demo-scripts

export env_file=$1
export clusterNumber=$2

if ! source "$ROOT"/helpers/init.sh; then exit 1; fi

source "$ROOT"/helpers/functions.sh
source "$ROOT"/helpers/parser.sh >/dev/null

if [[ -z "${clusterNumber}" ]]; then
  echo "Cluster number needs to be specified - here is the list"
  CLUSTER_LIST=$(listClusters)
  exit 1
elif [[ $clusterNumber -lt ${#CLUSTER_LIST[@]} ]]; then
  echo "Creating ${CLUSTER_LIST[${clusterNumber}]} cluster"
else
  echo "Specified cluster is missing in variables files"
  CLUSTER_LIST=$(listClusters)
  exit 1
fi

export CLUSTER=${CLUSTER_LIST[$clusterNumber]}
export REGION=${REGION_LIST[$clusterNumber]}
REPO=$(getRepo "$clusterNumber")
export REPO
if [[ "$clusterNumber" == "${TIER1_CLUSTER}" ]]; then
  isTier1GW="true"
  textTier1="Tier1 Gateway"
  clusterlabel="tsb-tier1gw"
else
  textTier1="Application Control plane"
  isTier1GW="false"
  clusterlabel="tsb-cp-backend"
fi
if [[ $clusterNumber == "$MP_CLUSTER" ]]; then
  REUSE_MP=true
  echo "Control Plane is configured to use Management Plane cluster and will try to use it"
else
  REUSE_MP=false
  echo "New Kubernetes cluster is required for this Contol Plane"
fi

  echo "this script doesn't deploy anything but creates valid yamls for the cluster"

tctlClusterManifests "${CLUSTER}" "${REGION}" "docker.io/cmwylie19" ${isTier1GW} "${ORG}"
if ${ECK_STACK_ENABLED}; then
read -r -d '' ES_STRING << EOM
# ca.crt and Elastic for FrontEnovy Elasticsearch
  kubectl -n istio-system create secret generic es-certs --from-file=ca.crt=/tmp/es-ca.crt
EOM
fi

cat <<EOF > /tmp/command-${CLUSTER}.sh
echo **** MAKE sure you're in the CORRECT cluster (${CLUSTER}) CONTEXT ***
# creating namespace
  kubectl create namespace istio-system 

#creating certificate for mutual trust
  kubectl create secret generic cacerts -n istio-system \\
    --from-file=$ROOT/helpers/istio-certs/ca-cert.pem \\
    --from-file=$ROOT/helpers/istio-certs/ca-key.pem \\
    --from-file=$ROOT/helpers/istio-certs/root-cert.pem \\
    --from-file=$ROOT/helpers/istio-certs/cert-chain.pem 

# installing operator
kubectl apply -f /tmp/cp-${CLUSTER}.yaml 

# applying secrets
kubectl apply -f /tmp/cp-secrets-${CLUSTER}.yaml 
kubectl apply -f /tmp/xcp-central-ca-bundle.yaml 

$ES_STRING

# Deploying the cluster config - better to examine before applying
kubectl apply -f /tmp/cp-site-${CLUSTER}.yaml

# Deploy Bookinfo yaml
ROOT=${ROOT} TIER2_NS=${TIER2_NS} $ROOT/helpers/bookinfo_deployment.sh 
EOF
cat $ROOT/templates/cp-jwt-support.yaml >> /tmp/cp-site-${CLUSTER}.yaml
echo Examine file /tmp/command-${CLUSTER}.sh and apply commands accordingly.
