#!/bin/bash
ROOT=$(git rev-parse --show-toplevel)/demo-scripts
REPO=docker.io/cmwylie19
if ! source "$ROOT"/helpers/init.sh; then exit 1; fi

sudo rm /usr/local/bin/tctl

echo "Downloading ""${ARCH}"" ${VERSION} of tctl"

if ! sudo wget -O /usr/local/bin/tctl https://binaries.dl.tetrate.io/public/raw/versions/"${ARCH}"-"${VERSION}"/tctl -o /dev/null; then
       echo "can't download https://binaries.dl.tetrate.io/public/raw/versions/"${ARCH}"-${VERSION}/tctl Exiting"
       exit 1
fi

sudo chmod a+x /usr/local/bin/tctl
echo "${GCP_PROJECT}"
# if [[ -n  ${GCP_PROJECT} ]] ; then
# if ! gcloud projects describe "${GCP_PROJECT}" --no-user-output-enabled; then
#        echo "can't access GCP project ${GCP_PROJECT} Make sure the project exist and you have a proper access. Exiting"
#        exit 1
#    else
#        [[ ! -z "$GCP_REGISTRY" ]] && REPO=$GCP_REGISTRY || REPO="gcr.io/${GCP_PROJECT}"
# fi
# fi
tctl install image-sync --username "$APIUSER" --apikey "$APIKEY" --registry "$REPO"
# for ((i = 0; i < ${#CLUSTER_LIST[@]}; i++)); do
#        if [[ ${CLUSTER_PLATFORM[$i]} =~ ^(amazon|aws|ocp)$ ]]; then
#               REPO="${AWS_ACCOUNT}.dkr.ecr.${REGION_LIST[$i]}.amazonaws.com/cx-aws-demo-repo"
#               echo "uploading to the $REPO"

#               if ! aws ecr get-login-password --region "${REGION_LIST[$i]}" | docker login --username AWS --password-stdin "${REPO}"; then
#                      echo "can't access AWS ECR ${REPO} - Make sure you have the correct access using ~/credentials.env file. Exiting"
#                      exit 1
#               fi

#               tctl install image-sync --username "$APIUSER" --apikey "$APIKEY" --registry "${REPO}"
#        fi
# done
