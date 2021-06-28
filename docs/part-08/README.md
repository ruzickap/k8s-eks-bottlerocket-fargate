# Other workloads

## Cluster API

Install `clusterctl`:

```shell
set -x

CLUSTERAPI_VERSION="0.3.17"
if [[ ! -f /usr/local/bin/clusterctl ]]; then
  curl -s -L "https://github.com/kubernetes-sigs/cluster-api/releases/download/v${CLUSTERAPI_VERSION}/clusterctl-$(uname | sed "s/./\L&/g" )-amd64" -o /usr/local/bin/clusterctl
  chmod +x /usr/local/bin/clusterctl
fi

CLUSTERAWSADM_VERSION="0.6.6"
if [[ ! -f /usr/local/bin/clusterawsadm ]]; then
  curl -s -L "https://github.com/kubernetes-sigs/cluster-api-provider-aws/releases/download/v${CLUSTERAWSADM_VERSION}/clusterawsadm-$(uname | sed "s/./\L&/g" )-amd64" -o /usr/local/bin/clusterawsadm
  chmod +x /usr/local/bin/clusterawsadm
fi
```

The `clusterawsadm` utility takes the credentials that you set as environment
variables and uses them to create a CloudFormation stack in your AWS account
with the correct IAM resources:

```shell
OIDC_PROVIDER_URL=$(aws eks describe-cluster --name "${CLUSTER_NAME}" --query "cluster.identity.oidc.issuer" --output text)
export OIDC_PROVIDER_URL

cat > "tmp/${CLUSTER_FQDN}/awsiamconfiguration.yaml" << EOF
apiVersion: bootstrap.aws.infrastructure.cluster.x-k8s.io/v1alpha1
kind: AWSIAMConfiguration
spec:
  eks:
    enable: true
    iamRoleCreation: true
    defaultControlPlaneRole:
      disable: false
    managedMachinePool:
      disable: false
EOF

clusterawsadm bootstrap iam create-cloudformation-stack --config "tmp/${CLUSTER_FQDN}/awsiamconfiguration.yaml"
```

Output:

```text
Attempting to create AWS CloudFormation stack cluster-api-provider-aws-sigs-k8s-io

Following resources are in the stack:

Resource                  |Type                                                                                |Status
AWS::IAM::InstanceProfile |control-plane.cluster-api-provider-aws.sigs.k8s.io                                  |CREATE_COMPLETE
AWS::IAM::InstanceProfile |controllers.cluster-api-provider-aws.sigs.k8s.io                                    |CREATE_COMPLETE
AWS::IAM::InstanceProfile |nodes.cluster-api-provider-aws.sigs.k8s.io                                          |CREATE_COMPLETE
AWS::IAM::ManagedPolicy   |arn:aws:iam::729560437327:policy/control-plane.cluster-api-provider-aws.sigs.k8s.io |CREATE_COMPLETE
AWS::IAM::ManagedPolicy   |arn:aws:iam::729560437327:policy/nodes.cluster-api-provider-aws.sigs.k8s.io         |CREATE_COMPLETE
AWS::IAM::ManagedPolicy   |arn:aws:iam::729560437327:policy/controllers.cluster-api-provider-aws.sigs.k8s.io   |CREATE_COMPLETE
AWS::IAM::Role            |control-plane.cluster-api-provider-aws.sigs.k8s.io                                  |CREATE_COMPLETE
AWS::IAM::Role            |controllers.cluster-api-provider-aws.sigs.k8s.io                                    |CREATE_COMPLETE
AWS::IAM::Role            |eks-controlplane.cluster-api-provider-aws.sigs.k8s.io                               |CREATE_COMPLETE
AWS::IAM::Role            |eks-nodegroup.cluster-api-provider-aws.sigs.k8s.io                                  |CREATE_COMPLETE
AWS::IAM::Role            |nodes.cluster-api-provider-aws.sigs.k8s.io                                          |CREATE_COMPLETE
```

Initialize the management cluster:

