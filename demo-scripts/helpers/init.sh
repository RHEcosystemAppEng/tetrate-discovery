#!/bin/bash

ROOT=$(git rev-parse --show-toplevel)/demo-scripts

if [ $# -eq 0 ]; then
    echo "No arguments provided = please specify parameter file name"
    exit 1
else
    if [[ $1 == *"env"* ]]; then
        filename=$1
    else
        filename="${1}.env"
    fi
    
    if ! source "$ROOT"/variables/"$filename" >/dev/null; then
        echo "cant find ${ROOT}/variables/${filename} exiting"
        exit 1
    else
        echo "using ${ROOT}/variables/${filename}"
    fi
fi

source ~/credentials.env

if [ -z "$ORG" ]; then
   export ORG=$DEPLOYMENT_TYPE-$DEPLOYMENT_NAME-org
fi

