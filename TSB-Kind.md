# TSB on Helm

_Typically, TSB would be installed on at least 3 clusters for the management plane, global control plane, and data plane, respectively. TSB's demo profile is simplified "batteries included" install experience that includes PostgreSQL, Elasticsearch, and LDAP running on the Kind cluster._

**TOC**
- [Prereqs](#prereqs)


## Prereqs

The prereqs for running TSB's demo profile include spinning up a kind cluster, installing `tctl`, and installing `metallb`.


Create the Kind cluster.

```yaml
cat <<EOF | kind create cluster --config=-
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: tsb-demo
nodes:
- role: control-plane
  kubeadmConfigPatches:
  - |
    kind: InitConfiguration
    nodeRegistration:
      kubeletExtraArgs:
        node-labels: "ingress-ready=true"
  extraPortMappings:
  - containerPort: 80
    hostPort: 80
    protocol: TCP
  - containerPort: 443
    hostPort: 443
    protocol: TCP
- role: worker
- role: worker
EOF
```

Install `tctl`, the following instructions are for mac, find instructions for linux [here](https://docs.tetrate.io/service-bridge/1.5.x/en-us/reference/cli/guide/index#installation).

```bash
mkdir -p ~/.tctl/bin
curl -Lo ~/.tctl/bin/tctl https://binaries.dl.tetrate.io/public/raw/versions/darwin-amd64-1.5.0/tctl
chmod +x ~/.tctl/bin/tctl
sudo xattr -r -d com.apple.quarantine ~/.tctl/bin/tctl
export PATH=$PATH:~/.tctl/bin
```

Install `metallb` using the default manifests.

```bash
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.12.1/manifests/namespace.yaml

kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.12.1/manifests/metallb.yaml
```

Wait for metallb pods to have a status of `running`.

```bash
kubectl wait --for=condition=ready pod -n metallb-system -l app=metallb 
```

Setup address pool used by loadbalancers. This output will contain a cidr such as 172.18.0.0/16 - we want our loadbalancer IP to come from this subclass.

```bash
docker network inspect -f '{{.IPAM.Config}}' kind
```

output
```
[{172.18.0.0/16  172.18.0.1 map[]} {fc00:f853:ccd:e793::/64   map[]}]
```

Create the `metallb` config for the LoadBalancer IP addresses:

```yaml
kubectl apply -f -<<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  namespace: metallb-system
  name: config
data:
  config: |
    address-pools:
    - name: default
      protocol: layer2
      addresses:
      - 172.18.255.200-172.18.255.250
EOF
```

Test `metallb` and loadabalancer configuration by deploying a simple nginx app and exposing it as type `LoadBalancer`.

```bash
kubectl run nginx --image=nginx --port=80 --expose

kubectl patch svc/nginx -p '{"spec":{"type":"LoadBalancer"}}'
```

Exec into the node, and curl the nginx service via the `LoadBalancer` external-ip

```bash
LB_IP=$(kubectl get svc nginx -ojsonpath='{ .status.loadBalancer.ingress[0].ip }')

docker exec tsb-demo-control-plane curl $LB_IP
```

output

```html
<!DOCTYPE html>
<html>
<head>
<title>Welcome to nginx!</title>
<style>
html { color-scheme: light dark; }
body { width: 35em; margin: 0 auto;
font-family: Tahoma, Verdana, Arial, sans-serif; }
</style>
</head>
<body>
<h1>Welcome to nginx!</h1>
<p>If you see this page, the nginx web server is successfully installed and
working. Further configuration is required.</p>

<p>For online documentation and support please refer to
<a href="http://nginx.org/">nginx.org</a>.<br/>
Commercial support is available at
<a href="http://nginx.com/">nginx.com</a>.</p>

<p><em>Thank you for using nginx.</em></p>
</body>
</html>
```

## Clean Up

Since this is an ephemeral environment, we will delete the kind cluster.

```bash
kind delete clusters tsb-demo
```
