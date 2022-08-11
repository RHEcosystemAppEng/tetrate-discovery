#!/bin/bash

ROOT=$(git rev-parse --show-toplevel)/demo-scripts

if ! source "$ROOT"/helpers/init.sh; then exit 1; fi

source "$ROOT"/helpers/functions.sh >/dev/null

echo "Parsing yaml's"
source "$ROOT"/helpers/parser.sh >/dev/null

REPO_MP="docker.io/cmwylie19"
export REPO_MP
export clusterNumber=${MP_CLUSTER}
export clusterlabel="tsb-mp-cp"

# if [[ ${CLUSTER_PLATFORM[$clusterNumber]} =~ ^(amazon|aws)$ ]]; then
#     DNS_RECORD_TYPE="CNAME"
#     echo "Deploying AWS Cluster which will serve as a Management Plane"
#     createAWSCluster "${CLUSTER_LIST[$clusterNumber]}" "${REGION_LIST[$clusterNumber]}" "m5.xlarge" 4 ${clusterlabel} "site-${clusterNumber}"
# elif [[ ${CLUSTER_PLATFORM[$clusterNumber]} == "gcp" ]]; then
#     DNS_RECORD_TYPE="A"
#     echo "Deploying GCP Cluster for Management Plane"
#     createGCPCluster "${CLUSTER_LIST[$clusterNumber]}" "${REGION_LIST[$clusterNumber]}" "e2-highcpu-16" 3 "${clusterlabel}" "site-${clusterNumber}" 4
# else
#     echo "can't detect the platform of the cluster"
#     exit 1
# fi
echo "Connecting to the Management Plane cluster"

if ! connectToCluster "${clusterNumber}"; then
    echo "Can't connect to the cluster Exiting!"
    exit 1
else
    echo "Succesfully connected to the ${CLUSTER_LIST[$clusterNumber]}"
fi

installCertManager

kubectl wait -n cert-manager --for=condition=Available --timeout=4m deployment/cert-manager-webhook 2>/dev/null

if ${ECK_STACK_ENABLED}; then
    echo "ECK is enabled"
    installECK
    kubectl wait -n es --for=condition=Available --timeout=4m deployment/tsb-kb 2>/dev/null
fi

eval "echo \"$(cat "$ROOT"/templates/mgmntplane-cr-base.yaml)\"" >/tmp/mgmntplane-cr.yaml

if ! kubectl -n "$TSB_NS" rollout status deployment/tsb-operator-management-plane 2>/dev/null; then
    tctl install manifest management-plane-operator \
        --registry "$REPO_MP" >/tmp/managementplaneoperator.yaml
    kubectl apply -f /tmp/managementplaneoperator.yaml
    kubectl wait -n "$TSB_NS" --for=condition=Available --timeout=4m deployment/tsb-operator-management-plane 2>/dev/null
else
    echo "TSB MP Operator deployment already exists"
fi

if ! kubectl -n "$TSB_NS" rollout status deployment/envoy 2>/dev/null; then
    kubectl apply -f /tmp/cert-manager.yaml
    kubectl wait -n "$TSB_NS" --for=condition=Ready --timeout=10m certificate/tsb-certs 2>/dev/null
    tctl install manifest management-plane-secrets \
        --elastic-password tsb-elastic-password \
        --elastic-username tsb \
        --ldap-bind-dn cn=admin,dc=tetrate,dc=io \
        --ldap-bind-password admin \
        --postgres-password tsb-postgres-password \
        --postgres-username tsb \
        --tsb-admin-password "$TSB_ADMIN_PASS" \
        --allow-defaults \
        >/tmp/mp-secrets-"$DEPLOYMENT_TYPE"-"$DEPLOYMENT_NAME".yaml

if [ $JWT = "true" ]; then
    kubectl delete secret -n "$TSB_NS" mpc-certs 2>/dev/null
