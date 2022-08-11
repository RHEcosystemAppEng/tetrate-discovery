#!/bin/bash

ROOT=$(git rev-parse --show-toplevel)/demo-scripts

source "$ROOT"/helpers/functions.sh >/dev/null

eval "echo \"$(cat "$ROOT"/templates/cert-manager.yaml)\"" >/tmp/cert-manager.yaml
eval "echo \"$(cat "$ROOT"/templates/tctl_base.yaml)\"" >/tmp/tctl.yaml
eval "echo \"$(cat "$ROOT"/templates/tier1gw.yaml)\"" >/tmp/tier1gw.yaml
# eval "echo \"$(cat "$ROOT"/templates/bookinfo-openapi.yaml)\"" >/tmp/bookinfo-openapi.yaml
eval "echo \"$(cat "$ROOT"/templates/traffic_generator.yaml)\"" >/tmp/traffic_generator.yaml

if [[ ${TIER1_CLUSTER} != "X" ]]; then
  read -a BOOKINFO_CLUSTERS < <(identifyBookinfoCP)
  eval "echo \"$(cat "$ROOT"/templates/tctl_tier1.yaml)\"" >>/tmp/tctl.yaml
fi
