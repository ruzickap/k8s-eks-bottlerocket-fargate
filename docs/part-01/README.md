# Amazon EKS Bottlerocket and Fargate

![Amazon EKS](https://raw.githubusercontent.com/cncf/landscape/7f5b02ecba914a32912e77fc78e1c54d1c2f98ec/hosted_logos/amazon-eks.svg?sanitize=true
"Amazon EKS")

Before starting with the main content, it's necessary to provision
the [Amazon EKS](https://aws.amazon.com/eks/) in AWS.

## Requirements

If you would like to follow this documents and it's task you will need to set up
few environment variables.

The `LETSENCRYPT_ENVIRONMENT` variable should be one of:

* `staging` - Let’s Encrypt will create testing certificate (not valid)
* `production` - Let’s Encrypt will create valid certificate (use with care)

`BASE_DOMAIN` contains DNS records for all your Kubernetes clusters. The cluster
names will look like `CLUSTER_NAME`.`BASE_DOMAIN` (`kube1.k8s.mylabs.dev`).

```bash
# Hostname / FQDN definitions
export BASE_DOMAIN=${BASE_DOMAIN:-k8s.mylabs.dev}
export CLUSTER_NAME=${CLUSTER_NAME:-kube1}
export CLUSTER_FQDN="${CLUSTER_NAME}.${BASE_DOMAIN}"
export KUBECONFIG=${PWD}/kubeconfig-${CLUSTER_NAME}.conf
# * "production" - valid certificates signed by Lets Encrypt ""
# * "staging" - not trusted certs signed by Lets Encrypt "Fake LE Intermediate X1"
export LETSENCRYPT_ENVIRONMENT="staging"
export LETSENCRYPT_CERTIFICATE="https://letsencrypt.org/certs/staging/letsencrypt-stg-root-x1.pem"
# export LETSENCRYPT_ENVIRONMENT="production"
# export LETSENCRYPT_CERTIFICATE="https://letsencrypt.org/certs/lets-encrypt-r3.pem"
export MY_EMAIL="petr.ruzicka@gmail.com"
# GitHub Organization + Team where are the users who will have the admin access
# to K8s resources (Grafana). Only users in GitHub organization
# (MY_GITHUB_ORG_NAME) will be able to access the apps via ingress.
export MY_GITHUB_ORG_NAME="ruzickap-org"
export MY_GITHUB_USERNAME="ruzickap"
# AWS Region
export AWS_DEFAULT_REGION="eu-west-1"
export SLACK_CHANNEL="mylabs"
# Tags used to tag the AWS resources
export TAGS="Owner=${MY_EMAIL} Environment=Dev Group=Cloud_Native Squad=Cloud_Container_Platform compliance:na:defender=bottlerocket"
echo -e "${MY_EMAIL} | ${LETSENCRYPT_ENVIRONMENT} | ${CLUSTER_NAME} | ${BASE_DOMAIN} | ${CLUSTER_FQDN}\n${TAGS}"
```

Prepare GitHub OAuth "access" credentials ans AWS "access" variables.

You will need to configure AWS CLI: [Configuring the AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/cli-chap-configure.html)

```shell
# Common password
export MY_PASSWORD="xxxx"
# AWS Credentials
export AWS_ACCESS_KEY_ID=""
export AWS_SECRET_ACCESS_KEY=""
export AWS_CONSOLE_ADMIN_ROLE_ARN="arn:aws:iam::7xxxxxxxxxx7:role/xxxxxxxxxxxxxN"
# GitHub Organization OAuth Apps credentials
export MY_GITHUB_ORG_OAUTH_DEX_CLIENT_ID="3xxxxxxxxxxxxxxxxxx3"
export MY_GITHUB_ORG_OAUTH_DEX_CLIENT_SECRET="7xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx8"
export MY_GITHUB_ORG_OAUTH_KEYCLOAK_CLIENT_ID="4xxxxxxxxxxxxxxxxxx4"
export MY_GITHUB_ORG_OAUTH_KEYCLOAK_CLIENT_SECRET="7xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxa"
# Sysdig credentials
export SYSDIG_AGENT_ACCESSKEY="xxx"
# Aqua credentials
export AQUA_REGISTRY_USERNAME="xxx"
export AQUA_REGISTRY_PASSWORD="xxx"
export AQUA_ENFORCER_TOKEN="xxx"
# Splunk credentials
export SPLUNK_HOST="xxx"
export SPLUNK_TOKEN="xxx"
export SPLUNK_INDEX_NAME="xxx"
# Slack incoming webhook
export SLACK_INCOMING_WEBHOOK_URL="https://hooks.slack.com/services/YOUR/SLACK/WEBHOOK"
export SLACK_BOT_API_TOKEN="xxxx-xxxxxxxxxxxxx-xxxxxxxxxxxxx-xxxxxxxxxxxxxxxxxxxxxxxP"
# Okta configuration
export OKTA_ISSUER="https://exxxxxxx-xxxxx-xx.okta.com"
export OKTA_CLIENT_ID="0xxxxxxxxxxxxxxxxxx7"
export OKTA_CLIENT_SECRET="1xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxH"
```

Verify if all the necessary variables were set:

```bash
case "${CLUSTER_NAME}" in
  kube1)
    MY_GITHUB_ORG_OAUTH_DEX_CLIENT_ID=${MY_GITHUB_ORG_OAUTH_DEX_CLIENT_ID:-${MY_GITHUB_ORG_OAUTH_DEX_CLIENT_ID_KUBE1}}
    MY_GITHUB_ORG_OAUTH_DEX_CLIENT_SECRET=${MY_GITHUB_ORG_OAUTH_DEX_CLIENT_SECRET:-${MY_GITHUB_ORG_OAUTH_DEX_CLIENT_SECRET_KUBE1}}
    MY_GITHUB_ORG_OAUTH_KEYCLOAK_CLIENT_ID=${MY_GITHUB_ORG_OAUTH_KEYCLOAK_CLIENT_ID:-${MY_GITHUB_ORG_OAUTH_KEYCLOAK_CLIENT_ID_KUBE1}}
    MY_GITHUB_ORG_OAUTH_KEYCLOAK_CLIENT_SECRET=${MY_GITHUB_ORG_OAUTH_KEYCLOAK_CLIENT_SECRET:-${MY_GITHUB_ORG_OAUTH_KEYCLOAK_CLIENT_SECRET_KUBE1}}
  ;;
  kube2)
    MY_GITHUB_ORG_OAUTH_DEX_CLIENT_ID=${MY_GITHUB_ORG_OAUTH_DEX_CLIENT_ID:-${MY_GITHUB_ORG_OAUTH_DEX_CLIENT_ID_KUBE2}}
    MY_GITHUB_ORG_OAUTH_DEX_CLIENT_SECRET=${MY_GITHUB_ORG_OAUTH_DEX_CLIENT_SECRET:-${MY_GITHUB_ORG_OAUTH_DEX_CLIENT_SECRET_KUBE2}}
    MY_GITHUB_ORG_OAUTH_KEYCLOAK_CLIENT_ID=${MY_GITHUB_ORG_OAUTH_KEYCLOAK_CLIENT_ID:-${MY_GITHUB_ORG_OAUTH_KEYCLOAK_CLIENT_ID_KUBE2}}
    MY_GITHUB_ORG_OAUTH_KEYCLOAK_CLIENT_SECRET=${MY_GITHUB_ORG_OAUTH_KEYCLOAK_CLIENT_SECRET:-${MY_GITHUB_ORG_OAUTH_KEYCLOAK_CLIENT_SECRET_KUBE2}}
  ;;
  *)
    echo "Unsupported cluster name: ${CLUSTER_NAME} !"
    exit 1
  ;;
esac

: "${AWS_ACCESS_KEY_ID?}"
: "${AWS_SECRET_ACCESS_KEY?}"
: "${AWS_CONSOLE_ADMIN_ROLE_ARN?}"
: "${GITHUB_TOKEN?}"
: "${SLACK_INCOMING_WEBHOOK_URL?}"
: "${SLACK_BOT_API_TOKEN?}"
: "${MY_PASSWORD?}"
: "${OKTA_ISSUER?}"
: "${OKTA_CLIENT_ID?}"
: "${OKTA_CLIENT_SECRET?}"
```

## Prepare the local working environment

::: tip
You can skip these steps if you have all the required software already
installed.
:::

Install necessary software:

```bash

if command -v apt-get &> /dev/null; then
  apt update -qq
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq apache2-utils ansible dnsutils git gnupg2 jq sudo unzip > /dev/null
fi
```

Install [AWS CLI](https://aws.amazon.com/cli/)  binary:

```bash
if ! command -v aws &> /dev/null; then
  curl -sL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "/tmp/awscliv2.zip"
  unzip -q -o /tmp/awscliv2.zip -d /tmp/
  sudo /tmp/aws/install
fi
```

Install [kubectl](https://github.com/kubernetes/kubectl) binary:

```bash
if ! command -v kubectl &> /dev/null; then
  # https://github.com/kubernetes/kubectl/releases
  sudo curl -s -Lo /usr/local/bin/kubectl "https://storage.googleapis.com/kubernetes-release/release/v1.21.1/bin/$(uname | sed "s/./\L&/g" )/amd64/kubectl"
  sudo chmod a+x /usr/local/bin/kubectl
fi
```

Install [Helm](https://helm.sh/):

```bash
if ! command -v helm &> /dev/null; then
  # https://github.com/helm/helm/releases
  curl -s https://raw.githubusercontent.com/helm/helm/master/scripts/get | bash -s -- --version v3.6.0
fi
```

Install [eksctl](https://eksctl.io/):

```bash
if ! command -v eksctl &> /dev/null; then
  # https://github.com/weaveworks/eksctl/releases
  curl -s -L "https://github.com/weaveworks/eksctl/releases/download/0.60.0/eksctl_$(uname)_amd64.tar.gz" | sudo tar xz -C /usr/local/bin/
fi
```

Install [AWS IAM Authenticator for Kubernetes](https://github.com/kubernetes-sigs/aws-iam-authenticator):

```bash
if ! command -v aws-iam-authenticator &> /dev/null; then
  # https://docs.aws.amazon.com/eks/latest/userguide/install-aws-iam-authenticator.html
  sudo curl -s -Lo /usr/local/bin/aws-iam-authenticator "https://amazon-eks.s3.us-west-2.amazonaws.com/1.19.6/2021-01-05/bin/$(uname | sed "s/./\L&/g")/amd64/aws-iam-authenticator"
  sudo chmod a+x /usr/local/bin/aws-iam-authenticator
fi
```

Install [vault](https://www.vaultproject.io/downloads):

```bash
if ! command -v vault &> /dev/null; then
  curl -s -L "https://releases.hashicorp.com/vault/1.7.2/vault_1.7.2_$(uname | sed "s/./\L&/g")_amd64.zip" -o /tmp/vault.zip
  sudo unzip -q /tmp/vault.zip -d /usr/local/bin/
  rm /tmp/vault.zip
fi
```

Install [velero](https://github.com/vmware-tanzu/velero/releases):

```bash
if ! command -v velero &> /dev/null; then
  curl -s -L "https://github.com/vmware-tanzu/velero/releases/download/v1.6.0/velero-v1.6.0-$(uname | sed "s/./\L&/g")-amd64.tar.gz" -o /tmp/velero.tar.gz
  sudo tar xzf /tmp/velero.tar.gz -C /usr/local/bin/ --strip-components 1 "velero-v1.6.0-$(uname | sed "s/./\L&/g")-amd64/velero"
fi
```

Install [flux](https://toolkit.fluxcd.io/):

```bash
if ! command -v flux &> /dev/null; then
  curl -s https://fluxcd.io/install.sh | sudo bash
fi
```

Install [calicoctl](https://docs.projectcalico.org/getting-started/clis/calicoctl/install):

```bash
if ! command -v calicoctl &> /dev/null; then
  sudo curl -s -Lo /usr/local/bin/calicoctl https://github.com/projectcalico/calicoctl/releases/download/v3.20.0/calicoctl
  sudo chmod a+x /usr/local/bin/calicoctl
fi
```

Install [SOPS: Secrets OPerationS](https://github.com/mozilla/sops):

```bash
if ! command -v sops &> /dev/null; then
  sudo curl -s -Lo /usr/local/bin/sops "https://github.com/mozilla/sops/releases/download/v3.7.1/sops-v3.7.1.$(uname | sed "s/./\L&/g")"
  sudo chmod a+x /usr/local/bin/sops
fi
```

Install [kustomize](https://kustomize.io/):

```bash
if ! command -v kustomize &> /dev/null; then
  curl -s "https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh" | sudo bash -s 4.1.2 /usr/local/bin/
fi
```

Install [hey](https://github.com/rakyll/hey):

```bash
if ! command -v hey &> /dev/null; then
  sudo curl -s -Lo /usr/local/bin/hey "https://hey-release.s3.us-east-2.amazonaws.com/hey_$(uname | sed "s/./\L&/g")_amd64"
  sudo chmod a+x /usr/local/bin/hey
fi
```

## Configure AWS Route 53 Domain delegation

Create DNS zone (`BASE_DOMAIN`):

```shell
aws route53 create-hosted-zone --output json \
  --name "${BASE_DOMAIN}" \
  --caller-reference "$(date)" \
  --hosted-zone-config="{\"Comment\": \"Created by ${MY_EMAIL}\", \"PrivateZone\": false}" | jq
```

Use your domain registrar to change the nameservers for your zone (for example
"mylabs.dev") to use the Amazon Route 53 nameservers. Here is the way how you
can find out the the Route 53 nameservers:

```shell
NEW_ZONE_ID=$(aws route53 list-hosted-zones --query "HostedZones[?Name==\`${BASE_DOMAIN}.\`].Id" --output text)
NEW_ZONE_NS=$(aws route53 get-hosted-zone --output json --id "${NEW_ZONE_ID}" --query "DelegationSet.NameServers")
NEW_ZONE_NS1=$(echo "${NEW_ZONE_NS}" | jq -r ".[0]")
NEW_ZONE_NS2=$(echo "${NEW_ZONE_NS}" | jq -r ".[1]")
```

Create the NS record in `k8s.mylabs.dev` (`BASE_DOMAIN`) for proper zone
delegation. This step depends on your domain registrar - I'm using CloudFlare
and using Ansible to automate it:

```shell
ansible -m cloudflare_dns -c local -i "localhost," localhost -a "zone=mylabs.dev record=${BASE_DOMAIN} type=NS value=${NEW_ZONE_NS1} solo=true proxied=no account_email=${CLOUDFLARE_EMAIL} account_api_token=${CLOUDFLARE_API_KEY}"
ansible -m cloudflare_dns -c local -i "localhost," localhost -a "zone=mylabs.dev record=${BASE_DOMAIN} type=NS value=${NEW_ZONE_NS2} solo=false proxied=no account_email=${CLOUDFLARE_EMAIL} account_api_token=${CLOUDFLARE_API_KEY}"
```

Output:

```text
localhost | CHANGED => {
    "ansible_facts": {
        "discovered_interpreter_python": "/usr/bin/python"
    },
    "changed": true,
    "result": {
        "record": {
            "content": "ns-885.awsdns-46.net",
            "created_on": "2020-11-13T06:25:32.18642Z",
            "id": "dxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxb",
            "locked": false,
            "meta": {
                "auto_added": false,
                "managed_by_apps": false,
                "managed_by_argo_tunnel": false,
                "source": "primary"
            },
            "modified_on": "2020-11-13T06:25:32.18642Z",
            "name": "k8s.mylabs.dev",
            "proxiable": false,
            "proxied": false,
            "ttl": 1,
            "type": "NS",
            "zone_id": "2xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxe",
            "zone_name": "mylabs.dev"
        }
    }
}
localhost | CHANGED => {
    "ansible_facts": {
        "discovered_interpreter_python": "/usr/bin/python"
    },
    "changed": true,
    "result": {
        "record": {
            "content": "ns-1692.awsdns-19.co.uk",
            "created_on": "2020-11-13T06:25:37.605605Z",
            "id": "9xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxb",
            "locked": false,
            "meta": {
                "auto_added": false,
                "managed_by_apps": false,
                "managed_by_argo_tunnel": false,
                "source": "primary"
            },
            "modified_on": "2020-11-13T06:25:37.605605Z",
            "name": "k8s.mylabs.dev",
            "proxiable": false,
            "proxied": false,
            "ttl": 1,
            "type": "NS",
            "zone_id": "2xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxe",
            "zone_name": "mylabs.dev"
        }
    }
}
```

## Add new domain to Route 53, Policies, S3, EBS

Details with examples are described on these links:

* [https://aws.amazon.com/blogs/opensource/introducing-fine-grained-iam-roles-service-accounts/](https://aws.amazon.com/blogs/opensource/introducing-fine-grained-iam-roles-service-accounts/)
* [https://cert-manager.io/docs/configuration/acme/dns01/route53/](https://cert-manager.io/docs/configuration/acme/dns01/route53/)
* [https://github.com/kubernetes-sigs/external-dns/blob/master/docs/tutorials/aws.md](https://github.com/kubernetes-sigs/external-dns/blob/master/docs/tutorials/aws.md)

Create CloudFormation template containing policies for Route53, S3 access
(Harbor, Velero) and Domain. Put new domain `CLUSTER_FQDN` to the Route 53 and
configure the DNS delegation from the `BASE_DOMAIN`.

```bash
mkdir -vp "tmp/${CLUSTER_FQDN}"

cat > "tmp/${CLUSTER_FQDN}/aws-route53-iam-s3-kms-asm.yml" << \EOF
Description: "Template to generate the necessary IAM Policies for access to Route53 and S3"
Parameters:
  ClusterFQDN:
    Description: "Cluster domain where all necessary app subdomains will live (subdomain of BaseDomain). Ex: kube1.k8s.mylabs.dev"
    Type: String
  ClusterName:
    Description: "Cluster Name Ex: kube1"
    Type: String
  BaseDomain:
    Description: "Base domain where cluster domains + their subdomains will live. Ex: k8s.mylabs.dev"
    Type: String
Resources:
  # This AWS control checks whether the status of the AWS Systems Manager association compliance is COMPLIANT or NON_COMPLIANT after the association is executed on an instance.
  ConfigRule:
    Type: "AWS::Config::ConfigRule"
    Properties:
      ConfigRuleName: !Sub "${ClusterName}-ec2-managedinstance-association-compliance-status-check"
      Scope:
        ComplianceResourceTypes:
          - "AWS::SSM::AssociationCompliance"
      Description: "A Config rule that checks whether the compliance status of the Amazon EC2 Systems Manager association compliance is COMPLIANT or NON_COMPLIANT after the association execution on the instance. The rule is compliant if the field status is COMPLIANT."
      Source:
        Owner: "AWS"
        SourceIdentifier: "EC2_MANAGEDINSTANCE_ASSOCIATION_COMPLIANCE_STATUS_CHECK"
  CloudWatchPolicy:
    Type: AWS::IAM::ManagedPolicy
    Properties:
      ManagedPolicyName: !Sub "${ClusterFQDN}-CloudWatch"
      Description: !Sub "Policy required by Fargate to log to CloudWatch for ${ClusterFQDN}"
      PolicyDocument:
        Version: "2012-10-17"
        Statement:
        - Effect: Allow
          Action:
          - logs:CreateLogStream
          - logs:CreateLogGroup
          - logs:DescribeLogStreams
          - logs:PutLogEvents
          Resource: "*"
  HostedZone:
    Type: AWS::Route53::HostedZone
    Properties:
      Name: !Ref ClusterFQDN
  KMSAlias:
    Type: AWS::KMS::Alias
    Properties:
      AliasName: !Sub "alias/eks-${ClusterName}"
      TargetKeyId: !Ref KMSKey
  KMSKey:
    Type: AWS::KMS::Key
    Properties:
      Description: !Sub "KMS key for secrets related to ${ClusterFQDN}"
      EnableKeyRotation: true
      PendingWindowInDays: 7
      KeyPolicy:
        Version: "2012-10-17"
        Id: !Sub "eks-key-policy-${ClusterName}"
        Statement:
        - Sid: Enable IAM User Permissions
          Effect: Allow
          Principal:
            AWS: !Sub "arn:aws:iam::${AWS::AccountId}:root"
          Action: kms:*
          Resource: "*"
        - Sid: Allow use of the key
          Effect: Allow
          Principal:
            AWS: !Sub "arn:aws:iam::${AWS::AccountId}:role/aws-service-role/autoscaling.amazonaws.com/AWSServiceRoleForAutoScaling"
          Action:
          - kms:Encrypt
          - kms:Decrypt
          - kms:ReEncrypt*
          - kms:GenerateDataKey*
          - kms:DescribeKey
          Resource: "*"
        - Sid: Allow attachment of persistent resources
          Effect: Allow
          Principal:
            AWS: !Sub "arn:aws:iam::${AWS::AccountId}:role/aws-service-role/autoscaling.amazonaws.com/AWSServiceRoleForAutoScaling"
          Action:
          - kms:CreateGrant
          Resource: "*"
          Condition:
            Bool:
              kms:GrantIsForAWSResource: true
  EKSViewNodesAndWorkloadsPolicy:
    Type: AWS::IAM::ManagedPolicy
    Properties:
      ManagedPolicyName: !Sub "${ClusterFQDN}-EKSViewNodesAndWorkloads"
      Description: !Sub "Policy used to view workloads running in an EKS cluster created using CAPA"
      PolicyDocument:
        Version: "2012-10-17"
        Statement:
        - Effect: Allow
          Action:
          - eks:DescribeNodegroup
          - eks:ListNodegroups
          - eks:DescribeCluster
          - eks:ListClusters
          - eks:AccessKubernetesApi
          - ssm:GetParameter
          - eks:ListUpdates
          - eks:ListFargateProfiles
          Resource: "*"
  RecordSet:
    Type: AWS::Route53::RecordSet
    Properties:
      HostedZoneName: !Sub "${BaseDomain}."
      Name: !Ref ClusterFQDN
      Type: NS
      TTL: 60
      ResourceRecords: !GetAtt HostedZone.NameServers
  S3Policy:
    Type: AWS::IAM::ManagedPolicy
    Properties:
      ManagedPolicyName: !Sub "${ClusterFQDN}-AmazonS3"
      Description: !Sub "Policy required by Harbor and Velero to write to S3 bucket ${ClusterFQDN}"
      PolicyDocument:
        Version: "2012-10-17"
        Statement:
        - Effect: Allow
          Action:
          - s3:ListBucket
          - s3:GetBucketLocation
          - s3:ListBucketMultipartUploads
          Resource: !GetAtt S3Bucket.Arn
        - Effect: Allow
          Action:
          - s3:PutObject
          - s3:GetObject
          - s3:DeleteObject
          - s3:ListMultipartUploadParts
          - s3:AbortMultipartUpload
          Resource: !Sub "arn:aws:s3:::${ClusterFQDN}/*"
  S3Bucket:
    Type: AWS::S3::Bucket
    Properties:
      AccessControl: Private
      BucketName: !Sub "${ClusterFQDN}"
      BucketEncryption:
        ServerSideEncryptionConfiguration:
          - ServerSideEncryptionByDefault:
              SSEAlgorithm: AES256
  SecretsManagerMySecret:
    Type: AWS::SecretsManager::Secret
    Properties:
      Name: !Sub "${ClusterFQDN}-MySecret"
      Description: My Secret
      GenerateSecretString:
        SecretStringTemplate: "{\"username\": \"Administrator\"}"
        GenerateStringKey: password
        PasswordLength: 32
      KmsKeyId: !Ref KMSKey
  SecretsManagerMySecret2:
    Type: AWS::SecretsManager::Secret
    Properties:
      Name: !Sub "${ClusterFQDN}-MySecret2"
      Description: My Secret2
      GenerateSecretString:
        SecretStringTemplate: "{\"username\": \"Administrator2\"}"
        GenerateStringKey: password
        PasswordLength: 32
      KmsKeyId: !Ref KMSKey
  UserMyUser1:
    Type: AWS::IAM::User
    Properties:
      UserName: !Sub "myuser1-${ClusterName}"
      Policies:
      - PolicyName: !Sub "myuser1-${ClusterName}-policy"
        PolicyDocument:
          Version: "2012-10-17"
          Statement:
          - Sid: AllowAssumeOrganizationAccountRole
            Effect: Allow
            Action: sts:AssumeRole
            Resource: !GetAtt RoleMyUser1.Arn
  AccessKeyMyUser1:
    Type: AWS::IAM::AccessKey
    Properties:
      UserName: !Ref UserMyUser1
  RoleMyUser1:
    Type: AWS::IAM::Role
    Properties:
      Description: !Sub "IAM role for the myuser1-${ClusterName} user"
      RoleName: !Sub "myuser1-${ClusterName}"
      AssumeRolePolicyDocument:
        Version: 2012-10-17
        Statement:
        - Effect: Allow
          Principal:
            AWS: !Sub "arn:aws:iam::${AWS::AccountId}:root"
          Action: sts:AssumeRole
  UserMyUser2:
    Type: AWS::IAM::User
    Properties:
      UserName: !Sub "myuser2-${ClusterName}"
      Policies:
      - PolicyName: !Sub "myuser2-${ClusterName}-policy"
        PolicyDocument:
          Version: "2012-10-17"
          Statement:
          - Sid: AllowAssumeOrganizationAccountRole
            Effect: Allow
            Action: sts:AssumeRole
            Resource: !GetAtt RoleMyUser2.Arn
  AccessKeyMyUser2:
    Type: AWS::IAM::AccessKey
    Properties:
      UserName: !Ref UserMyUser2
  RoleMyUser2:
    Type: AWS::IAM::Role
    Properties:
      Description: !Sub "IAM role for the myuser2-${ClusterName} user"
      RoleName: !Sub "myuser2-${ClusterName}"
      AssumeRolePolicyDocument:
        Version: 2012-10-17
        Statement:
        - Effect: Allow
          Principal:
            AWS: !Sub "arn:aws:iam::${AWS::AccountId}:root"
          Action: sts:AssumeRole
Outputs:
  CloudWatchPolicyArn:
    Description: The ARN of the created CloudWatchPolicy
    Value: !Ref CloudWatchPolicy
    Export:
      Name:
        Fn::Sub: "${AWS::StackName}-CloudWatchPolicyArn"
  KMSKeyArn:
    Description: The ARN of the created KMS Key to encrypt EKS related services
    Value: !GetAtt KMSKey.Arn
    Export:
      Name:
        Fn::Sub: "${AWS::StackName}-KMSKeyArn"
  KMSKeyId:
    Description: The ID of the created KMS Key to encrypt EKS related services
    Value: !Ref KMSKey
    Export:
      Name:
        Fn::Sub: "${AWS::StackName}-KMSKeyId"
  HostedZoneArn:
    Description: The ARN of the created Route53 Zone for K8s cluster
    Value: !Ref HostedZone
    Export:
      Name:
        Fn::Sub: "${AWS::StackName}-HostedZoneArn"
  S3PolicyArn:
    Description: The ARN of the created AmazonS3 policy
    Value: !Ref S3Policy
    Export:
      Name:
        Fn::Sub: "${AWS::StackName}-S3PolicyArn"
  RoleMyUser1Arn:
    Description: The ARN of the MyUser1 IAM Role
    Value: !GetAtt RoleMyUser1.Arn
    Export:
      Name:
        Fn::Sub: "${AWS::StackName}-RoleMyUser1Arn"
  AccessKeyMyUser1:
    Description: The AccessKey for MyUser1 user
    Value: !Ref AccessKeyMyUser1
    Export:
      Name:
        Fn::Sub: "${AWS::StackName}-AccessKeyMyUser1"
  SecretAccessKeyMyUser1:
    Description: The SecretAccessKey for MyUser1 user
    Value: !GetAtt AccessKeyMyUser1.SecretAccessKey
    Export:
      Name:
        Fn::Sub: "${AWS::StackName}-SecretAccessKeyMyUser1"
  RoleMyUser2Arn:
    Description: The ARN of the MyUser2 IAM Role
    Value: !GetAtt RoleMyUser2.Arn
    Export:
      Name:
        Fn::Sub: "${AWS::StackName}-RoleMyUser2Arn"
  AccessKeyMyUser2:
    Description: The AccessKey for MyUser2 user
    Value: !Ref AccessKeyMyUser2
    Export:
      Name:
        Fn::Sub: "${AWS::StackName}-AccessKeyMyUser2"
  SecretAccessKeyMyUser2:
    Description: The SecretAccessKey for MyUser2 user
    Value: !GetAtt AccessKeyMyUser2.SecretAccessKey
    Export:
      Name:
        Fn::Sub: "${AWS::StackName}-SecretAccessKeyMyUser2"
EOF

eval aws cloudformation deploy --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides "ClusterFQDN=${CLUSTER_FQDN} ClusterName=${CLUSTER_NAME} BaseDomain=${BASE_DOMAIN}" \
  --stack-name "${CLUSTER_NAME}-route53-iam-s3-kms-asm" --template-file "tmp/${CLUSTER_FQDN}/aws-route53-iam-s3-kms-asm.yml" --tags "${TAGS}"

AWS_CLOUDFORMATION_DETAILS=$(aws cloudformation describe-stacks --stack-name "${CLUSTER_NAME}-route53-iam-s3-kms-asm")
CLOUDWATCH_POLICY_ARN=$(echo "${AWS_CLOUDFORMATION_DETAILS}" | jq -r ".Stacks[0].Outputs[] | select(.OutputKey==\"CloudWatchPolicyArn\") .OutputValue")
KMS_KEY_ARN=$(echo "${AWS_CLOUDFORMATION_DETAILS}" | jq -r ".Stacks[0].Outputs[] | select(.OutputKey==\"KMSKeyArn\") .OutputValue")
KMS_KEY_ID=$(echo "${AWS_CLOUDFORMATION_DETAILS}" | jq -r ".Stacks[0].Outputs[] | select(.OutputKey==\"KMSKeyId\") .OutputValue")
S3_POLICY_ARN=$(echo "${AWS_CLOUDFORMATION_DETAILS}" | jq -r ".Stacks[0].Outputs[] | select(.OutputKey==\"S3PolicyArn\") .OutputValue")
MYUSER1_ROLE_ARN=$(echo "${AWS_CLOUDFORMATION_DETAILS}" | jq -r ".Stacks[0].Outputs[] | select(.OutputKey==\"RoleMyUser1Arn\") .OutputValue")
MYUSER1_USER_ACCESSKEYMYUSER=$(echo "${AWS_CLOUDFORMATION_DETAILS}" | jq -r ".Stacks[0].Outputs[] | select(.OutputKey==\"AccessKeyMyUser1\") .OutputValue")
MYUSER1_USER_SECRETACCESSKEY=$(echo "${AWS_CLOUDFORMATION_DETAILS}" | jq -r ".Stacks[0].Outputs[] | select(.OutputKey==\"SecretAccessKeyMyUser1\") .OutputValue")
MYUSER2_ROLE_ARN=$(echo "${AWS_CLOUDFORMATION_DETAILS}" | jq -r ".Stacks[0].Outputs[] | select(.OutputKey==\"RoleMyUser2Arn\") .OutputValue")
MYUSER2_USER_ACCESSKEYMYUSER=$(echo "${AWS_CLOUDFORMATION_DETAILS}" | jq -r ".Stacks[0].Outputs[] | select(.OutputKey==\"AccessKeyMyUser2\") .OutputValue")
MYUSER2_USER_SECRETACCESSKEY=$(echo "${AWS_CLOUDFORMATION_DETAILS}" | jq -r ".Stacks[0].Outputs[] | select(.OutputKey==\"SecretAccessKeyMyUser2\") .OutputValue")
```

Change TTL=60 of SOA + NS records for new domain
(it can not be done in CloudFormation):

```bash
HOSTED_ZONE_ID=$(aws route53 list-hosted-zones --query "HostedZones[?Name==\`${CLUSTER_FQDN}.\`].Id" --output text)
RESOURCE_RECORD_SET_SOA=$(aws route53 --output json list-resource-record-sets --hosted-zone-id "${HOSTED_ZONE_ID}" --query "(ResourceRecordSets[?Type == \`SOA\`])[0]" | sed "s/\"TTL\":.*/\"TTL\": 60,/")
RESOURCE_RECORD_SET_NS=$(aws route53 --output json list-resource-record-sets --hosted-zone-id "${HOSTED_ZONE_ID}" --query "(ResourceRecordSets[?Type == \`NS\`])[0]" | sed "s/\"TTL\":.*/\"TTL\": 60,/")
cat << EOF | aws route53 --output json change-resource-record-sets --hosted-zone-id "${HOSTED_ZONE_ID}" --change-batch=file:///dev/stdin
{
    "Comment": "Update record to reflect new TTL for SOA and NS records",
    "Changes": [
        {
            "Action": "UPSERT",
            "ResourceRecordSet":
${RESOURCE_RECORD_SET_SOA}
        },
        {
            "Action": "UPSERT",
            "ResourceRecordSet":
${RESOURCE_RECORD_SET_NS}
        }
    ]
}
EOF
```

## Create Amazon EKS

![EKS](https://raw.githubusercontent.com/aws-samples/eks-workshop/65b766c494a5b4f5420b2912d8373c4957163541/static/images/3-service-animated.gif
"EKS")

Create [Amazon EKS](https://aws.amazon.com/eks/) in AWS by using [eksctl](https://eksctl.io/).
It's a tool from [Weaveworks](https://weave.works/) based on official
AWS CloudFormation templates which will be used to launch and configure our
EKS cluster and nodes.

![eksctl](https://raw.githubusercontent.com/weaveworks/eksctl/c365149fc1a0b8d357139cbd6cda5aee8841c16c/logo/eksctl.png
"eksctl")

Generate SSH key if not exists:

```bash
test -f ~/.ssh/id_rsa.pub || ( install -m 0700 -d ~/.ssh && ssh-keygen -b 2048 -t rsa -f ~/.ssh/id_rsa -q -N "" )
```

Create the Amazon EKS cluster with Calico using `eksctl`:

```bash
cat > "tmp/${CLUSTER_FQDN}/eksctl.yaml" << EOF
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig
metadata:
  name: ${CLUSTER_NAME}
  region: ${AWS_DEFAULT_REGION}
  version: "1.21"
  tags: &tags
$(echo "${TAGS}" | sed "s/ /\\n    /g; s/^/    /g; s/=/: /g")
availabilityZones:
  - ${AWS_DEFAULT_REGION}a
  - ${AWS_DEFAULT_REGION}b
iam:
  withOIDC: true
  serviceAccounts:
    - metadata:
        name: aws-load-balancer-controller
        namespace: kube-system
      wellKnownPolicies:
        awsLoadBalancerController: true
    - metadata:
        name: cert-manager
        namespace: cert-manager
      wellKnownPolicies:
        certManager: true
    - metadata:
        name: cluster-autoscaler
        namespace: kube-system
      wellKnownPolicies:
        autoScaler: true
    - metadata:
        name: external-dns
        namespace: external-dns
      wellKnownPolicies:
        externalDNS: true
    - metadata:
        name: ebs-csi-controller-sa
        namespace: kube-system
      wellKnownPolicies:
        ebsCSIController: true
    - metadata:
        name: harbor
        namespace: harbor
      attachPolicyARNs:
        - ${S3_POLICY_ARN}
    - metadata:
        name: velero
        namespace: velero
      attachPolicyARNs:
        - ${S3_POLICY_ARN}
    - metadata:
        name: s3-test
        namespace: s3-test
      attachPolicyARNs:
        - ${S3_POLICY_ARN}
    - metadata:
        name: grafana
        namespace: kube-prometheus-stack
      attachPolicyARNs:
        - arn:aws:iam::aws:policy/AmazonPrometheusQueryAccess
        - arn:aws:iam::aws:policy/CloudWatchReadOnlyAccess
      attachPolicy:
        Version: 2012-10-17
        Statement:
        - Sid: AllowReadingTagsInstancesRegionsFromEC2
          Effect: Allow
          Action:
          - ec2:DescribeTags
          - ec2:DescribeInstances
          - ec2:DescribeRegions
          Resource: "*"
        - Sid: AllowReadingResourcesForTags
          Effect: Allow
          Action: tag:GetResources
          Resource: "*"
    - metadata:
        name: kube-prometheus-stack-prometheus
        namespace: kube-prometheus-stack
      attachPolicyARNs:
        - arn:aws:iam::aws:policy/AmazonPrometheusQueryAccess
        - arn:aws:iam::aws:policy/AmazonPrometheusRemoteWriteAccess
    - metadata:
        name: efs-csi-controller-sa
        namespace: kube-system
      wellKnownPolicies:
        efsCSIController: true
    - metadata:
        name: vault
        namespace: vault
      attachPolicy:
        Version: 2012-10-17
        Statement:
        - Sid: VaultKMSUnseal
          Effect: Allow
          Action:
          - kms:Encrypt
          - kms:Decrypt
          - kms:DescribeKey
          Resource:
          - "${KMS_KEY_ARN}"
    - metadata:
        name: kuard
        namespace: kuard
      attachPolicy:
        Version: 2012-10-17
        Statement:
        - Sid: AllowSecretManagerAccess
          Effect: Allow
          Action:
          - secretsmanager:GetSecretValue
          - secretsmanager:DescribeSecret
          Resource:
          - "arn:aws:secretsmanager:*:*:secret:*"
        - Sid: AllowKMSAccess
          Effect: Allow
          Action:
          - kms:Decrypt
          Resource:
          - "${KMS_KEY_ARN}"
vpc:
  nat:
    gateway: Disable
managedNodeGroups:
  - name: managed-ng-1
    amiFamily: Bottlerocket
    instanceType: t3.xlarge
    instancePrefix: ruzickap
    desiredCapacity: 3
    minSize: 2
    maxSize: 5
    volumeSize: 30
    labels:
      role: worker
    tags: *tags
    iam:
      withAddonPolicies:
        autoScaler: true
        cloudWatch: true
        ebs: true
        efs: true
    maxPodsPerNode: 1000
    volumeEncrypted: true
    volumeKmsKeyID: ${KMS_KEY_ID}
    disableIMDSv1: true
fargateProfiles:
  - name: fp-fgtest
    selectors:
      - namespace: fgtest
    tags: *tags
secretsEncryption:
  keyARN: ${KMS_KEY_ARN}
cloudWatch:
  clusterLogging:
    enableTypes:
      - authenticator
EOF

if ! eksctl get clusters --name="${CLUSTER_NAME}" &> /dev/null ; then
  eksctl create cluster --config-file "tmp/${CLUSTER_FQDN}/eksctl.yaml" --kubeconfig "${KUBECONFIG}" --without-nodegroup
  kubectl delete daemonset -n kube-system aws-node
  kubectl apply -f https://docs.projectcalico.org/archive/v3.20/manifests/calico-vxlan.yaml
  eksctl create nodegroup --config-file "tmp/${CLUSTER_FQDN}/eksctl.yaml"
fi
```

Output:

```text
2021-11-29 17:52:50 [ℹ]  eksctl version 0.75.0
2021-11-29 17:52:50 [ℹ]  using region eu-west-1
2021-11-29 17:52:50 [ℹ]  subnets for eu-west-1a - public:192.168.0.0/19 private:192.168.64.0/19
2021-11-29 17:52:50 [ℹ]  subnets for eu-west-1b - public:192.168.32.0/19 private:192.168.96.0/19
2021-11-29 17:52:50 [ℹ]  using Kubernetes version 1.21
2021-11-29 17:52:50 [ℹ]  creating EKS cluster "kube1" in "eu-west-1" region with Fargate profile
2021-11-29 17:52:50 [ℹ]  will create a CloudFormation stack for cluster itself and 0 nodegroup stack(s)
2021-11-29 17:52:50 [ℹ]  will create a CloudFormation stack for cluster itself and 0 managed nodegroup stack(s)
2021-11-29 17:52:50 [ℹ]  if you encounter any issues, check CloudFormation console or try 'eksctl utils describe-stacks --region=eu-west-1 --cluster=kube1'
2021-11-29 17:52:50 [ℹ]  Kubernetes API endpoint access will use default of {publicAccess=true, privateAccess=false} for cluster "kube1" in "eu-west-1"
2021-11-29 17:52:50 [ℹ]
2 sequential tasks: { create cluster control plane "kube1",
    7 sequential sub-tasks: {
        wait for control plane to become ready,
        tag cluster,
        update CloudWatch logging configuration,
        create fargate profiles,
        associate IAM OIDC provider,
        14 parallel sub-tasks: {
            2 sequential sub-tasks: {
                create IAM role for serviceaccount "kube-system/aws-load-balancer-controller",
                create serviceaccount "kube-system/aws-load-balancer-controller",
            },
            2 sequential sub-tasks: {
                create IAM role for serviceaccount "cert-manager/cert-manager",
                create serviceaccount "cert-manager/cert-manager",
            },
            2 sequential sub-tasks: {
                create IAM role for serviceaccount "kube-system/cluster-autoscaler",
                create serviceaccount "kube-system/cluster-autoscaler",
            },
            2 sequential sub-tasks: {
                create IAM role for serviceaccount "external-dns/external-dns",
                create serviceaccount "external-dns/external-dns",
            },
            2 sequential sub-tasks: {
                create IAM role for serviceaccount "kube-system/ebs-csi-controller-sa",
                create serviceaccount "kube-system/ebs-csi-controller-sa",
            },
            2 sequential sub-tasks: {
                create IAM role for serviceaccount "harbor/harbor",
                create serviceaccount "harbor/harbor",
            },
            2 sequential sub-tasks: {
                create IAM role for serviceaccount "velero/velero",
                create serviceaccount "velero/velero",
            },
            2 sequential sub-tasks: {
                create IAM role for serviceaccount "s3-test/s3-test",
                create serviceaccount "s3-test/s3-test",
            },
            2 sequential sub-tasks: {
                create IAM role for serviceaccount "kube-prometheus-stack/grafana",
                create serviceaccount "kube-prometheus-stack/grafana",
            },
            2 sequential sub-tasks: {
                create IAM role for serviceaccount "kube-prometheus-stack/kube-prometheus-stack-prometheus",
                create serviceaccount "kube-prometheus-stack/kube-prometheus-stack-prometheus",
            },
            2 sequential sub-tasks: {
                create IAM role for serviceaccount "kube-system/efs-csi-controller-sa",
                create serviceaccount "kube-system/efs-csi-controller-sa",
            },
            2 sequential sub-tasks: {
                create IAM role for serviceaccount "vault/vault",
                create serviceaccount "vault/vault",
            },
            2 sequential sub-tasks: {
                create IAM role for serviceaccount "kuard/kuard",
                create serviceaccount "kuard/kuard",
            },
            2 sequential sub-tasks: {
                create IAM role for serviceaccount "kube-system/aws-node",
                create serviceaccount "kube-system/aws-node",
            },
        },
        restart daemonset "kube-system/aws-node",
    }
}
2021-11-29 17:52:50 [ℹ]  building cluster stack "eksctl-kube1-cluster"
2021-11-29 17:52:50 [ℹ]  deploying stack "eksctl-kube1-cluster"
2021-11-29 17:53:21 [ℹ]  waiting for CloudFormation stack "eksctl-kube1-cluster"
...
2021-11-29 18:05:55 [ℹ]  waiting for CloudFormation stack "eksctl-kube1-cluster"
2021-11-29 18:07:59 [✔]  tagged EKS cluster (Owner=petr.ruzicka@gmail.com, Squad=Cloud_Container_Platform, compliance:na:defender=bottlerocket, Environment=Dev, Group=Cloud_Native)
2021-11-29 18:08:00 [ℹ]  waiting for requested "LoggingUpdate" in cluster "kube1" to succeed
...
2021-11-29 18:08:53 [ℹ]  waiting for requested "LoggingUpdate" in cluster "kube1" to succeed
2021-11-29 18:08:54 [✔]  configured CloudWatch logging for cluster "kube1" in "eu-west-1" (enabled types: authenticator & disabled types: api, audit, controllerManager, scheduler)
2021-11-29 18:08:54 [ℹ]  creating Fargate profile "fp-fgtest" on EKS cluster "kube1"
2021-11-29 18:13:12 [ℹ]  created Fargate profile "fp-fgtest" on EKS cluster "kube1"
2021-11-29 18:17:44 [ℹ]  building iamserviceaccount stack "eksctl-kube1-addon-iamserviceaccount-kube-system-aws-load-balancer-controller"
2021-11-29 18:17:44 [ℹ]  building iamserviceaccount stack "eksctl-kube1-addon-iamserviceaccount-kube-prometheus-stack-grafana"
2021-11-29 18:17:44 [ℹ]  building iamserviceaccount stack "eksctl-kube1-addon-iamserviceaccount-velero-velero"
2021-11-29 18:17:44 [ℹ]  building iamserviceaccount stack "eksctl-kube1-addon-iamserviceaccount-kube-system-efs-csi-controller-sa"
2021-11-29 18:17:44 [ℹ]  building iamserviceaccount stack "eksctl-kube1-addon-iamserviceaccount-kuard-kuard"
2021-11-29 18:17:44 [ℹ]  building iamserviceaccount stack "eksctl-kube1-addon-iamserviceaccount-cert-manager-cert-manager"
2021-11-29 18:17:44 [ℹ]  building iamserviceaccount stack "eksctl-kube1-addon-iamserviceaccount-kube-system-aws-node"
2021-11-29 18:17:44 [ℹ]  building iamserviceaccount stack "eksctl-kube1-addon-iamserviceaccount-kube-system-ebs-csi-controller-sa"
2021-11-29 18:17:44 [ℹ]  building iamserviceaccount stack "eksctl-kube1-addon-iamserviceaccount-kube-system-cluster-autoscaler"
2021-11-29 18:17:44 [ℹ]  building iamserviceaccount stack "eksctl-kube1-addon-iamserviceaccount-kube-prometheus-stack-kube-prometheus-stack-prometheus"
2021-11-29 18:17:44 [ℹ]  building iamserviceaccount stack "eksctl-kube1-addon-iamserviceaccount-external-dns-external-dns"
2021-11-29 18:17:44 [ℹ]  building iamserviceaccount stack "eksctl-kube1-addon-iamserviceaccount-s3-test-s3-test"
2021-11-29 18:17:44 [ℹ]  building iamserviceaccount stack "eksctl-kube1-addon-iamserviceaccount-vault-vault"
2021-11-29 18:17:44 [ℹ]  building iamserviceaccount stack "eksctl-kube1-addon-iamserviceaccount-harbor-harbor"
2021-11-29 18:17:45 [ℹ]  deploying stack "eksctl-kube1-addon-iamserviceaccount-kube-system-cluster-autoscaler"
2021-11-29 18:17:45 [ℹ]  waiting for CloudFormation stack "eksctl-kube1-addon-iamserviceaccount-kube-system-cluster-autoscaler"
2021-11-29 18:17:45 [ℹ]  deploying stack "eksctl-kube1-addon-iamserviceaccount-harbor-harbor"
2021-11-29 18:17:45 [ℹ]  waiting for CloudFormation stack "eksctl-kube1-addon-iamserviceaccount-harbor-harbor"
2021-11-29 18:17:45 [ℹ]  deploying stack "eksctl-kube1-addon-iamserviceaccount-kube-prometheus-stack-grafana"
2021-11-29 18:17:45 [ℹ]  waiting for CloudFormation stack "eksctl-kube1-addon-iamserviceaccount-kube-prometheus-stack-grafana"
2021-11-29 18:17:45 [ℹ]  deploying stack "eksctl-kube1-addon-iamserviceaccount-s3-test-s3-test"
2021-11-29 18:17:45 [ℹ]  waiting for CloudFormation stack "eksctl-kube1-addon-iamserviceaccount-s3-test-s3-test"
2021-11-29 18:17:45 [ℹ]  deploying stack "eksctl-kube1-addon-iamserviceaccount-cert-manager-cert-manager"
2021-11-29 18:17:45 [ℹ]  waiting for CloudFormation stack "eksctl-kube1-addon-iamserviceaccount-cert-manager-cert-manager"
2021-11-29 18:17:45 [ℹ]  deploying stack "eksctl-kube1-addon-iamserviceaccount-kube-system-efs-csi-controller-sa"
2021-11-29 18:17:45 [ℹ]  deploying stack "eksctl-kube1-addon-iamserviceaccount-vault-vault"
2021-11-29 18:17:45 [ℹ]  waiting for CloudFormation stack "eksctl-kube1-addon-iamserviceaccount-kube-system-efs-csi-controller-sa"
2021-11-29 18:17:45 [ℹ]  waiting for CloudFormation stack "eksctl-kube1-addon-iamserviceaccount-vault-vault"
2021-11-29 18:17:45 [ℹ]  deploying stack "eksctl-kube1-addon-iamserviceaccount-velero-velero"
2021-11-29 18:17:45 [ℹ]  waiting for CloudFormation stack "eksctl-kube1-addon-iamserviceaccount-velero-velero"
2021-11-29 18:17:45 [ℹ]  deploying stack "eksctl-kube1-addon-iamserviceaccount-kuard-kuard"
2021-11-29 18:17:45 [ℹ]  waiting for CloudFormation stack "eksctl-kube1-addon-iamserviceaccount-kuard-kuard"
2021-11-29 18:17:45 [ℹ]  deploying stack "eksctl-kube1-addon-iamserviceaccount-external-dns-external-dns"
2021-11-29 18:17:45 [ℹ]  waiting for CloudFormation stack "eksctl-kube1-addon-iamserviceaccount-external-dns-external-dns"
2021-11-29 18:17:45 [ℹ]  deploying stack "eksctl-kube1-addon-iamserviceaccount-kube-prometheus-stack-kube-prometheus-stack-prometheus"
2021-11-29 18:17:45 [ℹ]  waiting for CloudFormation stack "eksctl-kube1-addon-iamserviceaccount-kube-prometheus-stack-kube-prometheus-stack-prometheus"
2021-11-29 18:17:45 [ℹ]  deploying stack "eksctl-kube1-addon-iamserviceaccount-kube-system-aws-node"
2021-11-29 18:17:45 [ℹ]  waiting for CloudFormation stack "eksctl-kube1-addon-iamserviceaccount-kube-system-aws-node"
2021-11-29 18:17:45 [ℹ]  deploying stack "eksctl-kube1-addon-iamserviceaccount-kube-system-aws-load-balancer-controller"
2021-11-29 18:17:45 [ℹ]  waiting for CloudFormation stack "eksctl-kube1-addon-iamserviceaccount-kube-system-aws-load-balancer-controller"
2021-11-29 18:17:45 [ℹ]  deploying stack "eksctl-kube1-addon-iamserviceaccount-kube-system-ebs-csi-controller-sa"
2021-11-29 18:17:45 [ℹ]  waiting for CloudFormation stack "eksctl-kube1-addon-iamserviceaccount-kube-system-ebs-csi-controller-sa"
2021-11-29 18:18:00 [ℹ]  waiting for CloudFormation stack "eksctl-kube1-addon-iamserviceaccount-kube-system-cluster-autoscaler"
2021-11-29 18:18:00 [ℹ]  waiting for CloudFormation stack "eksctl-kube1-addon-iamserviceaccount-kube-prometheus-stack-grafana"
2021-11-29 18:18:01 [ℹ]  waiting for CloudFormation stack "eksctl-kube1-addon-iamserviceaccount-velero-velero"
2021-11-29 18:18:02 [ℹ]  waiting for CloudFormation stack "eksctl-kube1-addon-iamserviceaccount-kube-system-aws-load-balancer-controller"
2021-11-29 18:18:02 [ℹ]  waiting for CloudFormation stack "eksctl-kube1-addon-iamserviceaccount-harbor-harbor"
2021-11-29 18:18:02 [ℹ]  waiting for CloudFormation stack "eksctl-kube1-addon-iamserviceaccount-s3-test-s3-test"
2021-11-29 18:18:02 [ℹ]  waiting for CloudFormation stack "eksctl-kube1-addon-iamserviceaccount-kube-system-ebs-csi-controller-sa"
2021-11-29 18:18:03 [ℹ]  waiting for CloudFormation stack "eksctl-kube1-addon-iamserviceaccount-cert-manager-cert-manager"
2021-11-29 18:18:03 [ℹ]  waiting for CloudFormation stack "eksctl-kube1-addon-iamserviceaccount-vault-vault"
2021-11-29 18:18:03 [ℹ]  waiting for CloudFormation stack "eksctl-kube1-addon-iamserviceaccount-kuard-kuard"
2021-11-29 18:18:04 [ℹ]  waiting for CloudFormation stack "eksctl-kube1-addon-iamserviceaccount-kube-system-efs-csi-controller-sa"
2021-11-29 18:18:04 [ℹ]  waiting for CloudFormation stack "eksctl-kube1-addon-iamserviceaccount-kube-system-aws-node"
2021-11-29 18:18:04 [ℹ]  waiting for CloudFormation stack "eksctl-kube1-addon-iamserviceaccount-kube-prometheus-stack-kube-prometheus-stack-prometheus"
2021-11-29 18:18:05 [ℹ]  waiting for CloudFormation stack "eksctl-kube1-addon-iamserviceaccount-external-dns-external-dns"
2021-11-29 18:18:17 [ℹ]  waiting for CloudFormation stack "eksctl-kube1-addon-iamserviceaccount-harbor-harbor"
2021-11-29 18:18:18 [ℹ]  created namespace "harbor"
2021-11-29 18:18:18 [ℹ]  created serviceaccount "harbor/harbor"
2021-11-29 18:18:18 [ℹ]  waiting for CloudFormation stack "eksctl-kube1-addon-iamserviceaccount-s3-test-s3-test"
2021-11-29 18:18:18 [ℹ]  waiting for CloudFormation stack "eksctl-kube1-addon-iamserviceaccount-kube-system-cluster-autoscaler"
2021-11-29 18:18:18 [ℹ]  created namespace "s3-test"
2021-11-29 18:18:18 [ℹ]  created serviceaccount "s3-test/s3-test"
2021-11-29 18:18:19 [ℹ]  waiting for CloudFormation stack "eksctl-kube1-addon-iamserviceaccount-velero-velero"
2021-11-29 18:18:19 [ℹ]  waiting for CloudFormation stack "eksctl-kube1-addon-iamserviceaccount-cert-manager-cert-manager"
2021-11-29 18:18:19 [ℹ]  created namespace "velero"
2021-11-29 18:18:19 [ℹ]  waiting for CloudFormation stack "eksctl-kube1-addon-iamserviceaccount-kube-system-aws-load-balancer-controller"
2021-11-29 18:18:20 [ℹ]  created serviceaccount "velero/velero"
2021-11-29 18:18:20 [ℹ]  waiting for CloudFormation stack "eksctl-kube1-addon-iamserviceaccount-vault-vault"
2021-11-29 18:18:20 [ℹ]  waiting for CloudFormation stack "eksctl-kube1-addon-iamserviceaccount-kube-prometheus-stack-grafana"
2021-11-29 18:18:21 [ℹ]  waiting for CloudFormation stack "eksctl-kube1-addon-iamserviceaccount-kube-prometheus-stack-kube-prometheus-stack-prometheus"
2021-11-29 18:18:21 [ℹ]  created namespace "kube-prometheus-stack"
2021-11-29 18:18:21 [ℹ]  created serviceaccount "kube-prometheus-stack/kube-prometheus-stack-prometheus"
2021-11-29 18:18:21 [ℹ]  waiting for CloudFormation stack "eksctl-kube1-addon-iamserviceaccount-kube-system-ebs-csi-controller-sa"
2021-11-29 18:18:21 [ℹ]  waiting for CloudFormation stack "eksctl-kube1-addon-iamserviceaccount-kuard-kuard"
2021-11-29 18:18:24 [ℹ]  waiting for CloudFormation stack "eksctl-kube1-addon-iamserviceaccount-kube-system-efs-csi-controller-sa"
2021-11-29 18:18:24 [ℹ]  waiting for CloudFormation stack "eksctl-kube1-addon-iamserviceaccount-external-dns-external-dns"
2021-11-29 18:18:24 [ℹ]  waiting for CloudFormation stack "eksctl-kube1-addon-iamserviceaccount-kube-system-aws-node"
2021-11-29 18:18:24 [ℹ]  serviceaccount "kube-system/aws-node" already exists
2021-11-29 18:18:24 [ℹ]  updated serviceaccount "kube-system/aws-node"
2021-11-29 18:18:35 [ℹ]  waiting for CloudFormation stack "eksctl-kube1-addon-iamserviceaccount-kube-system-cluster-autoscaler"
2021-11-29 18:18:36 [ℹ]  created serviceaccount "kube-system/cluster-autoscaler"
2021-11-29 18:18:37 [ℹ]  waiting for CloudFormation stack "eksctl-kube1-addon-iamserviceaccount-kube-prometheus-stack-grafana"
2021-11-29 18:18:38 [ℹ]  waiting for CloudFormation stack "eksctl-kube1-addon-iamserviceaccount-kuard-kuard"
2021-11-29 18:18:38 [ℹ]  created serviceaccount "kube-prometheus-stack/grafana"
2021-11-29 18:18:38 [ℹ]  created namespace "kuard"
2021-11-29 18:18:38 [ℹ]  created serviceaccount "kuard/kuard"
2021-11-29 18:18:38 [ℹ]  waiting for CloudFormation stack "eksctl-kube1-addon-iamserviceaccount-vault-vault"
2021-11-29 18:18:38 [ℹ]  waiting for CloudFormation stack "eksctl-kube1-addon-iamserviceaccount-cert-manager-cert-manager"
2021-11-29 18:18:38 [ℹ]  waiting for CloudFormation stack "eksctl-kube1-addon-iamserviceaccount-kube-system-aws-load-balancer-controller"
2021-11-29 18:18:38 [ℹ]  waiting for CloudFormation stack "eksctl-kube1-addon-iamserviceaccount-kube-system-ebs-csi-controller-sa"
2021-11-29 18:18:38 [ℹ]  created namespace "vault"
2021-11-29 18:18:39 [ℹ]  created serviceaccount "vault/vault"
2021-11-29 18:18:39 [ℹ]  created namespace "cert-manager"
2021-11-29 18:18:39 [ℹ]  created serviceaccount "cert-manager/cert-manager"
2021-11-29 18:18:39 [ℹ]  created serviceaccount "kube-system/aws-load-balancer-controller"
2021-11-29 18:18:39 [ℹ]  created serviceaccount "kube-system/ebs-csi-controller-sa"
2021-11-29 18:18:41 [ℹ]  waiting for CloudFormation stack "eksctl-kube1-addon-iamserviceaccount-external-dns-external-dns"
2021-11-29 18:18:42 [ℹ]  created namespace "external-dns"
2021-11-29 18:18:42 [ℹ]  created serviceaccount "external-dns/external-dns"
2021-11-29 18:18:42 [ℹ]  waiting for CloudFormation stack "eksctl-kube1-addon-iamserviceaccount-kube-system-efs-csi-controller-sa"
2021-11-29 18:18:43 [ℹ]  created serviceaccount "kube-system/efs-csi-controller-sa"
2021-11-29 18:18:43 [ℹ]  daemonset "kube-system/aws-node" restarted
2021-11-29 18:18:43 [ℹ]  waiting for the control plane availability...
2021-11-29 18:18:43 [✔]  saved kubeconfig as "/Users/ruzickap/git/k8s-eks-bottlerocket-fargate/kubeconfig-kube1.conf"
2021-11-29 18:18:43 [ℹ]  no tasks
2021-11-29 18:18:43 [✔]  all EKS cluster resources for "kube1" have been created
2021-11-29 18:18:44 [ℹ]  kubectl command should work with "/Users/ruzickap/git/k8s-eks-bottlerocket-fargate/kubeconfig-kube1.conf", try 'kubectl --kubeconfig=/Users/ruzickap/git/k8s-eks-bottlerocket-fargate/kubeconfig-kube1.conf get nodes'
2021-11-29 18:18:44 [✔]  EKS cluster "kube1" in "eu-west-1" region is ready
daemonset.apps "aws-node" deleted
configmap/calico-config created
customresourcedefinition.apiextensions.k8s.io/bgpconfigurations.crd.projectcalico.org created
customresourcedefinition.apiextensions.k8s.io/bgppeers.crd.projectcalico.org created
customresourcedefinition.apiextensions.k8s.io/blockaffinities.crd.projectcalico.org created
customresourcedefinition.apiextensions.k8s.io/clusterinformations.crd.projectcalico.org created
customresourcedefinition.apiextensions.k8s.io/felixconfigurations.crd.projectcalico.org created
customresourcedefinition.apiextensions.k8s.io/globalnetworkpolicies.crd.projectcalico.org created
customresourcedefinition.apiextensions.k8s.io/globalnetworksets.crd.projectcalico.org created
customresourcedefinition.apiextensions.k8s.io/hostendpoints.crd.projectcalico.org created
customresourcedefinition.apiextensions.k8s.io/ipamblocks.crd.projectcalico.org created
customresourcedefinition.apiextensions.k8s.io/ipamconfigs.crd.projectcalico.org created
customresourcedefinition.apiextensions.k8s.io/ipamhandles.crd.projectcalico.org created
customresourcedefinition.apiextensions.k8s.io/ippools.crd.projectcalico.org created
customresourcedefinition.apiextensions.k8s.io/kubecontrollersconfigurations.crd.projectcalico.org created
customresourcedefinition.apiextensions.k8s.io/networkpolicies.crd.projectcalico.org created
customresourcedefinition.apiextensions.k8s.io/networksets.crd.projectcalico.org created
clusterrole.rbac.authorization.k8s.io/calico-kube-controllers created
clusterrolebinding.rbac.authorization.k8s.io/calico-kube-controllers created
clusterrole.rbac.authorization.k8s.io/calico-node created
clusterrolebinding.rbac.authorization.k8s.io/calico-node created
daemonset.apps/calico-node created
serviceaccount/calico-node created
deployment.apps/calico-kube-controllers created
serviceaccount/calico-kube-controllers created
Warning: policy/v1beta1 PodDisruptionBudget is deprecated in v1.21+, unavailable in v1.25+; use policy/v1 PodDisruptionBudget
poddisruptionbudget.policy/calico-kube-controllers created
2021-11-29 18:18:59 [ℹ]  eksctl version 0.75.0
2021-11-29 18:18:59 [ℹ]  using region eu-west-1
2021-11-29 18:19:15 [ℹ]  nodegroup "managed-ng-1" will use "" [Bottlerocket/1.21]
2021-11-29 18:19:32 [ℹ]  1 nodegroup (managed-ng-1) was included (based on the include/exclude rules)
2021-11-29 18:19:32 [ℹ]  will create a CloudFormation stack for each of 1 managed nodegroups in cluster "kube1"
2021-11-29 18:19:32 [ℹ]
2 sequential tasks: { fix cluster compatibility, 1 task: { 1 task: { create managed nodegroup "managed-ng-1" } }
}
2021-11-29 18:19:32 [ℹ]  checking cluster stack for missing resources
2021-11-29 18:19:41 [ℹ]  cluster stack has all required resources
2021-11-29 18:19:41 [ℹ]  building managed nodegroup stack "eksctl-kube1-nodegroup-managed-ng-1"
2021-11-29 18:19:41 [ℹ]  deploying stack "eksctl-kube1-nodegroup-managed-ng-1"
2021-11-29 18:19:41 [ℹ]  waiting for CloudFormation stack "eksctl-kube1-nodegroup-managed-ng-1"
...
2021-11-29 18:22:59 [ℹ]  waiting for CloudFormation stack "eksctl-kube1-nodegroup-managed-ng-1"
2021-11-29 18:23:00 [ℹ]  no tasks
2021-11-29 18:23:00 [✔]  created 0 nodegroup(s) in cluster "kube1"
2021-11-29 18:23:00 [ℹ]  nodegroup "managed-ng-1" has 3 node(s)
2021-11-29 18:23:00 [ℹ]  node "ip-192-168-31-11.eu-west-1.compute.internal" is ready
2021-11-29 18:23:00 [ℹ]  node "ip-192-168-56-82.eu-west-1.compute.internal" is ready
2021-11-29 18:23:00 [ℹ]  node "ip-192-168-60-184.eu-west-1.compute.internal" is ready
2021-11-29 18:23:00 [ℹ]  waiting for at least 2 node(s) to become ready in "managed-ng-1"
2021-11-29 18:23:00 [ℹ]  nodegroup "managed-ng-1" has 3 node(s)
2021-11-29 18:23:00 [ℹ]  node "ip-192-168-31-11.eu-west-1.compute.internal" is ready
2021-11-29 18:23:00 [ℹ]  node "ip-192-168-56-82.eu-west-1.compute.internal" is ready
2021-11-29 18:23:00 [ℹ]  node "ip-192-168-60-184.eu-west-1.compute.internal" is ready
2021-11-29 18:23:00 [✔]  created 1 managed nodegroup(s) in cluster "kube1"
2021-11-29 18:23:12 [ℹ]  checking security group configuration for all nodegroups
2021-11-29 18:23:12 [ℹ]  all nodegroups have up-to-date cloudformation templates
```

When the cluster is ready it immediately start pushing logs to CloudWatch under
`/aws/eks/kube1/cluster`.

Add add the user or role to the aws-auth ConfigMap. This is handy if you are
using different user for cli operations and different user/role for accessing
the AWS Console to see EKS Workloads in Cluster's tab.

```bash
if ! eksctl get iamidentitymapping --cluster="${CLUSTER_NAME}" --region="${AWS_DEFAULT_REGION}" --arn=${AWS_CONSOLE_ADMIN_ROLE_ARN}; then
  eksctl create iamidentitymapping --cluster="${CLUSTER_NAME}" --region="${AWS_DEFAULT_REGION}" --arn="${AWS_CONSOLE_ADMIN_ROLE_ARN}" --group system:masters --username admin
fi
```

Output:

```text
2021-11-29 18:23:13 [ℹ]  eksctl version 0.75.0
2021-11-29 18:23:13 [ℹ]  using region eu-west-1
2021-11-29 18:23:14 [ℹ]  adding identity "arn:aws:iam::7xxxxxxxxxx7:role/AxxxxxxxxxxxxN" to auth ConfigMap
```

Check the nodes+pods and max number of nodes which can be scheduled on one node:

```bash
kubectl get nodes,pods -o wide --all-namespaces
```

Output:

```text
NAME                                                STATUS   ROLES    AGE   VERSION   INTERNAL-IP      EXTERNAL-IP     OS-IMAGE                               KERNEL-VERSION   CONTAINER-RUNTIME
node/ip-192-168-31-11.eu-west-1.compute.internal    Ready    <none>   81s   v1.21.6   192.168.31.11    54.194.69.158   Bottlerocket OS 1.4.1 (aws-k8s-1.21)   5.10.68          containerd://1.5.5+bottlerocket
node/ip-192-168-56-82.eu-west-1.compute.internal    Ready    <none>   86s   v1.21.6   192.168.56.82    3.250.52.238    Bottlerocket OS 1.4.1 (aws-k8s-1.21)   5.10.68          containerd://1.5.5+bottlerocket
node/ip-192-168-60-184.eu-west-1.compute.internal   Ready    <none>   84s   v1.21.6   192.168.60.184   54.75.89.58     Bottlerocket OS 1.4.1 (aws-k8s-1.21)   5.10.68          containerd://1.5.5+bottlerocket

NAMESPACE     NAME                                           READY   STATUS    RESTARTS   AGE     IP               NODE                                           NOMINATED NODE   READINESS GATES
kube-system   pod/calico-kube-controllers-6c85b56fcb-5g5cq   1/1     Running   0          4m16s   172.16.166.130   ip-192-168-56-82.eu-west-1.compute.internal    <none>           <none>
kube-system   pod/calico-node-4whs8                          1/1     Running   0          84s     192.168.60.184   ip-192-168-60-184.eu-west-1.compute.internal   <none>           <none>
kube-system   pod/calico-node-nbjsn                          1/1     Running   0          86s     192.168.56.82    ip-192-168-56-82.eu-west-1.compute.internal    <none>           <none>
kube-system   pod/calico-node-nnhwz                          1/1     Running   0          81s     192.168.31.11    ip-192-168-31-11.eu-west-1.compute.internal    <none>           <none>
kube-system   pod/coredns-7cc879f8db-ct5bp                   1/1     Running   0          21m     172.16.166.131   ip-192-168-56-82.eu-west-1.compute.internal    <none>           <none>
kube-system   pod/coredns-7cc879f8db-h4mbs                   1/1     Running   0          21m     172.16.166.129   ip-192-168-56-82.eu-west-1.compute.internal    <none>           <none>
kube-system   pod/kube-proxy-9c9wk                           1/1     Running   0          86s     192.168.56.82    ip-192-168-56-82.eu-west-1.compute.internal    <none>           <none>
kube-system   pod/kube-proxy-gqbt7                           1/1     Running   0          81s     192.168.31.11    ip-192-168-31-11.eu-west-1.compute.internal    <none>           <none>
kube-system   pod/kube-proxy-q7pzh                           1/1     Running   0          84s     192.168.60.184   ip-192-168-60-184.eu-west-1.compute.internal   <none>           <none>
```
