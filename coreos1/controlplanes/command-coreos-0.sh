echo **** MAKE sure you're in the CORRECT cluster (coreos-0) CONTEXT ***
# creating namespace
  kubectl create namespace istio-system 

#creating certificate for mutual trust
  kubectl create secret generic cacerts -n istio-system \
    --from-file=helpers/istio-certs/ca-cert.pem \
    --from-file=helpers/istio-certs/ca-key.pem \
    --from-file=helpers/istio-certs/root-cert.pem \
    --from-file=helpers/istio-certs/cert-chain.pem 

# installing operator
kubectl apply -f cp-coreos-0.yaml 

# applying secrets
kubectl apply -f cp-secrets-coreos-0.yaml 
kubectl apply -f xcp-central-ca-bundle.yaml 



# Deploying the cluster config - better to examine before applying
kubectl apply -f cp-site-coreos-0.yaml