```shell
export AWS_REGION="${AWS_DEFAULT_REGION}"
AWS_B64ENCODED_CREDENTIALS="$(clusterawsadm bootstrap credentials encode-as-profile)"
export AWS_B64ENCODED_CREDENTIALS
export EXP_EKS=true
export EXP_EKS_IAM=true
# https://cluster-api-aws.sigs.k8s.io/topics/machinepools.html
export EXP_MACHINE_POOL=true
# https://blog.scottlowe.org/2021/03/02/deploying-a-cni-automatically-with-a-clusterresourceset/
export EXP_CLUSTER_RESOURCE_SET=true
kubectl get namespace capi-system &> /dev/null || clusterctl init -v 4 --infrastructure=aws --control-plane="aws-eks:v${CLUSTERAWSADM_VERSION}" --bootstrap="aws-eks:v${CLUSTERAWSADM_VERSION}" --core="cluster-api:v${CLUSTERAPI_VERSION}"

# Fix https://github.com/kubernetes-sigs/cluster-api-provider-aws/issues/2358
kubectl apply -f - << EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: capa-eks-control-plane-system-capa-eks-control-plane-manager-role
rules:
- apiGroups:
  - ""
  resources:
  - secrets
  verbs:
  - create
  - delete
  - get
  - list
  - patch
  - update
  - watch
- apiGroups:
  - cluster.x-k8s.io
  resources:
  - clusters
  - clusters/status
  verbs:
  - get
  - list
  - watch
- apiGroups:
  - controlplane.cluster.x-k8s.io
  resources:
  - awsmanagedcontrolplanes
  verbs:
  - create
  - delete
  - get
  - list
  - patch
  - update
  - watch
- apiGroups:
  - controlplane.cluster.x-k8s.io
  resources:
  - awsmanagedcontrolplanes/status
  verbs:
  - get
  - patch
  - update
- apiGroups:
  - ""
  resources:
  - events
  verbs:
  - create
  - get
  - list
  - patch
  - watch
- apiGroups:
  - infrastructure.cluster.x-k8s.io
  resources:
  - awsclustercontrolleridentities
  - awsclusterroleidentities
  - awsclusterstaticidentities
  verbs:
  - get
  - list
  - watch
- apiGroups:
  - infrastructure.cluster.x-k8s.io
  resources:
  - awsmachinepools
  - awsmachinepools/status
  verbs:
  - get
  - list
  - watch
- apiGroups:
  - infrastructure.cluster.x-k8s.io
  resources:
  - awsmachines
  - awsmachines/status
  verbs:
  - get
  - list
  - watch
- apiGroups:
  - infrastructure.cluster.x-k8s.io
  resources:
  - awsmanagedclusters
  - awsmanagedclusters/status
  verbs:
  - get
  - list
  - watch
- apiGroups:
  - infrastructure.cluster.x-k8s.io
  resources:
  - awsmanagedmachinepools
  - awsmanagedmachinepools/status
  verbs:
  - get
  - list
  - watch
EOF
```

Output:

```text
WARNING: `encode-as-profile` should only be used for bootstrapping.

Installing the clusterctl inventory CRD
Fetching providers
Skipping installing cert-manager as it is already installed
Installing Provider="cluster-api" Version="v0.3.17" TargetNamespace="capi-system"
Creating shared objects Provider="cluster-api" Version="v0.3.17"
Creating instance objects Provider="cluster-api" Version="v0.3.17" TargetNamespace="capi-system"
Creating inventory entry Provider="cluster-api" Version="v0.3.17" TargetNamespace="capi-system"
Installing Provider="bootstrap-aws-eks" Version="v0.6.6" TargetNamespace="capa-eks-bootstrap-system"
Creating shared objects Provider="bootstrap-aws-eks" Version="v0.6.6"
Creating instance objects Provider="bootstrap-aws-eks" Version="v0.6.6" TargetNamespace="capa-eks-bootstrap-system"
Creating inventory entry Provider="bootstrap-aws-eks" Version="v0.6.6" TargetNamespace="capa-eks-bootstrap-system"
Installing Provider="control-plane-aws-eks" Version="v0.6.6" TargetNamespace="capa-eks-control-plane-system"
Creating shared objects Provider="control-plane-aws-eks" Version="v0.6.6"
Creating instance objects Provider="control-plane-aws-eks" Version="v0.6.6" TargetNamespace="capa-eks-control-plane-system"
Creating inventory entry Provider="control-plane-aws-eks" Version="v0.6.6" TargetNamespace="capa-eks-control-plane-system"
Installing Provider="infrastructure-aws" Version="v0.6.6" TargetNamespace="capa-system"
Creating shared objects Provider="infrastructure-aws" Version="v0.6.6"
Creating instance objects Provider="infrastructure-aws" Version="v0.6.6" TargetNamespace="capa-system"
Creating inventory entry Provider="infrastructure-aws" Version="v0.6.6" TargetNamespace="capa-system"

Your management cluster has been initialized successfully!

You can now create your first workload cluster by running the following:

  clusterctl config cluster [name] --kubernetes-version [version] | kubectl apply -f -

Warning: resource clusterroles/capa-eks-control-plane-system-capa-eks-control-plane-manager-role is missing the kubectl.kubernetes.io/last-applied-configuration annotation which is required by kubectl apply. kubectl apply should only be used on resources created declaratively by either kubectl create --save-config or kubectl apply. The missing annotation will be patched automatically.
```

Create cluster:

