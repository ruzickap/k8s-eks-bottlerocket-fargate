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
export MY_DOMAIN=${MY_DOMAIN:-kube1.mylabs.dev}
export LETSENCRYPT_ENVIRONMENT=${LETSENCRYPT_ENVIRONMENT:-staging}
echo "${MY_DOMAIN} | ${LETSENCRYPT_ENVIRONMENT}"
```

Prepare Google OAuth 2.0 Client IDs and AWS variables for access. You can find
the description how to do it here: [https://oauth2-proxy.github.io/oauth2-proxy/auth-configuration#google-auth-provider](https://oauth2-proxy.github.io/oauth2-proxy/auth-configuration#google-auth-provider)

```shell
export AWS_ACCESS_KEY_ID="AxxxxxxxxxxxxxxxxxxY"
export AWS_SECRET_ACCESS_KEY="txxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxh"
export MY_GOOGLE_OAUTH_CLIENT_ID="2xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx5.apps.googleusercontent.com"
export MY_GOOGLE_OAUTH_CLIENT_SECRET="OxxxxxxxxxxxxxxxxxxxxxxF"
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
  --name ${MY_DOMAIN} \
  --caller-reference "$(date)" \
  --hosted-zone-config="{\"Comment\": \"Created by petr.ruzicka@gmail.com\", \"PrivateZone\": false}" | jq
```

Use your domain registrar to change the nameservers for your zone (for example
"mylabs.dev") to use the Amazon Route 53 nameservers. Here is the way how you
can find out the the Route 53 nameservers:

```bash
NEW_ZONE_ID=$(aws route53 list-hosted-zones --query "HostedZones[?Name==\`${MY_DOMAIN}.\`].Id" --output text)
NEW_ZONE_NS=$(aws route53 get-hosted-zone --output json --id ${NEW_ZONE_ID} --query "DelegationSet.NameServers")
NEW_ZONE_NS1=$(echo ${NEW_ZONE_NS} | jq -r ".[0]")
NEW_ZONE_NS2=$(echo ${NEW_ZONE_NS} | jq -r ".[1]")
```

Create the NS record in "mylabs.dev" for proper zone delegation.
This step depends on your domain registrar - I'm using CloudFlare and using
Ansible to automate it:

```shell
ansible -m cloudflare_dns -c local -i "localhost," localhost -a "zone=mylabs.dev record=$(echo ${MY_DOMAIN} | cut -f 1 -d .) type=NS value=${NEW_ZONE_NS1} solo=true proxied=no account_email=${CLOUDFLARE_EMAIL} account_api_token=${CLOUDFLARE_API_KEY}"
ansible -m cloudflare_dns -c local -i "localhost," localhost -a "zone=mylabs.dev record=$(echo ${MY_DOMAIN} | cut -f 1 -d .) type=NS value=${NEW_ZONE_NS2} solo=false proxied=no account_email=${CLOUDFLARE_EMAIL} account_api_token=${CLOUDFLARE_API_KEY}"
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

Create AWS IAM Policy `AllowDNSUpdates` which allows `cert-manager` and
`external-dns` to modify the Route 53 entries.

Details with examples are described on these links:

* [https://aws.amazon.com/blogs/opensource/introducing-fine-grained-iam-roles-service-accounts/](https://aws.amazon.com/blogs/opensource/introducing-fine-grained-iam-roles-service-accounts/)
* [https://cert-manager.io/docs/configuration/acme/dns01/route53/](https://cert-manager.io/docs/configuration/acme/dns01/route53/)
* [https://github.com/kubernetes-sigs/external-dns/blob/master/docs/tutorials/aws.md](https://github.com/kubernetes-sigs/external-dns/blob/master/docs/tutorials/aws.md)

```bash
test -d tmp || mkdir -v tmp
cat > tmp/route_53_change_policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "route53:GetChange",
      "Resource": "arn:aws:route53:::change/*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "route53:ChangeResourceRecordSets",
        "route53:ListResourceRecordSets"
      ],
      "Resource": "arn:aws:route53:::hostedzone/*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "route53:ListHostedZones",
        "route53:ListHostedZonesByName"
      ],
      "Resource": "*"
    }
  ]
}
EOF

aws iam create-policy \
  --policy-name ${MY_DOMAIN}-AmazonRoute53Domains \
  --description "Policy required by cert-manager to be able to modify Route 53 when generating wildcard certificates using Lets Encrypt" \
  --policy-document file://tmp/route_53_change_policy.json \
| jq

ROUTE53_POLICY_ARN=$(aws iam list-policies --query "Policies[?PolicyName==\`${MY_DOMAIN}-AmazonRoute53Domains\`].{ARN:Arn}" --output text)
```

Output:

```json
{
  "Policy": {
    "PolicyName": "kube1.mylabs.dev-AmazonRoute53Domains",
    "PolicyId": "ANPA2TXJQ2JHX755B25NW",
    "Arn": "arn:aws:iam::729560437327:policy/kube1.mylabs.dev-AmazonRoute53Domains",
    "Path": "/",
    "DefaultVersionId": "v1",
    "AttachmentCount": 0,
    "PermissionsBoundaryUsageCount": 0,
    "IsAttachable": true,
    "CreateDate": "2020-10-20T09:44:42Z",
    "UpdateDate": "2020-10-20T09:44:42Z"
  }
}
```

Create [Amazon EKS](https://aws.amazon.com/eks/) in AWS by using [eksctl](https://eksctl.io/).
It's a tool from [Weaveworks](https://weave.works/) based on official
AWS CloudFormation templates which will be used to launch and configure our
EKS cluster and nodes.

![eksctl](https://raw.githubusercontent.com/weaveworks/eksctl/c365149fc1a0b8d357139cbd6cda5aee8841c16c/logo/eksctl.png
"eksctl")

Create the Amazon EKS cluster using `eksctl`:

```bash
eksctl create cluster --config-file - --kubeconfig kubeconfig.conf << EOF
# https://eksctl.io/usage/schema/
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig

metadata:
  name: $(echo ${MY_DOMAIN} | cut -f 1 -d .)
  region: eu-central-1
  version: "1.18"
  tags: &tags
    Owner: petr.ruzicka@gmail.com
    Environment: Dev
    Tribe: Cloud_Native
    Squad: Cloud_Container_Platform

availabilityZones:
  - eu-central-1a
  - eu-central-1b

iam:
  withOIDC: true
  serviceAccounts:
    - metadata:
        name: cert-manager
        namespace: cert-manager
        labels:
          build: "eksctl"
      attachPolicyARNs:
        - ${ROUTE53_POLICY_ARN}
    - metadata:
        name: external-dns
        namespace: external-dns
        labels:
          build: "eksctl"
      attachPolicyARNs:
        - ${ROUTE53_POLICY_ARN}

nodeGroups:
  - name: ng01
    # Bottlerocket can not be used because of https://github.com/kubernetes-sigs/aws-efs-csi-driver/issues/246
    # amiFamily: Bottlerocket
    amiFamily: AmazonLinux2
    instanceType: t3.large
    desiredCapacity: 2
    minSize: 2
    maxSize: 2
    volumeSize: 0
    ssh:
      # Enable ssh access (via the admin container)
      allow: true
      publicKeyPath: ~/.ssh/id_rsa.pub
    labels:
      role: worker
    tags: *tags
    iam:
      withAddonPolicies:
        autoScaler: true
        cloudWatch: true
        ebs: true
        efs: true
        xRay: true
    volumeType: standard
    volumeEncrypted: true
    # bottlerocket:
    #   enableAdminContainer: true
    #   settings:
    #     motd: "Hello, eksctl!"
fargateProfiles:
  - name: fp-default
    selectors:
      # All workloads in the "default" Kubernetes namespace matching the following
      # label selectors will be scheduled onto Fargate:
      - namespace: default
        labels:
          fargate: "true"
    tags: *tags
  - name: fp-fargate-workload
    selectors:
      # All workloads in the "fargate-workload" Kubernetes namespace will be
      # scheduled onto Fargate:
      - namespace: fargate-workload
    tags: *tags

cloudWatch:
  clusterLogging:
    # enable specific types of cluster control plane logs
    enableTypes: ["audit", "authenticator", "controllerManager"]
    # all supported types: "api", "audit", "authenticator", "controllerManager", "scheduler"
    # supported special values: "*" and "all"
EOF
```

Output:

```text
[ℹ]  eksctl version 0.30.0
[ℹ]  using region eu-central-1
[ℹ]  subnets for eu-central-1a - public:192.168.0.0/19 private:192.168.64.0/19
[ℹ]  subnets for eu-central-1b - public:192.168.32.0/19 private:192.168.96.0/19
[ℹ]  nodegroup "ng01" will use "ami-045e4ecd708ac12ba" [AmazonLinux2/1.18]
[ℹ]  using SSH public key "/Users/petr_ruzicka/.ssh/id_rsa.pub" as "eksctl-kube1-nodegroup-ng01-a3:84:e4:0d:af:5f:c8:40:da:71:68:8a:74:c7:ba:16"
[ℹ]  using Kubernetes version 1.18
[ℹ]  creating EKS cluster "kube1" in "eu-central-1" region with Fargate profile and un-managed nodes
[ℹ]  1 nodegroup (ng01) was included (based on the include/exclude rules)
[ℹ]  will create a CloudFormation stack for cluster itself and 1 nodegroup stack(s)
[ℹ]  will create a CloudFormation stack for cluster itself and 0 managed nodegroup stack(s)
[ℹ]  if you encounter any issues, check CloudFormation console or try 'eksctl utils describe-stacks --region=eu-central-1 --cluster=kube1'
[ℹ]  Kubernetes API endpoint access will use default of {publicAccess=true, privateAccess=false} for cluster "kube1" in "eu-central-1"
[ℹ]  2 sequential tasks: { create cluster control plane "kube1", 2 sequential sub-tasks: { 6 sequential sub-tasks: { tag cluster, update CloudWatch logging configuration, create fargate profiles, associate IAM OIDC provider, 3 parallel sub-tasks: { 2 sequential sub-tasks: { create IAM role for serviceaccount "cert-manager/cert-manager", create serviceaccount "cert-manager/cert-manager" }, 2 sequential sub-tasks: { create IAM role for serviceaccount "external-dns/external-dns", create serviceaccount "external-dns/external-dns" }, 2 sequential sub-tasks: { create IAM role for serviceaccount "kube-system/aws-node", create serviceaccount "kube-system/aws-node" } }, restart daemonset "kube-system/aws-node" }, create nodegroup "ng01" } }
[ℹ]  building cluster stack "eksctl-kube1-cluster"
[ℹ]  deploying stack "eksctl-kube1-cluster"
[✔]  tagged EKS cluster (Environment=Dev, Owner=petr.ruzicka@gmail.com, Squad=Cloud_Container_Platform, Tribe=Cloud_Native)
[✔]  configured CloudWatch logging for cluster "kube1" in "eu-central-1" (enabled types: audit, authenticator, controllerManager & disabled types: api, scheduler)
[ℹ]  creating Fargate profile "fp-default" on EKS cluster "kube1"
[ℹ]  created Fargate profile "fp-default" on EKS cluster "kube1"
[ℹ]  creating Fargate profile "fp-fargate-workload" on EKS cluster "kube1"
[ℹ]  created Fargate profile "fp-fargate-workload" on EKS cluster "kube1"
[ℹ]  building iamserviceaccount stack "eksctl-kube1-addon-iamserviceaccount-external-dns-external-dns"
[ℹ]  building iamserviceaccount stack "eksctl-kube1-addon-iamserviceaccount-cert-manager-cert-manager"
[ℹ]  building iamserviceaccount stack "eksctl-kube1-addon-iamserviceaccount-kube-system-aws-node"
[ℹ]  deploying stack "eksctl-kube1-addon-iamserviceaccount-cert-manager-cert-manager"
[ℹ]  deploying stack "eksctl-kube1-addon-iamserviceaccount-kube-system-aws-node"
[ℹ]  deploying stack "eksctl-kube1-addon-iamserviceaccount-external-dns-external-dns"
[ℹ]  serviceaccount "kube-system/aws-node" already exists
[ℹ]  updated serviceaccount "kube-system/aws-node"
[ℹ]  created namespace "external-dns"
[ℹ]  created serviceaccount "external-dns/external-dns"
[ℹ]  created namespace "cert-manager"
[ℹ]  created serviceaccount "cert-manager/cert-manager"
[ℹ]  daemonset "kube-system/aws-node" restarted
[ℹ]  building nodegroup stack "eksctl-kube1-nodegroup-ng01"
[ℹ]  deploying stack "eksctl-kube1-nodegroup-ng01"
[ℹ]  waiting for the control plane availability...
[✔]  saved kubeconfig as "kubeconfig.conf"
[ℹ]  no tasks
[✔]  all EKS cluster resources for "kube1" have been created
[ℹ]  adding identity "arn:aws:iam::729560437327:role/eksctl-kube1-nodegroup-ng01-NodeInstanceRole-IYLKEG3R62OG" to auth ConfigMap
[ℹ]  nodegroup "ng01" has 0 node(s)
[ℹ]  waiting for at least 2 node(s) to become ready in "ng01"
[ℹ]  nodegroup "ng01" has 2 node(s)
[ℹ]  node "ip-192-168-53-81.eu-central-1.compute.internal" is ready
[ℹ]  node "ip-192-168-7-193.eu-central-1.compute.internal" is ready
[ℹ]  kubectl command should work with "kubeconfig.conf", try 'kubectl --kubeconfig=kubeconfig.conf get nodes'
[✔]  EKS cluster "kube1" in "eu-central-1" region is ready
```

Set `KUBECONFIG`:

```bash
export KUBECONFIG=${PWD}/kubeconfig.conf
```

Remove namespaces with serviceaccounts created by `eksctl`:

```bash
kubectl delete serviceaccount -n cert-manager cert-manager
kubectl delete serviceaccount -n external-dns external-dns
```

Check the nodes:

```bash
kubectl get nodes -o wide
```

Output:

```text
NAME                                             STATUS   ROLES    AGE   VERSION              INTERNAL-IP     EXTERNAL-IP     OS-IMAGE         KERNEL-VERSION                  CONTAINER-RUNTIME
ip-192-168-53-81.eu-central-1.compute.internal   Ready    <none>   44s   v1.18.8-eks-7c9bda   192.168.53.81   52.59.224.70    Amazon Linux 2   4.14.198-152.320.amzn2.x86_64   docker://19.3.6
ip-192-168-7-193.eu-central-1.compute.internal   Ready    <none>   47s   v1.18.8-eks-7c9bda   192.168.7.193   18.184.53.104   Amazon Linux 2   4.14.198-152.320.amzn2.x86_64   docker://19.3.6
```
