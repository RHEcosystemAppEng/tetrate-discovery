kubectl get -n tsb secret xcp-central-cert -o=json | jq -r '.data."ca.crt"' | base64 -d >/tmp/ca.crt

kubectl patch managementplanes.install.tetrate.io tsbmgmtplane -n tsb \
--patch "$(cat templates/mp-jwt-support.yaml)" \
--type merge

kubectl -n istio-system create secret generic xcp-central-ca-bundle --from-file=ca.crt=/tmp/ca.crt

kubectl patch controlplanes.install.tetrate.io controlplane -n istio-system \
--patch "$(cat templates/cp-jwt-support.yaml)" \
--type merge