```shell
AWS_SSH_KEY_NAME=eksctl-${CLUSTER_NAME}-nodegroup-ng01-$(ssh-keygen -f ~/.ssh/id_rsa.pub -e -m PKCS8 | openssl pkey -pubin -outform DER | openssl md5 -c)
export AWS_SSH_KEY_NAME

kubectl get namespace tenants &> /dev/null || kubectl create namespace tenants
kubectl apply -f - << EOF
apiVersion: controlplane.cluster.x-k8s.io/v1alpha3
kind: AWSManagedControlPlane
metadata:
  name: ${CLUSTER_NAME}1
  namespace: tenants
spec:
  additionalTags:
$(echo "${TAGS}" | sed "s/ /\\n    /g; s/^/    /g; s/=/: /g")
  eksClusterName: ${CLUSTER_NAME}1
  associateOIDCProvider: true
  region: "${AWS_DEFAULT_REGION}"
  sshKeyName: "${AWS_SSH_KEY_NAME}"
  # https://docs.aws.amazon.com/eks/latest/userguide/kubernetes-versions.html
  version: "v1.20.4"
  # Not working: https://github.com/kubernetes-sigs/cluster-api-provider-aws/issues/2409
  iamAuthenticatorConfig:
    mapRoles:
    - username: "admin"
      rolearn: "${AWS_CONSOLE_ADMIN_ROLE_ARN}"
      groups:
      - "system:masters"
---
apiVersion: infrastructure.cluster.x-k8s.io/v1alpha3
kind: AWSManagedCluster
metadata:
  name: ${CLUSTER_NAME}1
  namespace: tenants
---
apiVersion: cluster.x-k8s.io/v1alpha3
kind: Cluster
metadata:
  name: ${CLUSTER_NAME}1
  namespace: tenants
  labels:
    type: tenant
spec:
  clusterNetwork:
    pods:
      cidrBlocks:
      - 192.168.0.0/16
  controlPlaneRef:
    apiVersion: controlplane.cluster.x-k8s.io/v1alpha3
    kind: AWSManagedControlPlane
    name: ${CLUSTER_NAME}1
  infrastructureRef:
    apiVersion: infrastructure.cluster.x-k8s.io/v1alpha3
    kind: AWSManagedCluster
    name: ${CLUSTER_NAME}1
---
apiVersion: infrastructure.cluster.x-k8s.io/v1alpha3
kind: AWSManagedMachinePool
metadata:
  name: ${CLUSTER_NAME}1-pool-0
  namespace: tenants
spec:
  amiType: AL2_x86_64
  diskSize: 10
  instanceType: t2.small
  eksNodegroupName: ${CLUSTER_NAME}1-ng
  scaling:
    minSize: 1
    maxSize: 3
---
apiVersion: exp.cluster.x-k8s.io/v1alpha3
kind: MachinePool
metadata:
  name: ${CLUSTER_NAME}1-pool-0
  namespace: tenants
spec:
  clusterName: ${CLUSTER_NAME}1
  replicas: 2
  template:
    spec:
      bootstrap:
        dataSecretName: ""
      clusterName: ${CLUSTER_NAME}1
      infrastructureRef:
        apiVersion: infrastructure.cluster.x-k8s.io/v1alpha3
        kind: AWSManagedMachinePool
        name: ${CLUSTER_NAME}1-pool-0
EOF

kubectl wait --for=condition=Ready --timeout=30m -n tenants machinepool "${CLUSTER_NAME}1-pool-0"
```

Get cluster details:

```shell
kubectl get cluster,awsmanagedcontrolplane,machinepool,awsmanagedmachinepool,clusterresourceset -n tenants
```

Output:

```text
NAME                              PHASE
cluster.cluster.x-k8s.io/kube11   Provisioned

NAME                                                          CLUSTER   READY   VPC                     BASTION IP
awsmanagedcontrolplane.controlplane.cluster.x-k8s.io/kube11   kube11    true    vpc-08aaa8fe61f860f65

NAME                                             REPLICAS   PHASE     VERSION
machinepool.exp.cluster.x-k8s.io/kube11-pool-0   2          Running

NAME                                                                  READY   REPLICAS
awsmanagedmachinepool.infrastructure.cluster.x-k8s.io/kube11-pool-0   true    2
```

Get the cluster details:

```shell
clusterctl describe cluster --show-conditions all -n tenants "${CLUSTER_NAME}1"
```

```text
NAME                                                READY  SEVERITY  REASON   SINCE  MESSAGE
/kube11                                             True                      3m10s
├─ClusterInfrastructure - AWSManagedCluster/kube11
└─ControlPlane - AWSManagedControlPlane/kube11      True                      3m8s
              ├─ClusterSecurityGroupsReady          True                      14m
              ├─EKSAddonsConfigured                 True                      3m9s
              ├─EKSControlPlaneCreating             False  Info      created  3m10s
              ├─EKSControlPlaneReady                True                      3m9s
              ├─IAMAuthenticatorConfigured          True                      3m8s
              ├─IAMControlPlaneRolesReady           True                      14m
              ├─InternetGatewayReady                True                      16m
              ├─NatGatewaysReady                    True                      14m
              ├─RouteTablesReady                    True                      14m
              ├─SubnetsReady                        True                      16m
              └─VpcReady                            True                      16m
```

Get kubeconfig for the new EKS cluster:

```shell
clusterctl get kubeconfig "${CLUSTER_NAME}1" -n tenants > "tmp/${CLUSTER_FQDN}/kubeconfig-${CLUSTER_NAME}1.conf"
```

Display node details about new cluster `kube11`:

```shell
kubectl --kubeconfig="tmp/${CLUSTER_FQDN}/kubeconfig-${CLUSTER_NAME}1.conf" get nodes -L node.kubernetes.io/instance-type -L topology.kubernetes.io/zone
```

Output:

```text
NAME                                           STATUS   ROLES    AGE    VERSION              INSTANCE-TYPE   ZONE
ip-10-0-219-81.eu-central-1.compute.internal   Ready    <none>   104s   v1.20.4-eks-6b7464   t2.small        eu-central-1c
ip-10-0-73-114.eu-central-1.compute.internal   Ready    <none>   86s    v1.20.4-eks-6b7464   t2.small        eu-central-1a
```

