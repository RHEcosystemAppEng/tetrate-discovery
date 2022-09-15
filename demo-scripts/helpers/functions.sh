#!/bin/bash

function getSvcAddr() {
    svc=$1
    ns=$2
    ADDR=""
    ADDR=$(kubectl -n "$ns" get service "$svc" -o=jsonpath="{.status.loadBalancer.ingress[0]['hostname','ip']}" 2>/dev/null)
    echo "${ADDR}"
}

# e.g getTCCIP
function getTCCIP() {
    TCCIP=$(getSvcAddr "envoy" "$TSB_NS")
    echo "${TCCIP}"
}
function getBookinfoIP() {
    BookinfoIP=$(getSvcAddr "tsb-gateway-${TIER1_NS}" "$TIER1_NS")
    echo "${BookinfoIP}"
}

function updateRoute53() {
    OPERATION="UPSERT"
    RECORD_TTL=300
    FQDN=$1
    RECORD_VALUE=$2
    RECORD_TYPE="A"
    if [ -n "$3" ]; then
        RECORD_TYPE=$3
    fi
    
    eval "echo \"$(cat "$ROOT"/templates/route53_record.json)\"" >/tmp/"${FQDN}"-dns.json
    aws route53 change-resource-record-sets --hosted-zone-id "$HOSTEDZONEID" --change-batch file:///tmp/"${FQDN}"-dns.json
    check="false"
    counter=24
    wait_time=20
    while [ "$check" = "false" ] && [ $counter -gt 0 ]; do
        RECORD="$(aws route53 list-resource-record-sets --hosted-zone-id "$HOSTEDZONEID" --query ResourceRecordSets[?Name=="'""${FQDN}"".'"] | jq .[])"
        RECORD_ACTUAL_VALUE=$(echo "$RECORD" | jq .ResourceRecords[].Value)
        if [[ ${RECORD_ACTUAL_VALUE} == *${RECORD_VALUE}* ]]; then check="true"; fi
        if [[ "$check" != "true" ]]; then
            counter=$((counter - 1))
            echo "waiting for AWS Route53" $counter >&2
            echo
            sleep $wait_time
        fi
    done
}
function deleteRoute53record() {
    FQDN=$1
    RECORD=$(aws route53 list-resource-record-sets --hosted-zone-id "$HOSTEDZONEID" --query ResourceRecordSets[?Name=="'""${FQDN}"".'"] | jq .[])
    if [ -z "$RECORD" ]; then
        echo "Record for ${1} is not returned - can't delete" >&2
    else
        RECORD_TYPE=$(echo "$RECORD" | jq -r .Type)
        RECORD_TTL=$(echo "$RECORD" | jq .TTL)
        RECORD_VALUE=$(echo "$RECORD" | jq -r .ResourceRecords[].Value)
        OPERATION="DELETE"
        eval "echo \"$(cat "$ROOT"/templates/route53_record.json)\"" >/tmp/"${FQDN}"-delete-dns.json
        aws route53 change-resource-record-sets --hosted-zone-id "$HOSTEDZONEID" --change-batch file:///tmp/"${FQDN}"-delete-dns.json
    fi
}
function tctlCLIConfig() {
    FQDN=$1
    if [ -z "$FQDN" ]; then
        FQDN="${DEPLOYMENT_NAME}"-tsb."${DNS_DOMAIN}"
    fi
    
    tctl config clusters set "$ORG"-cluster --bridge-address "${FQDN}":8443 --tls-insecure
    tctl config users set "$ORG"-admin \
    --org "$ORG" \
    --tenant "$ORG"-tenant \
    --username admin --password "$TSB_ADMIN_PASS"
    tctl config profiles set "$ORG"-profile \
    --cluster "$ORG"-cluster \
    --username "$ORG"-admin
    tctl config profiles set-current "$ORG"-profile
}
function tctlClusterManifests() {
    CLUSTER=$1
    REGION=$2
    REPO=$3
    isTier1=$4
    
    
    if ! tctl config profiles set-current "$ORG"-profile; then
        echo "can't connect to TSB with tctl" >&2
        exit 1
    fi
    eval "echo \"$(cat "$ROOT"/templates/tctl-cluster.yaml)\"" >/tmp/cp-cluster-"${CLUSTER}".yaml
    # tctl apply -f /tmp/cp-cluster-"${CLUSTER}".yaml >/dev/null
    tctl install manifest cluster-operator --registry "$REPO" >/tmp/cp-"${CLUSTER}".yaml
    connectToCluster "${MP_CLUSTER}"
    tctl install cluster-service-account \
    --cluster  $CLUSTER\
    > /tmp/cluster-$CLUSTER-service-account.jwk
    if ${ECK_STACK_ENABLED}; then
        kubectl get secret -n es tsb-es-http-certs-public -o go-template='{{ index .data "ca.crt" | base64decode }}' >/tmp/es-ca.crt
        kubectl get secret -n es tsb-es-elastic-user -o jsonpath="{.data.elastic}" > /tmp/elastic-creds.data
        sleep 60
        tctl install manifest control-plane-secrets --cluster "$CLUSTER" \
        --elastic-username elastic \
        --cluster-service-account="$(cat /tmp/cluster-$CLUSTER-service-account.jwk)" \
        --elastic-password "$(kubectl get secret -n es tsb-es-elastic-user -o jsonpath="{.data.elastic}" | base64 -d)" \
        >/tmp/cp-secrets-"${CLUSTER}".yaml
        ES_FQDN=$(getSvcAddr "tsb-es-http" "es")
        export ES_FQDN
        eval "echo \"$(cat "$ROOT"/templates/cp-site-eck.yaml)\"" >/tmp/cp-site-"${CLUSTER}".yaml
    else
        if [[ ${CLUSTER_PLATFORM[$MP_CLUSTER]} =~ ^(oc|openshift|ocp)$ ]]; then
            if ! oc login https://api.${CLUSTER_LIST[$MP_CLUSTER]}.${DNS_DOMAIN}:6443 -u kubeadmin -p ${OC_PASSWORDS[$MP_CLUSTER]}; then
                echo "cannot connect to the cluster" >&2
                exit 1
            fi
            TCCIP=$(getTCCIP)
            while [[ -z ${TCCIP} ]]; do
                TCCIP=$(getTCCIP)
                sleep 5
            done
            BRIDGE_ADDRESS_LB="$TCCIP"
            OCP_DOMAIN=$(oc get ingresses.config/cluster -o jsonpath={.spec.domain})
            BRIDGE_ADDRESS_TSB=tsb."$OCP_DOMAIN"
            PORT_LB="8443"
            PORT_TSB="443"
        else
            BRIDGE_ADDRESS="${DEPLOYMENT_NAME}"-tsb."${DNS_DOMAIN}"
            PORT="8443"
        fi
        eval "echo \"$(cat "$ROOT"/templates/cp-site.yaml)\"" >/tmp/cp-site-"${CLUSTER}".yaml
        tctl install manifest control-plane-secrets --cluster "$CLUSTER" \
        --cluster-service-account="$(cat /tmp/cluster-$CLUSTER-service-account.jwk)" \
        --allow-defaults >/tmp/cp-secrets-"${CLUSTER}".yaml
    fi
    # tctl install cluster-certs --cluster "${CLUSTER}" >/tmp/cp-certs-"${CLUSTER}".yaml
    CA_CERT=$(kubectl get secrets -n tsb xcp-central-cert -ojsonpath='{.data.ca\.crt}')
    eval "echo \"$(cat "$ROOT"/templates/xcp-central-ca-bundle.yaml)\"" >/tmp/xcp-central-ca-bundle.yaml
}


