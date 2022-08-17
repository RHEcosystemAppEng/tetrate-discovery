# Tetrate Service Bridge on OpenShift 4.10

_Deploy TSB on OpenShift 4.10. We will have a cluster for the management plane and global control plane, and a second cluster with a local control plane and a data plane._

**TOC**
- [Prereqs](#prereqs)
- [Management Plane](#management-plane)
- [Remote Control Plane and Data Plane](#remote-control-plane-and-data-plane)
- [Clean Up](#clean-up)

## Prereqs

Configure the Helm repo

```bash
helm repo add tetrate-tsb-helm 'https://charts.dl.tetrate.io/public/helm/charts/'
helm repo update
```

List available versions

```
helm search repo tetrate-tsb-helm -l
```


Sync TSB Images by pulling them down locally, and pushing them to your personal repository.

This is necessary because Tetrate is keeping images under credentials. This command takes a while as it pulls and pushes ~5g of images. _This only needs to occur once._

```bash
docker login 

tctl install image-sync --username <username> \
    --apikey <api-key> --registry docker.io/cmwylie19
```


## Management Plane

_Installs the TSB Management Plane Operator and Global Control Plane._

Create the management-plane namespace and generate the necessary secrets.

```yaml
kubectl create ns tsb

kubectl apply -f -<<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  creationTimestamp: null
  name: system:openshift:scc:anyuid
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: system:openshift:scc:anyuid
subjects:
- kind: ServiceAccount
  name: tsb-operator-management-plane
  namespace: tsb
EOF
    
tctl install manifest management-plane-secrets  -y  \
--tsb-admin-password password \
--elastic-username admin \
--postgres-password password \
--postgres-username admin \
--tsb-admin-password password | kubectl apply -f -
# --xcp-certs |  kubectl apply -f -

# --xcp-certs https://docs.tetrate.io/service-bridge/1.5.x/en-us/setup/self_managed/management-plane-installation
```

output
```bash
secret/admin-credentials created
secret/tsb-certs created
secret/postgres-credentials created
secret/elastic-credentials created
secret/ldap-credentials created
```

output
```
secret/xcp-trust-anchor created
issuer.cert-manager.io/xcp-trust-anchor created
certificate.cert-manager.io/xcp-identity-issuer created
issuer.cert-manager.io/xcp-identity-issuer created
certificate.cert-manager.io/xcp-central-cert created
certificate.cert-manager.io/mpc-certs created
secret/admin-credentials created
secret/tsb-certs created
secret/postgres-credentials created
secret/elastic-credentials created
secret/ldap-credentials created
```

Deploy the Management Plane Operator through helm

```bash
helm install mp tetrate-tsb-helm/managementplane -n tsb \
--set image.registry=docker.io/cmwylie19 \
--set image.tag=1.5.0 
 ```

Wait for the TSB operator to be ready

```bash
kubectl wait --for=condition=ready pod -l name=tsb-operator -n tsb --timeout=180s
```
Give ManagementPlane Service Accounts RBAC permissions

```bash
oc adm policy add-scc-to-user anyuid -n tsb -z tsb-iam
oc adm policy add-scc-to-user anyuid -n tsb -z tsb-oap
```

Launch an instance of the ManagementPlane operator

```yaml
kubectl apply -f -<<EOF
apiVersion: install.tetrate.io/v1alpha1
kind: ManagementPlane
metadata:
  name: mp
  namespace: tsb
spec:
  hub: docker.io/cmwylie19
  organization: redhat-appeng
EOF
```

Wait for pods to be ready

```bash
kubectl wait --for=condition=ready pod -l app=zipkin -n tsb
kubectl wait --for=condition=ready pod -l app=web -n tsb
kubectl wait --for=condition=ready pod -l app=oap -n tsb
kubectl wait --for=condition=ready pod -l app=iam -n tsb
kubectl wait --for=condition=ready pod -l app=envoy -n tsb
kubectl wait --for=condition=ready pod -l app=elasticsearch -n tsb
kubectl wait --for=condition=ready pod -l app=ldap -n tsb
kubectl wait --for=condition=ready pod -l app=mpc -n tsb
```

Configure `tctl`'s default config profile to point to your TSB cluster. On GCP, use `.status.loadBalancer.ingress[0].ip` on AWS use `.status.loadBalancer.ingress[0].hostname`.   

```bash
tctl config clusters set tetrate-mp-cp-cluster  --bridge-address $(kubectl get svc -n tsb envoy --output jsonpath='{.status.loadBalancer.ingress[0].hostname}'):8443 --tls-insecure

tctl config users set tetrate-mp-cp-admin --org redhat-appeng --tenant admin --username admin --password password

tctl config profiles set tetrate-mp-cp-profile --cluster tetrate-mp-cp-cluster --username tetrate-mp-cp-admin

tctl config profiles set-current tetrate-mp-cp-profile
```

Check the dashboard

```bash
tctl ui -p tetrate-mp-cp-profile
```

Login

```
tctl login --org redhat-appeng --username admin --password password --tenant admin -p tetrate-mp-cp-profile
```

Configure the management plane to communication with data plane

```yaml
# cluster.yaml
apiVersion: api.tsb.tetrate.io/v2
kind: Cluster
metadata:
  name: tetrate-mp-cp-cluster # derived from cluster name in `tctl config view`
  organization: redhat-appeng
spec:
  tokenTtl: "8760h"

tctl apply -f cluster.yaml 
```

Check the clusters to ensure the dp cluster has been added

```bash
tctl get clusters
```

output

```
NAME                     DISPLAY NAME    DESCRIPTION 
tetrate-mp-cp-cluster                                    
```

## Remote Control Plane and Data Plane


_Installs the TSB Control Plane & Data Plane Operator on remote cluster._

**Background** The conrol plane operator manages Istio, SkyWalking, Zipkin and various other components. The data plane operator manages the gateways.

Add RBAC to allow control plane and data plane operator service accounts appropriate permissions

```bash
oc adm policy add-scc-to-user anyuid \
    system:serviceaccount:istio-system:tsb-operator-control-plane --context tetrate-dp
oc adm policy add-scc-to-user anyuid \
    system:serviceaccount:istio-gateway:tsb-operator-data-plane --context tetrate-dp
oc adm policy add-scc-to-user anyuid \
    system:serviceaccount:istio-system:xcp-edge --context tetrate-dp
oc adm policy add-scc-to-user anyuid \
    system:serviceaccount:istio-system:istio-system-oap --context tetrate-dp
```

Install operators for the control and data plane

```bash
tctl install manifest cluster-operators \
    --registry docker.io/cmwylie19 | kubectl apply --context tetrate-dp -f -
```

Wait for the remote control plane operator pod to be ready

```bash
kubectl wait --for=condition=ready pod -l name=tsb-operator -n istio-system --timeout=180s --context tetrate-dp
```


Create the service account that the cluster will use to authenticate with the management plane.

```bash
tctl install cluster-service-account \
    --cluster tetrate-mp-cp-cluster \
    > cluster-tsb-dp-service-account.jwk
```

Create the cluster-service-account secret that contains the Elasticsearch creds and service account key

```bash
tctl install manifest control-plane-secrets \
    --cluster tetrate-mp-cp-cluster \
    --cluster-service-account="$(cat cluster-tsb-dp-service-account.jwk)" |  kubectl apply --context tetrate-dp -f -
```



Create RBAC for the control plane 

```bash
oc adm policy add-scc-to-user anyuid -n istio-system -z istiod-service-account --context tetrate-dp # SA for istiod
oc adm policy add-scc-to-user anyuid -n istio-system -z vmgateway-service-account --context tetrate-dp 
oc adm policy add-scc-to-user anyuid -n istio-system -z istio-system-oap --context tetrate-dp 
oc adm policy add-scc-to-user privileged -n istio-system -z xcp-edge --context tetrate-dp 
```

Launch an instance of the ControlPlane operator

```yaml
kubectl delete --context tetrate-dp -f -<<EOF
apiVersion: install.tetrate.io/v1alpha1
kind: ControlPlane
metadata:
  name: controlplane
  namespace: istio-system
spec:
  components:
    internalCertProvider:
      certManager:
        managed: INTERNAL
    oap:
      kubeSpec:
        overlays:
          - apiVersion: extensions/v1beta1
            kind: Deployment
            name: oap-deployment
            patches:
              - path: spec.template.spec.containers.[name:oap].env.[name:SW_RECEIVER_GRPC_SSL_CERT_CHAIN_PATH].value
                value: /skywalking/pkin/tls.crt
              - path: spec.template.spec.containers.[name:oap].env.[name:SW_CORE_GRPC_SSL_TRUSTED_CA_PATH].value
                value: /skywalking/pkin/tls.crt
        service:
          annotations:
            service.beta.openshift.io/serving-cert-secret-name: dns.oap-service-account
    istio:
      kubeSpec:
        CNI:
          binaryDirectory: /var/lib/cni/bin
          chained: false
          configurationDirectory: /etc/cni/multus/net.d
          configurationFileName: istio-cni.conf
        overlays:
          - apiVersion: install.istio.io/v1alpha1
            kind: IstioOperator
            name: tsb-istiocontrolplane
            patches:
              - path: spec.meshConfig.defaultConfig.envoyAccessLogService.address
                value: oap.istio-system.svc:11800
              - path: spec.meshConfig.defaultConfig.envoyAccessLogService.tlsSettings.caCertificates
                value: /var/run/secrets/kubernetes.io/serviceaccount/service-ca.crt
              - path: spec.values.cni.chained
                value: false
              - path: spec.values.sidecarInjectorWebhook
                value:
                  injectedAnnotations:
                    k8s.v1.cni.cncf.io/networks: istio-cni
      traceSamplingRate: 100
  hub: docker.io/cmwylie19
  telemetryStore:
    elastic:
      host: aa001249c6c874b9997a2f36c8aa405a-1399382799.ca-central-1.elb.amazonaws.com
      port: 8443
      selfSigned: true
  managementPlane:
    host: aa001249c6c874b9997a2f36c8aa405a-1399382799.ca-central-1.elb.amazonaws.com
    port: 8443
    selfSigned: true
    clusterName: tetrate-dp # remote cluster
  meshExpansion: {}
EOF

kubectl apply --context tetrate-dp -f -<<EOF
apiVersion: install.tetrate.io/v1alpha1
kind: ControlPlane
metadata:
  name: controlplane
  namespace: istio-system
spec:
  hub: docker.io/cmwylie19
  telemetryStore:
    elastic:
      host: aa001249c6c874b9997a2f36c8aa405a-1399382799.ca-central-1.elb.amazonaws.com
      port: 8443
      selfSigned: true
  managementPlane:
    host: aa001249c6c874b9997a2f36c8aa405a-1399382799.ca-central-1.elb.amazonaws.com
    port: 8443
    selfSigned: true
    clusterName: tetrate-dp # remote cluster
  meshExpansion: {}
EOF
```

## Clean Up

```
k delete svc,deploy,sts,rs,cm,pvc,sa,secret,po,job,role,rolebinding,hpa -n tsb --all --force --grace-period=0;

kubectl delete ns tsb;

k get clusterrolebinding | grep tsb | awk '{print $1}' | xargs kubectl delete clusterrolebinding

k get clusterrole | grep tsb | awk '{print $1}' | xargs kubectl delete clusterrole  

 k get crd | grep cert | awk '{print $1}' | xargs kubectl delete crd         

k delete svc,deploy,sts,rs,cm,pvc,sa,secret,po,job,role,rolebinding -n cert-manager --all --force --grace-period=0;

kubectl delete ns cert-manager;
```

[top](#tetrate-service-bridge-on-openshift-4.10)





TODO

```
tctl install manifest management-plane-secrets \
        --elastic-password tsb-elastic-password \
        --elastic-username tsb \
        --ldap-bind-dn cn=admin,dc=tetrate,dc=io \
        --ldap-bind-password admin \
        --postgres-password tsb-postgres-password \
        --postgres-username tsb \
        --tsb-admin-password "password" \
        --allow-defaults \
        --xcp-certs --tsb-tls-hostname  a6a12e7bc4ff5435a9cf4e2697b140b5-961723708.ca-central-1.elb.amazonaws.com
        --tsb-tls-org aaa

```