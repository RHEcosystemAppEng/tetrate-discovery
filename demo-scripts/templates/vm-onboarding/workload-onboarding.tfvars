# AWS region for all resources
aws_region                  = \"${REGION_LIST[${VM_CLUSTER}]}\"

# Linux distribution to use
linux_distro                = \"rhel-8\"

# Address of the Workload Onboarding Endpoint
onboarding_endpoint_address = \"${ONBOARDING_ENDPOINT_ADDRESS} \"

# Tags to be compliant with AWS account tag policy AWS account tetrate-test (192760260411)

tags = {
  \"Tetrate:Owner\" = \"${OWNER_NAME}@tetrate.io\"
}

# Certificate of the Example CA
example_ca_certificate      = <<EOF
${VM_CA_CERT}
EOF

