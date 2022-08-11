# TSB Install via Scripts

Ensure your images are in repo
```bash
 ./demo-scripts/deployment/00-download.sh coreos
```

Copy credentials.env to `~/.credentials.env`

Make sure demo-scripts/variables/coreos.env is correct
```
line 11 should be the Clusters (Management and then remote CP )
line 27 should be the OCP kubeadmin passwords
```

Deploy Management Plane
```bash
 ./demo-scripts/deployment/01-deploy-management-plane.sh coreos
```

Generate a self-signed cert (ideally it would be from a proper ca)
```
./gen-cert.sh coreos-tsb-01 coreos-tsb-01.cx.tetrate.info .

k create secret tls -n tsb tsb-certs --cert=coreos-tsb-01.crt --key=coreos-tsb-01.key  
```
Type "thisisunsafe" in the chrome browser to see UI

If you do not want to use DNS we need name of the LoadBalancer service, you cannot get it until Envoy is deployed.

Action Items:
```
Look into creating an OpenShift route based on the envoy service in TSB
```
---

Control Plane
```bash
 ./demo-scripts/deployment/02a-manual-deploy-cp.sh coreos 0
```

To deploy the actual manifests on the CP
```
sudo cat /tmp/command-tetrate-mp-cp.sh
# apply this ^
```


Give to Petr in a tar:
coreos.env
credentials.env
and coreos certs