#!/bin/bash

ROOT=$(git rev-parse --show-toplevel)/demo-scripts

source "$ROOT"/helpers/functions.sh >/dev/null

if ! source "$ROOT"/helpers/init.sh; then exit 1; fi

AWS_PREFIX=$(
  cat <<-END
echo eval "\$( command rapture shell-init )"
rapture init tetrate-hub
rapture assume tetrate-test/admin
END
)

if [[ ${CLUSTER_PLATFORM[$MP_CLUSTER]} =~ ^(oc|openshift|ocp)$ ]]; then
    if ! oc login https://api.${CLUSTER_LIST[$MP_CLUSTER]}.${DNS_DOMAIN}:6443 -u kubeadmin -p ${OC_PASSWORDS[$MP_CLUSTER]}; then
        echo "cannot connect to the cluster" >&2
        exit 1
    fi
    OCP_DOMAIN=$(oc get ingresses.config/cluster -o jsonpath={.spec.domain})
    BRIDGE_ADDRESS=tsb."$OCP_DOMAIN":443
else
    BRIDGE_ADDRESS="${DEPLOYMENT_NAME}"-tsb."${DNS_DOMAIN}":8443
fi

echo ==========================
echo tctl config
echo --------------------------
echo
echo tctl config clusters set "$ORG"-cluster \
--bridge-address "${BRIDGE_ADDRESS}" --tls-insecure
echo tctl config users set "$ORG"-admin \
--org "$ORG" \
--tenant "$ORG"-tenant \
--username admin --password "$TSB_ADMIN_PASS"
echo tctl config profiles set "$ORG"-profile \
--cluster "$ORG"-cluster \
--username "$ORG"-admin
echo tctl config profiles set-current "$ORG"-profile
echo
echo ==========================
echo tctl Parameters
echo --------------------------
echo
echo oranization: "$ORG"
echo tenant: "$ORG"-tenant
echo
echo user: admin
echo password: "$TSB_ADMIN_PASS"
echo
echo ==========================
echo TSB UI Access
echo --------------------------
echo
echo https://tsb."$OCP_DOMAIN":8443
# echo https://"${DEPLOYMENT_NAME}"-tsb."${DNS_DOMAIN}":8443
echo
echo Credentials are admin/"$TSB_ADMIN_PASS"
echo
echo ===============================
echo Product Page is accessable at
echo -------------------------------
echo
echo http://"$DEPLOYMENT_NAME"-bookinfo."$DNS_DOMAIN"/productpage
echo
echo ===============================
echo MP Cluster connection string:
echo oc login https://api.${CLUSTER_LIST[MP_CLUSTER]}.${DNS_DOMAIN}:6443 -u kubeadmin -p ${OC_PASSWORDS[$MP_CLUSTER]}
echo
echo
echo ===============================
echo CP Clusters connection strings:
echo ===============================
for ((i = 0; i < ${#CLUSTER_LIST[@]}; i++)); do
    if [ "$i" != "$MP_CLUSTER" ]; then
        echo to access cluster "${CLUSTER_LIST[${i}]}" use:
        if [[ ${CLUSTER_PLATFORM[${i}]} =~ ^(amazon|aws)$ ]]; then
            echo
            echo "${AWS_PREFIX}"
            echo
            echo aws eks --region "${REGION_LIST[${i}]}" update-kubeconfig --name "${CLUSTER_LIST[${i}]}"
            elif [[ ${CLUSTER_PLATFORM[$i]} =~ ^(oc|openshift|ocp)$ ]]; then
            echo oc login https://api.${CLUSTER_LIST[${i}]}.${DNS_DOMAIN}:6443 -u kubeadmin -p ${OC_PASSWORDS[${i}]}
        else
            echo
            echo gcloud container clusters get-credentials "${CLUSTER_LIST[${i}]}" --region "${REGION_LIST[${i}]}" --project "$GCP_PROJECT"
        fi
        echo ===============================
    fi
done
# VMIP=$(gcloud compute instances list --project "$GCP_PROJECT" --filter=NAME=$VM_NAME  --format='get(networkInterfaces[0].accessConfigs[0].natIP)')
# VMintIP=$(gcloud compute instances list --project "$GCP_PROJECT" --filter=NAME=$VM_NAME --format='get(networkInterfaces[0].networkIP)')
# if [ -z "$VMintIP" ] || [ -z "$VMIP" ]; then
#   echo "Not able to detect VM parameters - check if VM is running"
# else
#   echo GCP VM details
#   echo
#   echo Public IP: "$VMIP" Private IP: "$VMintIP"
#   echo
#   echo gcloud compute ssh "$VM_NAME" --project "$GCP_PROJECT"
#   echo
# fi

# if [[ $(setTFWorkspace $1) == *"success"* ]]; then
#   echo =====================================
#   echo Autoscalled VM Details \(if deployed\)
#   echo ====================================
#   echo Using ${TFWorkspace} for Autoscaled VM Details
#   AutoscallingGroup=$(terraform -chdir="$ROOT"/vm_tf/asg/ show -json | jq -r '.values.outputs.auto_scaling_group_id.value')
#   SshCommand=$(terraform -chdir="$ROOT"/vm_tf/asg/ show -json | jq -r '.values.outputs.ssh_commands.value |.[]')
#   echo Autoscaling group for VMs is ${AutoscallingGroup}
#   echo Login to autoscalled VM using the following command \(ssh.key is in vm_tf/asg directory\) ${SshCommand}
# fi
