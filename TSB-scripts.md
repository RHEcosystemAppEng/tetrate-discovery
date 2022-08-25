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

So far, clean up includes only the management plane (Perform this at your own risk, this has part is not yet finished)

```bash
k delete svc,deploy,sts,rs,cm,pvc,sa,secret,po,job,role,rolebinding -n tsb --all --force --grace-period=0;

kubectl delete ns tsb;

k get clusterrolebinding | grep tsb | awk '{print $1}' | xargs kubectl delete clusterrolebinding

k get clusterrole | grep tsb | awk '{print $1}' | xargs kubectl delete clusterrole  

kubectl delete clusterissuer selfsigned-issuer-management-plane


k get crd | grep cert | awk '{print $1}' | xargs kubectl delete crd         

k delete svc,deploy,sts,rs,cm,pvc,sa,secret,po,job,role,rolebinding -n cert-manager --all --force --grace-period=0;

kubectl delete ns cert-manager;
```