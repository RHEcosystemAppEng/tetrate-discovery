## Credentials files

file ~/credentials.env should be placed in the home directory:

```bash
APIUSER=${APIUSER:-"user-tetrate"} #bintray user to receive images 
APIKEY=${APIKEY:-"f....ffff"} #API key for bintray user above 
declare -a OC_PASSWORDS=("kubeadmin-password-cluster1" "kubeadmin-password-cluster2" )
```