function createTier1GW() {
    kubectl create namespace "$TIER1_NS"
    if [[ ${CLUSTER_PLATFORM[$clusterNumber]} =~ ^(amazon|aws)$ ]]; then
        eval "echo \"$(cat "$ROOT"/templates/tier1gw-aws.yaml)\"" >/tmp/tier1gw.yaml
    fi
    kubectl apply -f /tmp/tier1gw.yaml
}

function createTrafficGenerator() {
    kubectl apply -f /tmp/traffic_generator.yaml
}

function listClusters() {
    echo =========================================================== >&2
    for ((i = 0; i < ${#CLUSTER_LIST[@]}; i++)); do
        echo "./02-deploy-cp.sh ${env_file} $i # if you want to deploy ${CLUSTER_LIST[$i]}" >&2
    done
    echo =========================================================== >&2
}
function applyCAcert() {
    kubectl create namespace istio-system >/dev/null 2>/dev/null
    kubectl create secret generic cacerts -n istio-system \
    --from-file="$ROOT"/helpers/istio-certs/ca-cert.pem \
    --from-file="$ROOT"/helpers/istio-certs/ca-key.pem \
    --from-file="$ROOT"/helpers/istio-certs/root-cert.pem \
    --from-file="$ROOT"/helpers/istio-certs/cert-chain.pem >&2
}
function createGCPCluster() {
    CLUSTER=$1
    REGION=$2
    NODE_TYPE=$3
    NUMBER_NODES=$4
    TYPE_LABEL=$5
    SITE_LABEL=$6
    GCP_VERSION="1.21.6-gke.1500"
    LOCATION=$(gcloud compute zones list --project ${GCP_PROJECT}  --filter=region:${REGION} --format=json | jq -r .[0].name)
    required_dashes=1
    number_dashes=$(echo ${REGION} | grep -o '-' | wc -l)
    if [ $number_dashes -ne $required_dashes ]; then
        echo "Region name needs correction in variables file - number of \"-\" doesn't match the GCP cloud specs" >&2
        exit 1
    fi
    if [[ "$7" -ne 0 ]]; then
        AUTOSCALING="--enable-autoscaling --min-nodes 0 --max-nodes ${7}"
    else
        AUTOSCALING=""
    fi
    gcloud container clusters create $CLUSTER \
    --node-labels=owner=$OWNER_NAME,type=$TYPE_LABEL,site=$SITE_LABEL,demo_env=$DEPLOYMENT_NAME \
    --region $REGION \
    --node-locations $LOCATION \
    --machine-type=$NODE_TYPE \
    --enable-network-policy \
    --project $GCP_PROJECT \
    --num-nodes $NUMBER_NODES \
    --release-channel stable \
    #        --cluster-version=$GCP_VERSION \
    --no-user-output-enabled \
    $AUTOSCALING
}
function createAWSCluster() {
    CLUSTER=$1
    REGION=$2
    NODE_TYPE=$3
    NUMBER_NODES=$4
    TYPE_LABEL=$5
    SITE_LABEL=$6
    required_dashes=2
    owner_tag="${OWNER_NAME}@tetrate.io"
    number_dashes=$(echo ${REGION} | grep -o '-' | wc -l)
    if [ $number_dashes -ne $required_dashes ]; then
        echo "Region name needs correction in variables file - number of \"-\" doesn't match the AWS cloud specs" >&2
        exit 1
    fi
    eksctl create cluster --region $REGION \
    --name $CLUSTER  \
    --nodes $NUMBER_NODES \
    --node-type $NODE_TYPE \
    --node-labels="Owner=cxteam,Environment=${DEPLOYMENT_TYPE},Contact=${OWNER_NAME},type=${TYPE_LABEL},site=${SITE_LABEL},demo_env=${DEPLOYMENT_NAME}" \
    --tags "Tetrate:Owner=${owner_tag}" \
    --version=1.19 >&2
    
    eksctl create iamidentitymapping --cluster $CLUSTER \
    --arn arn:aws:iam::192760260411:role/OpsAdmin \
    --group system:masters --username OpsAdmin --region $REGION
}
function installCertManager() {
    echo "Install cert manager" >&2
    
    if ! kubectl -n cert-manager rollout status deployment/cert-manager 2>/dev/null;
    then
        kubectl apply --validate=false -f https://github.com/jetstack/cert-manager/releases/download/v1.7.2/cert-manager.yaml 2>/dev/null
        kubectl --namespace cert-manager create secret generic prod-route53-credentials-secret \
        --from-literal="secret-access-key=$ROUTE53_SECRET" 2>/dev/null
    else
        echo "Cert Manager Deployment already exists" >&2
    fi
    echo "adding flag for ExperimentalCertificateSigningRequestControllers" >&2
    kubectl -n cert-manager patch deployments.apps/cert-manager \
    --type merge \
    --patch "$(cat "$ROOT"/templates/cert-manager-flags.yaml)" >/dev/null 2>/dev/null
    kubectl rollout restart deployment -n cert-manager >/dev/null 2>/dev/null
}
function installECK() {
    echo "Deploying Elastic Cloud on Kubernetes (ECK)" >&2
    
    if ! kubectl -n es rollout status deployment/tsb-kb 2>/dev/null; then
        kubectl create -f https://download.elastic.co/downloads/eck/1.7.0/crds.yaml 2>/dev/null;
        kubectl apply -f https://download.elastic.co/downloads/eck/1.7.0/operator.yaml 2>/dev/null;
        kubectl apply -f "$ROOT"/templates/eck.yaml 2>/dev/null;
    else
        echo "ECK is already deployed in this cluster" >&2
    fi
}
function ECKCreds() {
    kubectl -n tsb delete secret elastic-credentials 2>/dev/null
    kubectl -n tsb create secret generic elastic-credentials \
    --from-literal=username=elastic \
    --from-literal=password="$(kubectl get secret -n es tsb-es-elastic-user -o jsonpath="{.data.elastic}" | base64 -d)" \
    2>/dev/null;
    
    kubectl -n tsb create secret generic es-certs \
    --from-literal=ca.crt="$(kubectl get secret -n es tsb-es-http-certs-public -o go-template='{{ index .data "ca.crt" | base64decode}}')" \
    2>/dev/null;
}
function identifyBookinfoCP() {
    for ((i = 0; i < ${#CLUSTER_LIST[@]}; i++)); do
        if [[ "$i" -ne ${TIER1_CLUSTER} ]]; then
            BACKEND_CLUSTERS+=($i)
        fi
    done
    echo "${BACKEND_CLUSTERS[*]}"
}
function getRepo() {
    CLUSTER_NUMBER=$1
    if [[ ${CLUSTER_PLATFORM[$CLUSTER_NUMBER]} =~ ^(amazon|aws)$ ]]; then
        REPO="${AWS_ACCOUNT}.dkr.ecr.${REGION_LIST[$CLUSTER_NUMBER]}.amazonaws.com/cx-aws-demo-repo"
        elif [[ ${CLUSTER_PLATFORM[$CLUSTER_NUMBER]} == "gcp" ]]; then
        [[ ! -z "$GCP_REGISTRY" ]] && REPO=$GCP_REGISTRY || REPO="gcr.io/${GCP_PROJECT}"
    else
        REPO="unknown"
    fi
    echo ${REPO}
}
function connectToCluster() {
    internalClusterNumber=$1
    internalPLATFORM=${CLUSTER_PLATFORM[${internalClusterNumber}]}
    internalCLUSTER=${CLUSTER_LIST[$internalClusterNumber]}
    internalREGION=${REGION_LIST[$internalClusterNumber]}

    if [[ $internalPLATFORM == "gcp" ]]; then
        echo "Connecting to GKE cluster ${internalCLUSTER}"
        CLUSTER_EXISTS=$(gcloud container clusters list --project "${GCP_PROJECT}" --region "${internalREGION}" --filter NAME="${internalCLUSTER}" | wc -l)
        if [[ $CLUSTER_EXISTS -eq 0 ]]; then
            echo "GCP cluster doesn't exists exiting" >&2
            exit 1
        fi
        
        if ! gcloud container clusters get-credentials "$internalCLUSTER" \
        --region "$internalREGION" --project "$GCP_PROJECT" --no-user-output-enabled; then
            echo "cannot connect to the cluster" >&2
            exit 1
        fi
        elif [[ $internalPLATFORM =~ ^(amazon|aws)$ ]]; then
        echo "Connecting to AWS cluster ${internalCLUSTER}"
        
        if ! aws eks --region "$internalREGION" update-kubeconfig --name "$internalCLUSTER"; then
            echo "cannot connect to the cluster" >&2
            exit 1
        fi
        elif [[ $internalPLATFORM =~ ^(openshift|oc)$ ]]; then
        echo "Connecting to Openshfit cluster ${internalCLUSTER}"
        ocpass=${OC_PASSWORDS[$internalClusterNumber]}
        
        if ! oc login https://api.${internalCLUSTER}.${DNS_DOMAIN}:6443 -u kubeadmin -p ${ocpass}; then
            echo "cannot connect to the cluster" >&2
            exit 1
        fi
    else
        echo "unknown cluster type" >&2
        exit 1
    fi
}
function setupOnboardingCA() {
    openssl req \
    -x509 \
    -subj '/CN=Tetrate CX Team' \
    -days 3650 \
    -sha256 \
    -newkey rsa:2048 \
    -nodes \
    -keyout /tmp/tetratecx-ca.key.pem \
    -out /tmp/tetratecx-ca.crt.pem \
    -config "$ROOT"/templates/vm-onboarding/ca.cfg \
    >/dev/null 2>/dev/null
}

function procureOnboardingTLScert() {
    openssl req \
    -subj '/CN=onboarding-endpoint.cx.tetrate.info' \
    -sha256 \
    -newkey rsa:2048 \
    -nodes \
    -keyout /tmp/onboarding-endpoint.cx.tetrate.info.key.pem \
    -out /tmp/onboarding-endpoint.cx.tetrate.info.csr.pem \
    >/dev/null 2>/dev/null
    
    openssl x509 \
    -req \
    -days 3650 \
    -sha256 \
    -in /tmp/onboarding-endpoint.cx.tetrate.info.csr.pem \
    -out /tmp/onboarding-endpoint.cx.tetrate.info.crt.pem \
    -CA /tmp/tetratecx-ca.crt.pem \
    -CAkey /tmp/tetratecx-ca.key.pem \
    -CAcreateserial \
    -extfile "$ROOT"/templates/vm-onboarding/tls.cfg \
    >/dev/null 2>/dev/null
    
}
function setTFWorkspace() {
    if [[ $1 == *"env"* ]]; then
        TFWorkspace=$1
    else
        TFWorkspace="${1}.env"
    fi
    if [[ $2 == "allow_new" ]]; then terraform -chdir="$ROOT"/vm_tf/asg/ workspace new ${TFWorkspace} 2>/dev/null; fi
    if terraform -chdir="$ROOT"/vm_tf/asg/ workspace select ${TFWorkspace} 2>/dev/null; then echo "success"; fi
    
}

function createPrivateJWTSigner() {
   ssh-keygen -f /tmp/private.key -m pem -N "" <<<y >/dev/null 2>&1
   kubectl -n tsb create secret generic token-issuer-key \
    --from-file=private.key=/tmp/private.key 2>/dev/null
}

function generateSelfSignedTSBCertsForOCP() {
    OCP_DOMAIN=$1
    "$ROOT"/helpers/gen-cert.sh tsb tsb."$OCP_DOMAIN" "$ROOT"/helpers/tsb
}

function applySeflSignedTSBCertificates() {
    kubectl -n "$TSB_NS" create secret generic tsb-certs \
    --from-file=ca.crt="$ROOT"/helpers/tsb/tsb-ca.crt  \
    --from-file=tls.crt="$ROOT"/helpers/tsb/tsb.crt  \
    --from-file=tls.key="$ROOT"/helpers/tsb/tsb.key
}