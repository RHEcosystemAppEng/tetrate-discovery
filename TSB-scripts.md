# TSB Install via Scripts

- [Sync Images](#sync-images)
- [Script Prereqs](#script-prereqs)
- [Management Plane](#management-plane)
- [Control Plane](#control-plane)
- [Clean Up](#clean-up)

## Sync Images

- Make sure `demo-scripts/deployment/00-download.sh` has your repo under `REPO` on line 3.

- Copy `credentials.md` to `~/credentials.env` and ensure `APIUSER` and `APIKEY` are adjusted according to the credentials given by Tetrate. `OC_PASSWORDS` should be the OCP kubeadmin passwords.

Run script to pull images and push to your personal image repo

```bash
./demo-scripts/deployment/00-download.sh coreos
```

## Script Prereqs

Configure `demo-scripts/variables/coreos.env`

- line 11 should be the Clusters names (Management Plane and Remote Control Plane ).
- line 27 should be the OCP kubeadmin passwords in an array.


## Management Plane

Check UI in browser. If you are unable to see the Envoy service in the browser. Type "thisisunsafe" in the chrome browser to see UI.

```bash
kubectl get route envoy -n tsb --template='{{ .spec.host }}'
```


## Control Plane
```bash
 ./demo-scripts/deployment/02a-manual-deploy-cp.sh coreos 0
```

To deploy the actual manifests on the CP
```
sudo cat /tmp/command-tetrate-mp-cp.sh
# apply this ^
```


## Clean Up

Clean up the application namespace:

```bash
# TSB resources
kubectl delete ingressgateway tsb-gateway-bookinfo -n bookinfo

# Istio Resources
kubectl delete gw,envoyfilter,sidecar,vs,net-attach-def --all -n bookinfo

# Kubernetes Resources
kubectl delete deploy,rolebinding,role --all --force --grace-period=0 -n bookinfo

# Secondary Kubernetes Resources
kubectl delete endpointslice,ep,svc,sa,secret,podmetrics,cm,hpa,poddisruptionbudget,po -n bookinfo --all --force --grace-period=0 -n bookinfo

# Delete the namespace
kubectl delete ns bookinfo
```


Clean up the Data Plane:

```bash
# TSB resources & you may need to remove finalizer first
kubectl delete istiooperator --all -n istio-gateway

# Kubernetes Resources
kubectl delete deploy,rolebinding,role,sa --all -n istio-gateway

# Secondary Kubernetes Resources
kubectl delete po,cm,secret,svc,ep,lease,endpointslice,podmetrics,job,cronjob --all --force --grace-period=0 -n istio-gateway

# Delete the namespace
kubectl delete ns istio-gateway
```

Clean up the Control Plane:

```bash
# TSB Resources & manually remove finalizer from istiooperator
# xcp-edge-internal edge-validation
kubectl delete controlplane,gatewaygroup,istiooperator,edgexcp,workspace,edgedirectory --all -n istio-system

# Network Resource
kubectl delete net-attach-def --all -n istio-system

# Istio Resources
kubectl delete dr,envoyfilter --all -n istio-system

# Cert Manager resource
kubectl delete issuer,certificaterequests,certificates --all -n istio-system

# Kubernetes Resources
kubectl delete deploy --all -n istio-system

# Secondary Kubernetes Resources
kubectl delete po,svc,ep,sa,hpa,rolebinding,role,hpa,endpointslice,podmetrics,poddisruptionbudget,job,cronjob --force --grace-period=0 --all -n istio-system

# Delete the namespace
kubectl delete ns istio-system
```

Clean Up the Management Plane:

```bash
# TSB resources
kubectl delete cluster,workspace,gatewaygroup,ingressgateway,tier1gateway,managementplane,centralxcp --all -n tsb

# Cert Manager resource
kubectl delete issuer,certificaterequests,certificates --all -n tsb

# Kubernetes Resources
kubectl delete deploy,netpol --all -n tsb

# Secondary Kubernetes Resources
kubectl delete po,cm,ep,pvc,route,svc,rolebinding,role,svc,sa,job,secret,cronjob,podmetrics --force --grace-period=0 --all -n tsb

# Delete the namespace
kubectl delete ns tsb
```

Clean Up the xcp-multicluster namespace:

```bash
# Istio Resources
kubectl delete dr,se --all -n xcp-multicluster

# Kubernetes Resources
kubectl delete cm,secret,sa,role,rolebinding,po,job,cronjob --force --grace-period=0  --all -n xcp-multicluster

# Delete the namespace
kubectl delete ns xcp-multicluster
```


Clean Up the Cert-Manager namespace:

```bash
# Cert-manager Resources
kubectl delete clusterissuer --all

# Kubernetes Resources
kubectl delete deploy,ep,endpointslice,podmetrics --all  -n cert-manager

# Secondary Kubernetes Resources
kubectl delete cm,secret,sa,role,rolebinding,po,job,cronjob --all --force --grace-period=0 -n cert-manager

# Delete the namespace
kubectl delete ns cert-manager
```


Clean Up cluster scoped resources:

```bash
kubectl get clusterrole | grep tsb | awk '{print $1}' | xargs kubectl delete clusterrole  

kubectl get clusterrole | grep istio | awk '{print $1}' | xargs kubectl delete clusterrole  

kubectl get clusterrole | grep cert-manager | awk '{print $1}' | xargs kubectl delete clusterrole 

kubectl get clusterrolebinding | grep tsb | awk '{print $1}' | xargs kubectl delete clusterrolebinding  

kubectl get clusterrolebinding | grep istio | awk '{print $1}' | xargs kubectl delete clusterrolebinding  

kubectl get clusterrolebinding | grep cert-manager | awk '{print $1}' | xargs kubectl delete clusterrolebinding
```

Clean Up the CRDS:

```bash
# Tetrate CRDs
kubectl get crd | grep tetrate | awk '{print $1}' | xargs kubectl delete crd

# Cert-manager CRDs
kubectl get crd | grep cert-manager | awk '{print $1}' | xargs kubectl delete crd
```