fi
    createPrivateJWTSigner
    kubectl apply -f /tmp/mp-secrets-"$DEPLOYMENT_TYPE"-"$DEPLOYMENT_NAME".yaml 2>/dev/null
    kubectl --namespace cert-manager create secret generic prod-route53-credentials-secret \
      --from-literal="secret-access-key=$ROUTE53_SECRET" 2>/dev/null 
    kubectl delete secret -n "$TSB_NS" tsb-certs 2>/dev/null
#    kubectl -n "$TSB_NS" create secret generic tsb-certs \
#      --from-file=ca.crt=/tmp/tsb-ca.crt  \
#      --from-file=tls.crt=/tmp/tsb.crt  \
#      --from-file=tls.key=/tmp/tsb.key
    kubectl get secret -n "$TSB_NS" tsb-certs 2>/dev/null
    check=$?
    counter=20
    while [ $check -ne 0 ] && [ $counter -gt 0 ]; do
        kubectl get secret -n "$TSB_NS" tsb-certs 2>/dev/null
        check=$?
        if [ $check -ne 0 ]; then
            counter=$((counter - 1))
            if [ $counter -eq 0 ]; then
                echo "the tsb-certs secret is not ready"
                exit 1
            fi
            echo "waiting for tsb-cert" $counter
            sleep 10
        fi
    done
    # kubectl -n "$TSB_NS" get secret tsb-certs -o yaml \
    #   | sed 's/name: .*/name: xcp-central-cert/' \
    #   | kubectl apply -f - 2>/dev/null
    if ${ECK_STACK_ENABLED}; then
        echo "creating ECK secrets"
        ECKCreds
    fi
else
    echo "MP deployments already exists"
fi
if [ $JWT = "true" ]; then
cat "$ROOT"/templates/mp-jwt-support.yaml >> /tmp/mgmntplane-cr.yaml  
fi
kubectl apply -f /tmp/mgmntplane-cr.yaml
if ${ECK_STACK_ENABLED}; then
    kubectl patch managementplanes.install.tetrate.io tsbmgmtplane \
        -n "$TSB_NS" --patch "$(cat "$ROOT"/templates/mgmntplane-patch.yaml)" \
        --type merge 2>/dev/null
fi

kubectl rollout status -n "$TSB_NS" deployment/central 2>/dev/null
check=$?
counter=24
while [ $check -ne 0 ] && [ $counter -gt 0 ]; do
    kubectl rollout status -n "$TSB_NS" deployment/central 2>/dev/null
    check=$?
    if [ $check -ne 0 ]; then
        counter=$((counter - 1))
        echo "waiting for Central" $counter
        sleep 10
    fi
done

if ! kubectl wait -n "$TSB_NS" --for=condition=Available --timeout=10m deployment/central 2>/dev/null; then
    echo "TSB deployment failed!"
    exit 1
else
    echo "TSB deployment succeeded"
fi

kubectl delete job -n "$TSB_NS" teamsync-bootstrap 2>/dev/null
kubectl create job -n "$TSB_NS" teamsync-bootstrap --from=cronjob/teamsync 2>/dev/null
kubectl wait -n "$TSB_NS" --for=Condition=Completed job -n "$TSB_NS" teamsync-bootstrap 2>/dev/null

echo "Waiting for TSB IP/hostname..."
TCCIP=$(getTCCIP)
while [[ -z ${TCCIP} ]]; do
    TCCIP=$(getTCCIP)
    sleep 5
done

if [[ -z "$TCCIP" ]]; then
    echo "Unable to obtain TSB IP"
    exit 1
else
    echo "TSB Front Envoy Address " "$TCCIP"
fi
updateRoute53 "${DEPLOYMENT_NAME}"-tsb."${DNS_DOMAIN}" "$TCCIP" ${DNS_RECORD_TYPE}
tctlCLIConfig
createTrafficGenerator

if ! tctl apply -f /tmp/tctl.yaml; then
    echo "tctl constructs are not applied!"
    exit 1
else
    echo "tctl settings are successfully applied"
fi

echo ==========================
echo TSB UI Access
echo --------------------------
echo
echo https://"${DEPLOYMENT_NAME}"-tsb."${DNS_DOMAIN}":8443
echo
echo Credentials are admin/"$TSB_ADMIN_PASS"
echo
echo ==========================
