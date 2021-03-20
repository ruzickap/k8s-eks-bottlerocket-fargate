# Other workloads

## Cluster API

Install `clusterctl`:

```shell
CLUSTERAPI_VERSION="0.3.11"
if [[ ! -f /usr/local/bin/clusterctl ]]; then
  curl -s -L "https://github.com/kubernetes-sigs/cluster-api/releases/download/v${CLUSTERAPI_VERSION}/clusterctl-$(uname | sed "s/./\L&/g" )-amd64" -o /usr/local/bin/clusterctl
  chmod +x /usr/local/bin/clusterctl
fi

CLUSTERAWSADM_VERSION="0.6.3"
if [[ ! -f /usr/local/bin/clusterawsadm ]]; then
  curl -s -L "https://github.com/kubernetes-sigs/cluster-api-provider-aws/releases/download/v${CLUSTERAWSADM_VERSION}/clusterawsadm-$(uname | sed "s/./\L&/g" )-amd64" -o /usr/local/bin/clusterawsadm
  chmod +x /usr/local/bin/clusterawsadm
fi
```

The `clusterawsadm` utility takes the credentials that you set as environment
variables and uses them to create a CloudFormation stack in your AWS account
with the correct IAM resources:

```shell
cat > "tmp/${CLUSTER_FQDN}/eks.config" << EOF
apiVersion: bootstrap.aws.infrastructure.cluster.x-k8s.io/v1alpha1
kind: AWSIAMConfiguration
spec:
  bootstrapUser:
    enable: true
  eks:
    enable: true
    iamRoleCreation: false
    defaultControlPlaneRole:
        disable: false
EOF

clusterawsadm bootstrap iam create-cloudformation-stack --config "tmp/${CLUSTER_FQDN}/eks.config"
```

Create the Base64 encoded credentials using `clusterawsadm`.
This command uses your environment variables and encodes
them in a value to be stored in a Kubernetes Secret.

```shell
AWS_B64ENCODED_CREDENTIALS=$(clusterawsadm bootstrap credentials encode-as-profile)
export AWS_B64ENCODED_CREDENTIALS
```

Initialize the management cluster:

```shell
export EXP_EKS=true
clusterctl init --infrastructure=aws --control-plane=aws-eks --bootstrap=aws-eks
```

Create cluster:

```shell
AWS_SSH_KEY_NAME=eksctl-${CLUSTER_NAME}-nodegroup-ng01-$(ssh-keygen -f ~/.ssh/id_rsa.pub -e -m PKCS8 | openssl pkey -pubin -outform DER | openssl md5 -c)
export AWS_SSH_KEY_NAME
export KUBERNETES_VERSION=v1.18.0
export WORKER_MACHINE_COUNT=1
export AWS_NODE_MACHINE_TYPE=t2.medium

clusterctl config cluster managed-test --flavor eks > "tmp/${CLUSTER_FQDN}/capi-eks.yaml"
kubectl apply -f "tmp/${CLUSTER_FQDN}/capi-eks.yaml"
```

Get cluster details:

```shell
kubectl get AWSManagedControlPlane,AWSMachine,AWSMachineTemplate,EKSConfig,EKSConfigTemplate
```

## HashiCorp Vault

Create a secret with your EKS access key/secret:

```bash
kubectl create namespace vault
kubectl create secret generic -n vault eks-creds \
  --from-literal=AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID?}" \
  --from-literal=AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY?}"
```

