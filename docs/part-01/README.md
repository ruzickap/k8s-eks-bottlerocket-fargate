# Amazon EKS Bottlerocket and Fargate

![Amazon EKS](https://raw.githubusercontent.com/cncf/landscape/7f5b02ecba914a32912e77fc78e1c54d1c2f98ec/hosted_logos/amazon-eks.svg?sanitize=true
"Amazon EKS")

Before starting with the main content, it's necessary to provision
the [Amazon EKS](https://aws.amazon.com/eks/) in AWS.

Use the `MY_DOMAIN` variable containing domain and `LETSENCRYPT_ENVIRONMENT`
variable.
The `LETSENCRYPT_ENVIRONMENT` variable should be one of:

* `staging` - Let’s Encrypt will create testing certificate (not valid)

* `production` - Let’s Encrypt will create valid certificate (use with care)

```bash
export MY_DOMAIN=${MY_DOMAIN:-mylabs.dev}
export LETSENCRYPT_ENVIRONMENT=${LETSENCRYPT_ENVIRONMENT:-staging}
echo "${MY_DOMAIN} | ${LETSENCRYPT_ENVIRONMENT}"
```

## Prepare the local working environment

::: tip
You can skip these steps if you have all the required software already
installed.
:::

Install necessary software:

```bash
if [[ -x /usr/bin/apt-get ]]; then
  apt update -qq
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq ansible awscli git jq sudo
fi
```

Install [kubectl](https://github.com/kubernetes/kubectl) binary:

```bash
if [[ ! -x /usr/local/bin/kubectl ]]; then
  sudo curl -s -Lo /usr/local/bin/kubectl https://storage.googleapis.com/kubernetes-release/release/v1.18.10/bin/linux/amd64/kubectl
  sudo chmod a+x /usr/local/bin/kubectl
fi
```

Install [Helm](https://helm.sh/):

```bash
if [[ ! -x /usr/local/bin/helm ]]; then
  curl https://raw.githubusercontent.com/helm/helm/master/scripts/get | bash -s -- --version v3.3.4
fi
```

Install [eksctl](https://eksctl.io/):

```bash
if [[ ! -x /usr/local/bin/eksctl ]]; then
  curl -s -L "https://github.com/weaveworks/eksctl/releases/download/0.30.0/eksctl_Linux_amd64.tar.gz" | sudo tar xz -C /usr/local/bin/
fi
```

Install [AWS IAM Authenticator for Kubernetes](https://github.com/kubernetes-sigs/aws-iam-authenticator):

```bash
if [[ ! -x /usr/local/bin/aws-iam-authenticator ]]; then
  sudo curl -s -Lo /usr/local/bin/aws-iam-authenticator https://amazon-eks.s3.us-west-2.amazonaws.com/1.18.8/2020-09-18/bin/linux/amd64/aws-iam-authenticator
  sudo chmod a+x /usr/local/bin/aws-iam-authenticator
fi
```

## Configure AWS

Authorize to AWS using AWS CLI: [https://docs.aws.amazon.com/cli/latest/userguide/cli-chap-configure.html](https://docs.aws.amazon.com/cli/latest/userguide/cli-chap-configure.html)

```bash
aws configure
...
```

Create DNS zone:

```bash
aws route53 create-hosted-zone --output json \
  --name ruzickap-k8s-01.${MY_DOMAIN} \
  --caller-reference "$(date)" \
  --hosted-zone-config="{\"Comment\": \"Created by petr.ruzicka@gmail.com\", \"PrivateZone\": false}" | jq
```

Use your domain registrar to change the nameservers for your zone (for example
"mylabs.dev") to use the Amazon Route 53 nameservers. Here is the way how you
can find out the the Route 53 nameservers:

```bash
NEW_ZONE_ID=$(aws route53 list-hosted-zones --query "HostedZones[?Name==\`ruzickap-k8s-01.mylabs.dev.\`].Id" --output text)
NEW_ZONE_NS=$(aws route53 get-hosted-zone --output json --id ${NEW_ZONE_ID} --query "DelegationSet.NameServers")
NEW_ZONE_NS1=$(echo ${NEW_ZONE_NS} | jq -r '.[0]')
NEW_ZONE_NS2=$(echo ${NEW_ZONE_NS} | jq -r '.[1]')
```

Create the NS record in "mylabs.dev" for proper zone delegation.
This step depends on your domain registrar - I'm using CloudFlare and using
Ansible to automate it:

```shell
ansible -m cloudflare_dns -c local -i "localhost," localhost -a "zone=mylabs.dev record=ruzickap-k8s-01 type=NS value=${NEW_ZONE_NS1} solo=true proxied=no account_email=${CLOUDFLARE_EMAIL} account_api_token=${CLOUDFLARE_API_KEY}"
ansible -m cloudflare_dns -c local -i "localhost," localhost -a "zone=mylabs.dev record=ruzickap-k8s-01 type=NS value=${NEW_ZONE_NS2} solo=false proxied=no account_email=${CLOUDFLARE_EMAIL} account_api_token=${CLOUDFLARE_API_KEY}"
```

## Create Amazon EKS

![EKS](https://raw.githubusercontent.com/aws-samples/eks-workshop/65b766c494a5b4f5420b2912d8373c4957163541/static/images/3-service-animated.gif
"EKS")

Generate SSH key if not exists:

```bash
test -f $HOME/.ssh/id_rsa || ( install -m 0700 -d $HOME/.ssh && ssh-keygen -b 2048 -t rsa -f $HOME/.ssh/id_rsa -q -N "" )
```

Clone the [k8s-eks-bottlerocket-fargate](https://github.com/ruzickap/k8s-eks-bottlerocket-fargate)
Git repository if it wasn't done already:

```bash
if [ ! -d .git ]; then
  git clone --quiet https://github.com/ruzickap/k8s-eks-bottlerocket-fargate
  cd k8s-eks-bottlerocket-fargate
fi
```

Create [Amazon EKS](https://aws.amazon.com/eks/) in AWS by using [eksctl](https://eksctl.io/).
It's a tool from [Weaveworks](https://weave.works/) based on official
AWS CloudFormation templates which will be used to launch and configure our
EKS cluster and nodes.

![eksctl](https://raw.githubusercontent.com/weaveworks/eksctl/c365149fc1a0b8d357139cbd6cda5aee8841c16c/logo/eksctl.png
"eksctl")

Create the configuration file for `eksctl`:

```bash
test -d tmp || mkdir tmp
cat > tmp/bottlerocket.yaml << EOF
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig

metadata:
  name: ruzickap-k8s-01
  region: eu-central-1
  version: "1.17"
  tags:
    Owner: petr.ruzicka@gmail.com
    Environment: Dev
    Tribe: Cloud Native
    Squad: Cloud Container Platform

nodeGroups:
  - name: ng01
    availabilityZones: ["eu-central-1a"] # use single AZ to optimise data transfer between instances
    instanceType: t3.large
    desiredCapacity: 2
    minSize: 2
    maxSize: 2
    volumeSize: 20
    volumeType: standard
    volumeEncrypted: true
    amiFamily: Bottlerocket
    labels:
      node-class: "my-worker-node"
    tags:
      Owner: petr.ruzicka@gmail.com
      Environment: Dev
      Tribe: Cloud Native
      Squad: Cloud Container Platform
    iam:
      attachPolicyARNs:
        - arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy
        - arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy
        - arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly
        - arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore
      withAddonPolicies:
      #   albIngress: true
      #   autoScaler: true
      #   cloudWatch: true
        ebs: true
      #   fsx: true
      #   efs: true
      #   externalDNS: true
      #   certManager: true
    bottlerocket:
      enableAdminContainer: true
      settings:
        motd: "Hello, eksctl!"
    ssh:
      # Enable ssh access (via the admin container)
      allow: true
      publicKeyPath: ~/.ssh/id_rsa.pub
fargateProfiles:
  - name: fp-default
    selectors:
      # All workloads in the "default" Kubernetes namespace matching the following
      # label selectors will be scheduled onto Fargate:
      - namespace: default
        labels:
          fargate: "true"
  - name: fp-fargate-workload
    selectors:
      # All workloads in the "fargate-workload" Kubernetes namespace will be
      # scheduled onto Fargate:
      - namespace: fargate-workload

cloudWatch:
    clusterLogging:
      # enable specific types of cluster control plane logs
      enableTypes: ["audit", "authenticator", "controllerManager"]
      # all supported types: "api", "audit", "authenticator", "controllerManager", "scheduler"
      # supported special values: "*" and "all"
EOF
```

Create the Amazon EKS cluster using `eksctl`:

```bash
eksctl create cluster --config-file tmp/bottlerocket.yaml --kubeconfig kubeconfig.conf
```

Set `KUBECONFIG`:

```bash
export KUBECONFIG=kubeconfig.conf
```

Check the nodes:

```bash
kubectl get nodes -o wide
```
