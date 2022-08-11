## Credentials files

file ~/credentials.env should be placed in the home directory:

```bash
APIUSER=${APIUSER:-"user-tetrate"} #bintray user to receive images 
APIKEY=${APIKEY:-"f....ffff"} #API key for bintray user above 
AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID:-"A....."} #key that is used for AWS updates 
AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY:-"s...."} #secret key for AWS account above 
ROUTE53_ACCESS_KEY=${ROUTE53_ACCESS_KEY:="A..."} #KEY that pairs with below ROUTE53_SECRET to update DNS records
ROUTE53_SECRET=${ROUTE53_SECRET:="q....."} #this secret is used by cert-manager (AWS account is currently hardcoded in cert-manager.yaml template
```
