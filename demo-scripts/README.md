# tsb-demo

the set of scripts to setup a demo for Tetrate CX demo with latest bits (or version that you prefer in the limits of backward/forward compatibility)
The current TSB version tested with these scripts is 1.5.0-EA2

#### The implementation includes the following components:
(all scripts have logic to wait for the dependandancy operation before proceeding to the next step - however if the script fail - it should be save to rerun them and complete the tasks that could timeout)

the **all** scripts require the second argument of your variables config file
- variable files are located in `varialbes` directory and have `.env` extension
- when specified in the script only name is needed (no extension or location) e.g. `./<script_name>.sh demo` will use varialbes/demo.env file (the full name will also be processed - e.g. `./<script_name>.sh demo.env`)

- _script `00`_ downloads `tctl` corresponding to the version specified in the env file and distributes to the repos listed in env file. Also `tctl` binary is put in the default path of Ubuntu (didn't confirm other shell versions) and will run for all following commands
- _script `01`_ deploys MP Kubernetes cluster (based on the variable value `MP_CLUSTER`), installs Cert Manager, installs TSB, configures tctl access, applies tctl manifests - please note that number of public certs issued is limited per user/per time period. cert-manager troubleshooting should be done according to the documenation of `cert-manager`
- _script `02`_ creates Kuberentes cluster in Region specified in Environment file, adds the cluster to TSB (aka installs TSB CP), installs TSB bookinfo or Tier1 GW. The script requies additional parameter as the cluster selector - 0..<total clusters specified -1> (if run without the parameter the list of clusters with associated names and numbers is printed)
- _script `03a`_ deploys VM in GCP, installs docker and adds it to the namespace with bookinfo in the cluster specified in the environment file.
- _script `03b`_ uses TSB 1.4+ to deploy AWS Autoscalling VM group (terraform needs to be installed on admin machine for this step to be succesful)
- _script `20`_ fetches all command line and URL settings to access the environment -  specified as parameter - file variables/<deployment_name>.env is used (the only validation if VM is deployed - all other commands are provided under assumption that the environment is deployed and functions properly.
- _script `99`_ uses spefified varialbe file to remove all components created by all other scripts
- _script `helpers/deploy-openapi.sh`_ can be used to redeploy bookinfo deployed by _script `02`_ and add OpenApi support for the calls such as `/api/v1/products/3/reviews`

- _`templates`_ directory has all required templates - some are parsed by helper/parser.sh script that is called by deployment scripts, some via direct calls
- _`helpers`_ directory has multiple scripts
- _`functions.sh`_ has all operations from deployment separated, also there a script that is transferred to and executed on VM and multiple others to deploy apps etc.
- _`vm_tf`_ is slightly modified subtree of [repo created by Yaro](https://github.com/tetrateio/onboarding-quickstart-terraform)

#### Requirements:
- _`kubectl`_ version **1.20** is installed
- _`aws cli`_ is installed and configured - the account has access to repo, cloudformation and route53
- _`gcloud`_ is installed and configured - access to all project resources (project is defined in the definition directory)
- _`terraform`_ if plan to run _03b_ autoscalling script
- _`jq`_ is used extensively by different fetching commands
- _`credentials file`_ exist and has the items explained in [here](credentials.md) - *this is an addition to variable files - as credentials shouldn't be placed in public repo*
- _`ssh keys`_ to access **single VM in GCP** are VM_ are located in home directory: `~/.ssh/google_compute_engine` and `~/.ssh/google_compute_engine.pub`
- _`ssh keys`_ to access **autoscaled VM** are located in `vm_tf/asg` directory


#### Variables details specified in variables directories

- _Self-expanatory parameters_ _`TSB_ADMIN_PASS`_, _`OWNER_NAME`_, _`TIER1_NS`_, _`TIER2_NS`_, _`TSB_NS`_, _`VM_NAME`_, _`AWS_ACCOUNT`_ 
- _`GCP_PROJECT`_ the same project is used for both GCP clusters and VM, needs to be empty ("") if the deployment without GCP Project - so all logic will ignore GCP
- _`MP_CLUSTER`_ - index of Management plane cluster relative to CLUSTER_LIST array (starts with 0)
- _`TIER1_CLUSTER`_ - index for the cluster that will be Tier1
- _`GCP_REGISTRY`_ - can be used for custom gcp registries such as us-docker.pkg.dev/cx-shared-demo-2/tsb - if not specified or empty ("") gcr.io for the GCP Project will be used
- _`VM_CLUSTER`_ - index of the cluster where VM will be connected to
- _`SUFFIX`_ is used to easily add common part for multiple objects
- _`REGION_LIST`_ - array of Regions that match in sequence clusters in CLUSTER_LIST array
- _`CLUSTER_PLATFORM`_ - array that specifies "amazon" or "gcp" for each cluster (no other values are accepted)
- _`CLUSTER_LIST`_ - array has clusters logical names (that partially generated based on SUFFIX value)
- _`REGION`_ array has regions that should match in sequence CLUSTER definition, the same for REPO
- _`ECK_STACK_ENABLED`_ - if `true` then [ECK](https://www.elastic.co/guide/en/cloud-on-k8s/current/k8s-overview.html) will be deployed otherwise demo elastic is configured
- _`DEPLOYMENT_NAME`_ - very impotant to change also _note_ that LetsEncrypt will use this varialbe for the tls.key/crt - so it's like to reject the request for existing cert - this variable needs to be change _everytime_ when deploying
- _`DNS_DOMAIN`_ will be used as suffix for TSB UI and bookinfo apps
- _the proper access`_ is must for GCP_REPO (gcloud config needs to be tested before the deployment) and AWS_REPO (aws config or rapture)
- _`DEPLOYMENT_TYPE`_ - additional identifier label for the deployment - "cx" is completely fine
- _`ISTIO_DIR`_ - the directory is used for deploying the sample certs and bookinfo app - without proper location - the deployment will not be functional and mTLS between cluster will not work
- _`HOSTEDZONEID`_ - AWS parameter that is used for updating DNS hosted zone - if changed - aws account needs to have access to the zone 
- _`SSH_USER`_ used in combination with `~/.ssh/google_compute_engine` and `~/.ssh/google_compute_engine.pub` to bootstrap the VM