Install `vault`
[helm chart](https://artifacthub.io/packages/helm/hashicorp/vault)
and modify the
[default values](https://github.com/hashicorp/vault-helm/blob/master/values.yaml).

```bash
helm repo add hashicorp https://helm.releases.hashicorp.com
helm install --version 0.9.1 --namespace vault --wait --wait-for-jobs --values - vault hashicorp/vault << EOF
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
  extraSecretEnvironmentVars:
    - envName: AWS_ACCESS_KEY_ID
      secretName: eks-creds
      secretKey: AWS_ACCESS_KEY_ID
    - envName: AWS_SECRET_ACCESS_KEY
      secretName: eks-creds
      secretKey: AWS_SECRET_ACCESS_KEY
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
        kms_key_id = "${VAULT_KMS_KEY_ID}"
      }
      storage "file" {
        path = "/vault/data"
      }
EOF
sleep 60
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
kubectl exec -n vault vault-0 -- vault operator init -format=json | tee "tmp/${CLUSTER_FQDN}/vault_cluster-keys.json"
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
kubectl exec -n vault vault-0 -- vault status
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

```bash
VAULT_ROOT_TOKEN=$(jq -r ".root_token" "tmp/${CLUSTER_FQDN}/vault_cluster-keys.json")
export VAULT_ROOT_TOKEN
export VAULT_ADDR="https://vault.${CLUSTER_FQDN}"
export VAULT_SKIP_VERIFY="true"
```

Login to vault as root user:

```bash
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

```bash
cat > "tmp/${CLUSTER_FQDN}/my-admin-policy.hcl" << EOF
path "*" {
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}
EOF
vault policy write my-admin-policy "tmp/${CLUSTER_FQDN}/my-admin-policy.hcl"
```

Configure GitHub + Dex OIDC authentication:

```bash
vault auth enable github
vault write auth/github/config organization="${MY_GITHUB_ORG_NAME}"
vault write auth/github/map/teams/cluster-admin value=my-admin-policy

# Wait for DNS vault.${CLUSTER_FQDN} to be ready...
while [[ -z "$(dig +nocmd +noall +answer +ttlid a vault.${CLUSTER_FQDN})" ]]; do
  date
  sleep 5
done

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
```

You should be now able to login using OIDC (Dex):

```shell
rm ~/.vault-token
vault login -method=oidc
vault secrets list
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

```bash
vault secrets enable pki
```

Tune the `pki` secrets engine to issue certificates with a maximum time-to-live
(TTL) of 87600 hours:

```bash
vault secrets tune -max-lease-ttl=87600h pki
```

Generate the `root` certificate and save the certificate in `CA_cert.crt`:

```bash
vault write -field=certificate pki/root/generate/internal \
  common_name="${CLUSTER_FQDN}" \
  ttl=87600h > tmp/${CLUSTER_FQDN}/CA_cert.crt
```

Configure the PKI secrets engine certificate issuing and certificate revocation
list (CRL) endpoints to use the Vault service in the `vault` namespace:

```bash
vault write pki/config/urls \
  issuing_certificates="https://vault.${CLUSTER_FQDN}/v1/pki/ca" \
  crl_distribution_points="https://vault.${CLUSTER_FQDN}/v1/pki/crl"
```

### Generate Intermediate CA

Enable the `pki` secrets engine at the `pki_int` path:

```bash
vault secrets enable -path=pki_int pki
```

Tune the `pki_int` secrets engine to issue certificates with a maximum
time-to-live (TTL) of 43800 hours:

```bash
vault secrets tune -max-lease-ttl=43800h pki_int
```

Execute the following command to generate an intermediate and save the
CSR as `pki_intermediate.csr`:

```bash
vault write -format=json pki_int/intermediate/generate/internal \
  common_name="${CLUSTER_FQDN} Intermediate Authority" \
  | jq -r ".data.csr" > tmp/${CLUSTER_FQDN}/pki_intermediate.csr
```

Sign the intermediate certificate with the root certificate and save the
generated certificate as `intermediate.cert.pem`:

```bash
vault write -format=json pki/root/sign-intermediate csr=@tmp/${CLUSTER_FQDN}/pki_intermediate.csr \
  format=pem_bundle ttl="43800h" \
  | jq -r ".data.certificate" > tmp/${CLUSTER_FQDN}/intermediate.cert.pem
```

Once the CSR is signed and the root CA returns a certificate, it can be
imported back into Vault:

```bash
vault write pki_int/intermediate/set-signed certificate=@tmp/${CLUSTER_FQDN}/intermediate.cert.pem
```

### Configure cert-manager authentication to vault

I would like to simulate the scenario, where `cert-manager` will connect to
external Vault instance - therefore I can not use the Kubernetes authentication.
The vault instance is running on the same K8s cluster, but I will configure the
cert-manager to use [AppRole](https://cert-manager.io/docs/configuration/vault/#authenticating-via-an-approle)
to simulate "external vault access".

Set default variables:

```bash
VAULT_CERT_MANAGER_ROLE="cert-manager-role-$(echo "${CLUSTER_FQDN}" | tr . -)"
VAULT_CERT_MANAGER_POLICY="cert-manager-policy-$(echo "${CLUSTER_FQDN}" | tr . -)"
```

Enable the AppRole auth method:

```bash
vault auth enable approle
```

Create a policy that enables read access to the PKI secrets engine paths:

```bash
cat > tmp/pki_int_policy.hcl << EOF
path "pki_int*"                                   { capabilities = ["read", "list"] }
path "pki_int/roles/${VAULT_CERT_MANAGER_ROLE}"   { capabilities = ["create", "update"] }
path "pki_int/sign/${VAULT_CERT_MANAGER_ROLE}"    { capabilities = ["create", "update"] }
path "pki_int/issue/${VAULT_CERT_MANAGER_ROLE}"   { capabilities = ["create"] }
EOF
vault policy write "${VAULT_CERT_MANAGER_POLICY}" tmp/pki_int_policy.hcl
```

Create a named role:

```bash
vault write "auth/approle/role/${VAULT_CERT_MANAGER_ROLE}" policies="${VAULT_CERT_MANAGER_POLICY}"
```

Configure a role that enables the creation of certificates for domain with any
subdomains:

```bash
vault write "pki_int/roles/${VAULT_CERT_MANAGER_ROLE}" \
  allowed_domains=${CLUSTER_FQDN} \
  allow_subdomains=true \
  max_ttl=720h \
  require_cn=false
```

Get `secretId` and `roleId`:

```bash
VAULT_CERT_MANAGER_ROLE_ID=$(vault read "auth/approle/role/${VAULT_CERT_MANAGER_ROLE}/role-id" --format=json | jq -r ".data.role_id")
VAULT_CERT_MANAGER_SECRET_ID=$(vault write -f "auth/approle/role/${VAULT_CERT_MANAGER_ROLE}/secret-id" --format=json | jq -r ".data.secret_id")
```

Create K8s secret with `secretId`:

```bash
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

```bash
kubectl apply -f - << EOF
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: vault-issuer
  namespace: cert-manager
spec:
  vault:
    path: pki_int/sign/${VAULT_CERT_MANAGER_ROLE}
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
kubectl apply -f - << EOF
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: vault-certificate
  namespace: default
spec:
  secretName: vault-certificate-tls
  issuerRef:
    name: vault-issuer
    kind: ClusterIssuer
  commonName: "*.vault-test-crt.${CLUSTER_FQDN}"
  dnsNames:
  - "*.vault-test-crt.${CLUSTER_FQDN}"
  - "vault-test-crt.${CLUSTER_FQDN}"
EOF
```

## podinfo with vault certificate

Install `podinfo`
[helm chart](https://github.com/stefanprodan/podinfo/releases)
and modify the
[default values](https://github.com/stefanprodan/podinfo/blob/master/charts/podinfo/values.yaml).

```bash
helm install --version 5.1.1 --namespace default --values - podinfo-vault-test-crt sp/podinfo << EOF
ui:
  message: "Vault Certificate"
serviceMonitor:
  enabled: true
ingress:
  enabled: true
  path: /
  annotations:
    cert-manager.io/cluster-issuer: vault-issuer
  hosts:
    - podinfo.vault-test-crt.${CLUSTER_FQDN}
  tls:
    - secretName: podinfo-vault-test-crt-ingress-cert
      hosts:
        - podinfo.vault-test-crt.${CLUSTER_FQDN}
EOF
```
