echo **** MAKE sure you're in the CORRECT cluster (core-os-0-cp1) CONTEXT ***
# creating namespace
  kubectl create namespace istio-system 

#creating certificate for mutual trust
  kubectl create secret generic cacerts -n istio-system \
    --from-file=helpers/istio-certs/ca-cert.pem \
    --from-file=helpers/istio-certs/ca-key.pem \
    --from-file=helpers/istio-certs/root-cert.pem \
    --from-file=helpers/istio-certs/cert-chain.pem 

# installing operator
kubectl apply -f cp-core-os-0-cp1.yaml 

# applying secrets
kubectl apply -f cp-secrets-core-os-0-cp1.yaml 
kubectl apply -f xcp-central-ca-bundle.yaml 



# Deploying the cluster config - better to examine before applying
kubectl apply -f cp-site-core-os-0-cp1.yaml

# Deploy Bookinfo yaml
ROOT=${PWD} TIER2_NS=bookinfo helpers/bookinfo_ocp_deployment.sh 
