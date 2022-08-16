# TSB Install via Scripts

- [Sync Images](#sync-images)
- [Script Prereqs](#script-prereqs)
- [Management Plane](#management-plane)
- [Control Plane](#control-plane)

## Sync Images

- Make sure `demo-scripts/deployment/00-download.sh` has your repo under `REPO` on line 3.

- Copy `credentials.md` to `~/.credentials.env` and ensure `APIUSER` and `APIKEY` are adjusted according to the credentials given by Tetrate.

Run script to pull images and push to your personal repo
```bash
./demo-scripts/deployment/00-download.sh coreos
```

## Script Prereqs

Make sure demo-scripts/variables/coreos.env is correct
```
line 11 should be the Clusters names (Management and then remote CP )
line 27 should be the OCP kubeadmin passwords
```


## Management Plane

Now, we need to deploy the management plane, generate a self-signed cert to the Envoy service in the TSB namespace.


```bash
OCP_DOMAIN=$(oc get ingresses.config/cluster -o jsonpath={.spec.domain})

./gen-cert.sh envoy-tsb envoy-tsb.$OCP_DOMAIN .
```

Deploy Management Plane and create the `tsb-certs` secret
```bash
# (If this command hangs, then delete the clusterissuer)
./demo-scripts/deployment/01-deploy-management-plane.sh coreos

kubectl create secret tls -n tsb tsb-certs --cert=envoy.crt --key=envoy.key  
```


If you are unable to see the Envoy service in the browser. Type "thisisunsafe" in the chrome browser to see UI



## Control Plane
```bash
 ./demo-scripts/deployment/02a-manual-deploy-cp.sh coreos 0
```

To deploy the actual manifests on the CP
```
sudo cat /tmp/command-tetrate-mp-cp.sh
# apply this ^
```