Delete new EKS cluster:

```shell
kubectl delete Cluster,AWSManagedControlPlane,MachinePool,AWSManagedMachinePool,ClusterResourceSet -n tenants --all
```

## HashiCorp Vault

Install `vault`
[helm chart](https://artifacthub.io/packages/helm/hashicorp/vault)
and modify the
[default values](https://github.com/hashicorp/vault-helm/blob/master/values.yaml).

```bash
helm repo add hashicorp https://helm.releases.hashicorp.com
helm upgrade --install --version 0.13.0 --namespace vault --wait --values - vault hashicorp/vault << EOF
injector:
  metrics:
    enabled: false
server:
  ingress:
    enabled: true
    hosts:
      - host: vault.${CLUSTER_FQDN}
    tls:
      - secretName: ingress-cert-${LETSENCRYPT_ENVIRONMENT}
        hosts:
          - vault.${CLUSTER_FQDN}
  dataStorage:
    size: 1Gi
  standalone:
    enabled: true
    config: |
      ui = true
      log_level = "trace"
      listener "tcp" {
        tls_disable = 1
        address = "[::]:8200"
        cluster_address = "[::]:8201"
      }
      seal "awskms" {
        region     = "${AWS_DEFAULT_REGION}"
        kms_key_id = "${KMS_KEY_ID}"
      }
      storage "file" {
        path = "/vault/data"
      }
  serviceAccount:
    create: false
    name: vault
EOF
```

Wait for Vault to be ready:

```bash
# Wait for DNS vault.${CLUSTER_FQDN} to be ready...
while [[ -z "$(dig +nocmd +noall +answer +ttlid a "vault.${CLUSTER_FQDN}")" ]] || [[ -z "$(dig +nocmd +noall +answer +ttlid a "dex.${CLUSTER_FQDN}")" ]]; do
  date
  sleep 5
done
sleep 5
```

Check the status of the vault server - it should be sealed and uninitialized:

```bash
kubectl exec -n vault vault-0 -- vault status || true
```

Output:

```text
Key                      Value
---                      -----
Recovery Seal Type       awskms
Initialized              false
Sealed                   true
Total Recovery Shares    0
Threshold                0
Unseal Progress          0/0
Unseal Nonce             n/a
Version                  1.6.2
Storage Type             file
HA Enabled               false
```

Initialize the vault server:

```bash
test -f "tmp/${CLUSTER_FQDN}/vault_cluster-keys.json" || ( kubectl exec -n vault vault-0 -- vault operator init -format=json | tee "tmp/${CLUSTER_FQDN}/vault_cluster-keys.json" )
```

Output:

```json
{
  "unseal_keys_b64": [],
  "unseal_keys_hex": [],
  "unseal_shares": 1,
  "unseal_threshold": 1,
  "recovery_keys_b64": [
    "NWWBsGaWctRlsMu0fSM73yUU4JcWKhNE94xcmcH8cylo",
    "TvB5MPu4MUdYBd8/jqETclCX3bGKoan6060oHnANurUt",
    "p0DFz3mpwYizLk4GYZogq5W8D43k3EHUBk3mRJmkTAND",
    "xF66v2U6Cx+lulxqPcE5ePBFBHSLOdFys9X1fYfncZbn",
    "rfLZuSGJJjbhHFIDgo6/MzXbfHotwwLC51UZ9++2LLHy"
  ],
  "recovery_keys_hex": [
    "356581b0669672d465b0cbb47d233bdf2514e097162a1344f78c5c99c1fc732968",
    "4ef07930fbb831475805df3f8ea113725097ddb18aa1a9fad3ad281e700dbab52d",
    "a740c5cf79a9c188b32e4e06619a20ab95bc0f8de4dc41d4064de64499a44c0343",
    "c45ebabf653a0b1fa5ba5c6a3dc13978f04504748b39d172b3d5f57d87e77196e7",
    "adf2d9b921892636e11c5203828ebf3335db7c7a2dc302c2e75519f7efb62cb1f2"
  ],
  "recovery_keys_shares": 5,
  "recovery_keys_threshold": 3,
  "root_token": "s.xxGVe7EDNAacwKOGB8DhU7xW"
}
```

The vault server should be initialized + unsealed now:

```bash
kubectl exec -n vault vault-0 -- vault status || true
```

Output:

```text
Key                      Value
---                      -----
Recovery Seal Type       shamir
Initialized              true
Sealed                   false
Total Recovery Shares    5
Threshold                3
Version                  1.6.2
Storage Type             file
Cluster Name             vault-cluster-683b9d1d
Cluster ID               eacda9cf-7dab-f8e0-e432-0fbd49a5da7c
HA Enabled               false
```

Configure vault policy + authentication:

```shell
VAULT_ROOT_TOKEN=$(jq -r ".root_token" "tmp/${CLUSTER_FQDN}/vault_cluster-keys.json")
export VAULT_ROOT_TOKEN
export VAULT_ADDR="https://vault.${CLUSTER_FQDN}"
export VAULT_SKIP_VERIFY="true"
VAULT_CLUSTER_FQDN=$(echo "${CLUSTER_FQDN}" | tr . -)
export VAULT_CLUSTER_FQDN
```

Login to vault as root user:

```shell
vault login "${VAULT_ROOT_TOKEN}"
```

Output:

```text
Success! You are now authenticated. The token information displayed below
is already stored in the token helper. You do NOT need to run "vault login"
again. Future Vault requests will automatically use this token.

Key                  Value
---                  -----
token                s.xxGVe7EDNAacwKOGB8DhU7xW
token_accessor       W9jB3jeqG5VMIinagrN81OjG
token_duration       ∞
token_renewable      false
token_policies       ["root"]
identity_policies    []
policies             ["root"]
```

Create admin policy:

```shell
cat > "tmp/${CLUSTER_FQDN}/my-admin-policy.hcl" << EOF
path "*" {
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}
EOF
vault policy write my-admin-policy "tmp/${CLUSTER_FQDN}/my-admin-policy.hcl"
```

Configure GitHub + Dex OIDC authentication:

```shell
if ! vault auth list | grep -q github ; then
  vault auth enable github
  vault write auth/github/config organization="${MY_GITHUB_ORG_NAME}"
  vault write auth/github/map/teams/cluster-admin value=my-admin-policy

  curl -s "${LETSENCRYPT_CERTIFICATE}" -o "tmp/${CLUSTER_FQDN}/letsencrypt.pem"
  vault auth enable oidc
  vault write auth/oidc/config \
    oidc_discovery_ca_pem="@tmp/${CLUSTER_FQDN}/letsencrypt.pem" \
    oidc_discovery_url="https://dex.${CLUSTER_FQDN}" \
    oidc_client_id="vault.${CLUSTER_FQDN}" \
    oidc_client_secret="${MY_PASSWORD}" \
    default_role="my-oidc-role"
  vault write auth/oidc/role/my-oidc-role \
    bound_audiences="vault.${CLUSTER_FQDN}" \
    allowed_redirect_uris="https://vault.${CLUSTER_FQDN}/ui/vault/auth/oidc/oidc/callback,http://localhost:8250/oidc/callback" \
    user_claim="sub" \
    policies="my-admin-policy"
fi
```

You should be now able to login using OIDC (Dex):

```shell
rm ~/.vault-token
vault login -method=oidc
vault secrets list
```

Output:

```text
Complete the login via your OIDC provider. Launching browser to:

    https://dex.kube2.k8s.mylabs.dev/auth?client_id=vault.kube2.k8s.mylabs.dev&nonce=n_vaiwZVJEVlpDheqXUyUJ&redirect_uri=http%3A%2F%2Flocalhost%3A8250%2Foidc%2Fcallback&response_type=code&scope=openid&state=st_g4NPcYQyzjYT7nnoVWsK


Success! You are now authenticated. The token information displayed below
is already stored in the token helper. You do NOT need to run "vault login"
again. Future Vault requests will automatically use this token.

Key                  Value
---                  -----
token                s.9VAADnJCWKJuXtfkSRDfNE9H
token_accessor       BXl2rAkOfDGLbH7y1Zu0Zmw3
token_duration       768h
token_renewable      true
token_policies       ["default" "my-admin-policy"]
identity_policies    []
policies             ["default" "my-admin-policy"]
token_meta_role      my-oidc-role

Path          Type         Accessor              Description
----          ----         --------              -----------
cubbyhole/    cubbyhole    cubbyhole_03a9c7e4    per-token private secret storage
identity/     identity     identity_3b8d49bf     identity store
sys/          system       system_654c1a4e       system endpoints used for control, policy and debugging
```

### Generate Root CA

This should emulate your Company CA.
I used these guides to set it up:

* [Integrate a Kubernetes Cluster with an External Vault](https://learn.hashicorp.com/tutorials/vault/kubernetes-external-vault?in=vault/kubernetes#install-the-vault-helm-chart)
* [Configure Vault as a Certificate Manager in Kubernetes with Helm](https://learn.hashicorp.com/tutorials/vault/kubernetes-cert-manager)
* [cert-manager Vault](https://cert-manager.io/docs/configuration/vault/#authenticating-with-kubernetes-service-accounts)
* [Vault Agent with Kubernetes](https://learn.hashicorp.com/tutorials/vault/agent-kubernetes)
* [How to use Vault PKI Engine for Dynamic TLS Certificates on GKE](https://www.arctiq.ca/our-blog/2019/4/1/how-to-use-vault-pki-engine-for-dynamic-tls-certificates-on-gke/)

Configure PKI secrets engine:

```shell
vault secrets enable -path="${VAULT_CLUSTER_FQDN}-pki" pki
```

Tune the `${VAULT_CLUSTER_FQDN}-pki` secrets engine to issue certificates with
a maximum time-to-live (TTL) of 87600 hours:

```shell
vault secrets tune -max-lease-ttl=87600h "${VAULT_CLUSTER_FQDN}-pki"
```

Generate the `root` certificate and save the certificate in `CA_cert.crt`:

```shell
vault write -field=certificate "${VAULT_CLUSTER_FQDN}-pki/root/generate/internal" \
  common_name="${CLUSTER_FQDN}" country="CZ" organization="PA" \
  alt_names="${CLUSTER_FQDN},*.${CLUSTER_FQDN}" \
  ttl=87600h > "tmp/${CLUSTER_FQDN}/CA_cert.crt"
```

Configure the PKI secrets engine certificate issuing and certificate revocation
list (CRL) endpoints to use the Vault service in the `vault` namespace:

```shell
vault write "${VAULT_CLUSTER_FQDN}-pki/config/urls" \
  issuing_certificates="https://vault.${CLUSTER_FQDN}/v1/pki/ca" \
  crl_distribution_points="https://vault.${CLUSTER_FQDN}/v1/pki/crl"
```

### Generate Intermediate CA

Enable the `pki` secrets engine at the `${VAULT_CLUSTER_FQDN}-pki_int` path:

```shell
vault secrets enable -path="${VAULT_CLUSTER_FQDN}-pki_int" pki
```

Tune the `${VAULT_CLUSTER_FQDN}-pki_int` secrets engine to issue certificates
with a maximum time-to-live (TTL) of 43800 hours:

```shell
vault secrets tune -max-lease-ttl=43800h "${VAULT_CLUSTER_FQDN}-pki_int"
```

Execute the following command to generate an intermediate and save the
CSR as `pki_intermediate.csr`:

```shell
vault write -format=json "${VAULT_CLUSTER_FQDN}-pki_int/intermediate/generate/internal" \
  common_name="${CLUSTER_FQDN}" country="CZ" organization="PA2" \
  alt_names="${CLUSTER_FQDN},*.${CLUSTER_FQDN}" \
  | jq -r ".data.csr" > "tmp/${CLUSTER_FQDN}/pki_intermediate.csr"
```

Sign the intermediate certificate with the root certificate and save the
generated certificate as `intermediate.cert.pem`:

```shell
vault write -format=json "${VAULT_CLUSTER_FQDN}-pki/root/sign-intermediate" csr="@tmp/${CLUSTER_FQDN}/pki_intermediate.csr" \
  format=pem_bundle ttl="43800h" \
  | jq -r ".data.certificate" > "tmp/${CLUSTER_FQDN}/intermediate.cert.pem"
```

Once the CSR is signed and the root CA returns a certificate, it can be
imported back into Vault:

```shell
vault write "${VAULT_CLUSTER_FQDN}-pki_int/intermediate/set-signed" certificate="@tmp/${CLUSTER_FQDN}/intermediate.cert.pem"
```

### Configure cert-manager authentication to vault

I would like to simulate the scenario, where `cert-manager` will connect to
external Vault instance - therefore I can not use the Kubernetes authentication.
The vault instance is running on the same K8s cluster, but I will configure the
cert-manager to use [AppRole](https://cert-manager.io/docs/configuration/vault/#authenticating-via-an-approle)
to simulate "external vault access".

Enable the AppRole auth method:

```shell
vault auth enable approle
```

Create a policy that enables read access to the PKI secrets engine paths:

```shell
cat > "tmp/${CLUSTER_FQDN}/pki_int_policy.hcl" << EOF
path "${VAULT_CLUSTER_FQDN}-pki_int*"                                              { capabilities = ["read", "list"] }
path "${VAULT_CLUSTER_FQDN}-pki_int/roles/cert-manager-role-${VAULT_CLUSTER_FQDN}" { capabilities = ["create", "update"] }
path "${VAULT_CLUSTER_FQDN}-pki_int/sign/cert-manager-role-${VAULT_CLUSTER_FQDN}"  { capabilities = ["create", "update"] }
path "${VAULT_CLUSTER_FQDN}-pki_int/issue/cert-manager-role-${VAULT_CLUSTER_FQDN}" { capabilities = ["create"] }
EOF
vault policy write "cert-manager-policy-${VAULT_CLUSTER_FQDN}" "tmp/${CLUSTER_FQDN}/pki_int_policy.hcl"
```

Create a named role:

```shell
vault write "auth/approle/role/cert-manager-role-${VAULT_CLUSTER_FQDN}" policies="cert-manager-policy-${VAULT_CLUSTER_FQDN}"
```

Configure a role that enables the creation of certificates for domain with any
subdomains:

```shell
vault write "${VAULT_CLUSTER_FQDN}-pki_int/roles/cert-manager-role-${VAULT_CLUSTER_FQDN}" \
  allowed_domains="${CLUSTER_FQDN}" \
  allow_subdomains=true \
  max_ttl=720h \
  require_cn=false
```

Get `secretId` and `roleId`:

```shell
VAULT_CERT_MANAGER_ROLE_ID=$(vault read "auth/approle/role/cert-manager-role-${VAULT_CLUSTER_FQDN}/role-id" --format=json | jq -r ".data.role_id")
VAULT_CERT_MANAGER_SECRET_ID=$(vault write -f "auth/approle/role/cert-manager-role-${VAULT_CLUSTER_FQDN}/secret-id" --format=json | jq -r ".data.secret_id")
```

Create K8s secret with `secretId`:

```shell
kubectl apply -f - << EOF
apiVersion: v1
kind: Secret
type: Opaque
metadata:
  name: cert-manager-vault-approle
  namespace: cert-manager
data:
  secretId: "$(echo "${VAULT_CERT_MANAGER_SECRET_ID}" | base64)"
EOF
```

Create an Issuer, named vault-issuer, that defines Vault as a certificate
issuer:

```shell
kubectl apply -f - << EOF
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: vault-issuer
  namespace: cert-manager
spec:
  vault:
    path: ${VAULT_CLUSTER_FQDN}-pki_int/sign/cert-manager-role-${VAULT_CLUSTER_FQDN}
    server: https://vault.${CLUSTER_FQDN}
    caBundle: $(curl -s "${LETSENCRYPT_CERTIFICATE}" | base64 -w0)
    auth:
      appRole:
        path: approle
        roleId: "${VAULT_CERT_MANAGER_ROLE_ID}"
        secretRef:
          name: cert-manager-vault-approle
          key: secretId
EOF
```

Generate test certificate:

```shell
kubectl get namespace podinfo-vault &> /dev/null || kubectl create namespace podinfo-vault
kubectl apply -f - << EOF
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: podinfo-vault-certificate
  namespace: podinfo-vault
spec:
  secretName: podinfo-vault-certificate-tls
  duration: 250h
  # Minimum of renewBefore should be 240h otherwise ingress-nginx will start complaining (https://github.com/kubernetes/ingress-nginx/blob/1b76ad70ca237fdd2a6ee1017cd16fda1908df90/internal/ingress/controller/controller.go#L1225)
  renewBefore: 240h
  subject:
    organizations:
    - MyLabs
  issuerRef:
    name: vault-issuer
    kind: ClusterIssuer
  commonName: "*.vault-test-crt.${CLUSTER_FQDN}"
  dnsNames:
  - "*.vault-test-crt.${CLUSTER_FQDN}"
  - "vault-test-crt.${CLUSTER_FQDN}"
EOF
```

Check the certificates:

```shell
kubectl get secrets -n podinfo-vault podinfo-vault-certificate-tls --output=jsonpath="{.data.ca\\.crt}"| base64 --decode | openssl x509 -text -noout
kubectl get secrets -n podinfo-vault podinfo-vault-certificate-tls --output=jsonpath="{.data.tls\\.crt}" | base64 --decode | openssl x509 -text -noout
kubectl get secrets -n podinfo-vault podinfo-vault-certificate-tls --output=jsonpath="{.data.tls\\.key}" | base64 --decode | openssl rsa -check
```

## podinfo with vault certificate

Install `podinfo`
[helm chart](https://github.com/stefanprodan/podinfo/releases)
and modify the
[default values](https://github.com/stefanprodan/podinfo/blob/master/charts/podinfo/values.yaml).

```shell
helm upgrade --install --version 6.0.0 --namespace podinfo-vault --values - podinfo sp/podinfo << EOF
ui:
  message: "Vault Certificate"
serviceMonitor:
  enabled: true
ingress:
  enabled: true
  hosts:
    - host: podinfo.vault-test-crt.${CLUSTER_FQDN}
      paths:
        - path: /
          pathType: ImplementationSpecific
  tls:
    - secretName: podinfo-vault-certificate-tls
      hosts:
        - podinfo.vault-test-crt.${CLUSTER_FQDN}
EOF
```

Wait for the DNS to be resolvable and service accessible:

```shell
# Wait for DNS vault.${CLUSTER_FQDN} to be ready...
while [[ -z "$(dig +nocmd +noall +answer +ttlid a "podinfo.vault-test-crt.${CLUSTER_FQDN}")" ]]; do
  date
  sleep 5
done
```

Check the certificate:

```shell
openssl s_client -connect "podinfo.vault-test-crt.${CLUSTER_FQDN}:443" < /dev/null 2>/dev/null | sed "/Server certificate/,/-----END CERTIFICATE-----/d"
```

Output:

```text
CONNECTED(00000003)
---
Certificate chain
 0 s:CN = *.vault-test-crt.kube1.k8s.mylabs.dev
   i:CN = kube1.k8s.mylabs.dev
---
subject=CN = *.vault-test-crt.kube1.k8s.mylabs.dev

issuer=CN = kube1.k8s.mylabs.dev

---
No client certificate CA names sent
Peer signing digest: SHA256
Peer signature type: RSA-PSS
Server Temp Key: X25519, 253 bits
---
SSL handshake has read 1499 bytes and written 415 bytes
Verification error: unable to verify the first certificate
---
New, TLSv1.3, Cipher is TLS_AES_256_GCM_SHA384
Server public key is 2048 bit
Secure Renegotiation IS NOT supported
Compression: NONE
Expansion: NONE
No ALPN negotiated
Early data was not sent
Verify return code: 21 (unable to verify the first certificate)
---
```

## secrets-store-csi-driver

* [Integrating Secrets Manager secrets with Kubernetes Secrets Store CSI Driver](https://docs.aws.amazon.com/secretsmanager/latest/userguide/integrating_csi_driver.html)
* [How to use AWS Secrets & Configuration Provider with your Kubernetes Secrets
  Store CSI driver](https://aws.amazon.com/blogs/security/how-to-use-aws-secrets-configuration-provider-with-kubernetes-secrets-store-csi-driver/)

Install `secrets-store-csi-driver`
[helm chart](https://github.com/kubernetes-sigs/secrets-store-csi-driver/tree/master/charts/secrets-store-csi-driver)
and modify the
[default values](https://github.com/kubernetes-sigs/secrets-store-csi-driver/blob/master/charts/secrets-store-csi-driver/values.yaml).

```bash
helm repo add secrets-store-csi-driver https://raw.githubusercontent.com/kubernetes-sigs/secrets-store-csi-driver/master/charts
helm upgrade --install --version 0.0.23 --namespace kube-system --values - csi-secrets-store secrets-store-csi-driver/secrets-store-csi-driver << EOF
syncSecret:
  enabled: true
enableSecretRotation: true
rotationPollInterval: 60s
EOF
```

Install the AWS Provider:

```bash
kubectl apply -f https://raw.githubusercontent.com/aws/secrets-store-csi-driver-provider-aws/main/deployment/aws-provider-installer.yaml
```

## kuard

Create the SecretProviderClass which tells the AWS provider which secrets are
to be mounted in the pod:

```bash
kubectl apply -f - << EOF
apiVersion: secrets-store.csi.x-k8s.io/v1alpha1
kind: SecretProviderClass
metadata:
  name: kuard-deployment-aws-secrets
  namespace: kuard
spec:
  provider: aws
  parameters:
    objects: |
        - objectName: "${CLUSTER_FQDN}-MySecret"
          objectType: "secretsmanager"
          objectAlias: MySecret
        - objectName: "${CLUSTER_FQDN}-MySecret2"
          objectType: "secretsmanager"
          objectAlias: MySecret2
  secretObjects:
  - secretName: mysecret
    type: Opaque
    data:
    - objectName: MySecret
      key: username
  - secretName: mysecret2
    type: Opaque
    data:
    - objectName: MySecret2
      key: username
EOF
```

Install [kuard](https://github.com/kubernetes-up-and-running/kuard):

```bash
kubectl apply -f - << EOF
kind: Service
apiVersion: v1
metadata:
  name: kuard
  namespace: kuard
  labels:
    app: kuard
spec:
  selector:
    app: kuard
  ports:
    - protocol: TCP
      port: 80
      targetPort: 8080
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: kuard-deployment
  namespace: kuard
  labels:
    app: kuard
spec:
  replicas: 2
  selector:
    matchLabels:
      app: kuard
  template:
    metadata:
      labels:
        app: kuard
    spec:
      serviceAccountName: kuard
      affinity:
        podAntiAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
          - topologyKey: "kubernetes.io/hostname"
            labelSelector:
              matchLabels:
                app: kuard
      volumes:
      - name: secrets-store-inline
        csi:
          driver: secrets-store.csi.k8s.io
          readOnly: true
          volumeAttributes:
            secretProviderClass: "kuard-deployment-aws-secrets"
      containers:
      - name: kuard-deployment
        image: gcr.io/kuar-demo/kuard-amd64:v0.10.0-green
        resources:
          requests:
            cpu: 100m
            memory: "64Mi"
          limits:
            cpu: 100m
            memory: "64Mi"
        ports:
        - containerPort: 8080
        volumeMounts:
        - name: secrets-store-inline
          mountPath: "/mnt/secrets-store"
          readOnly: true
        env:
        - name: MYSECRET
          valueFrom:
            secretKeyRef:
              name: mysecret
              key: username
        - name: MYSECRET2
          valueFrom:
            secretKeyRef:
              name: mysecret2
              key: username
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: kuard
  namespace: kuard
  annotations:
    nginx.ingress.kubernetes.io/auth-url: https://oauth2-proxy.${CLUSTER_FQDN}/oauth2/auth
    nginx.ingress.kubernetes.io/auth-signin: https://oauth2-proxy.${CLUSTER_FQDN}/oauth2/start?rd=\$scheme://\$host\$request_uri
  labels:
    app: kuard
spec:
  rules:
    - host: kuard.${CLUSTER_FQDN}
      http:
        paths:
        - path: /
          pathType: ImplementationSpecific
          backend:
            service:
              name: kuard
              port:
                number: 8080
  tls:
    - hosts:
        - kuard.${CLUSTER_FQDN}
      secretName: ingress-cert-${LETSENCRYPT_ENVIRONMENT}
EOF
```

Go to these URLs and check see the credentials synced from AWS Secrets Manager:

* [https://kuard.kube1.k8s.mylabs.dev/-/env](https://kuard.kube1.k8s.mylabs.dev/-/env)
* [https://kuard.kube1.k8s.mylabs.dev/fs/mnt/secrets-store/](https://kuard.kube1.k8s.mylabs.dev/fs/mnt/secrets-store/)

You should also see it in the `kuard` secret:

```shell
kubectl wait --namespace kuard --for condition=available deployment kuard-deployment
kubectl get secrets -n kuard mysecret --template="{{.data.username}}" | base64 -d | jq
```

Output:

```json
{
  "password": "test1234",
  "username": "Administrator"
}
```
