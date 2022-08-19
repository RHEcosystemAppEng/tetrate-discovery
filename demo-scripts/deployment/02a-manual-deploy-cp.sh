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
export CLUSTER_PLATFORM=${CLUSTER_PLATFORM[$clusterNumber]}
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
  read -r -d '' CERTMNG_STRING << EOM
# Management plane uses external Cert Manager in this implementation so it needs to be added to the controlplane CRD
  kubectl -n istio-system patch controlplanes.install.tetrate.io controlplane --type='json' -p='[{"op": "add", "path": "/spec/components/internalCertProvider/certManager", "value": {"managed": "EXTERNAL"}}]'
EOM
else
    REUSE_MP=false
    echo "New Kubernetes cluster is required for this Contol Plane"
fi

echo "this script doesn't deploy anything but creates valid yamls for the cluster"

tctlClusterManifests "${CLUSTER}" "${REGION}" "docker.io/cmwylie19" ${isTier1GW}
if ${ECK_STACK_ENABLED}; then
read -r -d '' ES_STRING << EOM
# ca.crt and Elastic for FrontEnovy Elasticsearch
  kubectl -n istio-system create secret generic es-certs --from-file=ca.crt=/tmp/es-ca.crt
EOM
else
read -r -d '' ES_STRING << EOM
# default (demo)Elastic Credentials Secret
kubectl create secret generic elastic-credentials -n istio-system  --from-literal password=tsb-elastic-password --from-literal username=tsb
kubectl -n istio-system create secret generic mp-certs --from-file=ca.crt="$ROOT"/helpers/tsb/tsb-ca.crt 
kubectl -n istio-system create secret generic es-certs --from-file=ca.crt="$ROOT"/helpers/tsb/tsb-ca.crt
EOM
fi

if [[ ${CLUSTER_PLATFORM[$i]} =~ ^(oc|openshift|ocp)$ ]]; then
            OCP_DOMAIN=$(oc get ingresses.config/cluster -o jsonpath={.spec.domain})
            BRIDGE_ADDRESS_TSB=tsb."$OCP_DOMAIN"
read -r -d '' OPERATOR_PATCH << EOM
# for Openshift the memory limit needs to be patched for the operator
  oc -n istio-system patch deployment tsb-operator-control-plane --type='json' -p='[{"op": "add", "path": "/spec/template/spec/containers/0/resources/limits", "memory": "512Mi"}]'
  oc -n istio-system set env deployment/tsb-operator-control-plane MP_CUSTOM_SNI=$BRIDGE_ADDRESS_TSB
  oc apply -n istio-system -f templates/oc_NetworkAttach.yaml
EOM
fi

if [[ $VERSION == "1.5.0" ]]; then
    cat $ROOT/templates/fix-150.yaml >> /tmp/cp-${CLUSTER}.yaml
fi
read -r -d '' CONNECT_COMMAND << EOM
oc login https://api.${CLUSTER}.${DNS_DOMAIN}:6443 -u kubeadmin -p ${OC_PASSWORDS[$clusterNumber]}
EOM
cat <<EOF > /tmp/command-${CLUSTER}.sh
echo **** MAKE sure you're in the CORRECT cluster (${CLUSTER}) CONTEXT ***
$CONNECT_COMMAND
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
sleep 120 # wait before proceeding to the next command

$OPERATOR_PATCH

# applying secrets
kubectl apply -f /tmp/cp-secrets-${CLUSTER}.yaml
kubectl apply -f /tmp/xcp-central-ca-bundle.yaml

$ES_STRING

# Deploying the cluster config - better to examine before applying
kubectl apply -f /tmp/cp-site-${CLUSTER}.yaml

$CERTMNG_STRING

# Deploy Bookinfo yaml
ROOT=${ROOT} TIER2_NS=${TIER2_NS} $ROOT/helpers/bookinfo_deployment.sh
oc -n ${TIER2_NS} apply -f $ROOT/templates/oc_NetworkAttach.yaml 
EOF
cat $ROOT/templates/cp-jwt-support.yaml >> /tmp/cp-site-${CLUSTER}.yaml
echo Examine file /tmp/command-${CLUSTER}.sh and apply commands accordingly.
