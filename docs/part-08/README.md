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
cat > tmp/eks.config << EOF
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

clusterawsadm bootstrap iam create-cloudformation-stack --config tmp/eks.config
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

clusterctl config cluster managed-test --flavor eks > tmp/capi-eks.yaml
kubectl apply -f tmp/capi-eks.yaml
```

Get cluster details:

```shell
kubectl get AWSManagedControlPlane,AWSMachine,AWSMachineTemplate,EKSConfig,EKSConfigTemplate
```

## ArgoCD

Set the `ARGOCD_ADMIN_PASSWORD` with password:

```bash
# my_argocd_admin_password - https://github.com/argoproj/argo-helm/blob/master/charts/argo-cd/values.yaml#L747
ARGOCD_ADMIN_PASSWORD="\$2a\$10\$mBtAG2R9BYgawypf2tOhE.jD/G3tScaHj6C3DG52X/xjEZf4ocCm."
```

Install `argo-cd`
[helm chart](https://artifacthub.io/packages/helm/argo/argo-cd)
and modify the
[default values](https://github.com/argoproj/argo-helm/blob/master/charts/argo-cd/values.yaml).

```bash
helm repo add argo https://argoproj.github.io/argo-helm
helm install --version 2.11.3 --namespace argocd --create-namespace --values - argocd argo/argo-cd << EOF
controller:
  metrics:
    enabled: true
    serviceMonitor:
      enabled: true
dex:
  enabled: false
server:
  extraArgs:
    - --insecure
  metrics:
    enabled: true
    serviceMonitor:
      enabled: false
  ingress:
    enabled: true
    hosts:
      - argocd.${CLUSTER_FQDN}
    tls:
      - secretName: ingress-cert-${LETSENCRYPT_ENVIRONMENT}
        hosts:
          - argocd.${CLUSTER_FQDN}
  config:
    url: https://argocd.${CLUSTER_FQDN}
    # OIDC does not work for self signed certs: https://github.com/argoproj/argo-cd/issues/4344
    oidc.config: |
      name: Dex
      issuer: https://dex.${CLUSTER_FQDN}
      clientID: argocd.${CLUSTER_FQDN}
      clientSecret: ${MY_GITHUB_ORG_OAUTH_CLIENT_SECRET}
      requestedIDTokenClaims:
        groups:
          essential: true
      requestedScopes:
        - openid
        - profile
        - email
  rbacConfig:
    policy.default: role:admin
repoServer:
  metrics:
    enabled: true
    serviceMonitor:
      enabled: true
configs:
  secret:
    argocdServerAdminPassword: ${ARGOCD_ADMIN_PASSWORD}
EOF
```

Output:

```text
"argo" has been added to your repositories
manifest_sorter.go:192: info: skipping unknown hook: "crd-install"
manifest_sorter.go:192: info: skipping unknown hook: "crd-install"
NAME: argocd
LAST DEPLOYED: Thu Dec 10 16:02:58 2020
NAMESPACE: argocd
STATUS: deployed
REVISION: 1
TEST SUITE: None
NOTES:
In order to access the server UI you have the following options:

1. kubectl port-forward service/argocd-server -n argocd 8080:443

    and then open the browser on http://localhost:8080 and accept the certificate

2. enable ingress in the values file `service.ingress.enabled` and either
      - Add the annotation for ssl passthrough: https://github.com/argoproj/argo-cd/blob/master/docs/operator-manual/ingress.md#option-1-ssl-passthrough
      - Add the `--insecure` flag to `server.extraArgs` in the values file and terminate SSL at your ingress: https://github.com/argoproj/argo-cd/blob/master/docs/operator-manual/ingress.md#option-2-multiple-ingress-objects-and-hosts


After reaching the UI the first time you can login with username: admin and the password will be the
name of the server pod. You can get the pod name by running:

kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-server -o name | cut -d'/' -f 2
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
helm install --version 0.8.0 --namespace vault --wait --wait-for-jobs --values - vault hashicorp/vault << EOF
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
sleep 100
```

Output:

```text
"hashicorp" has been added to your repositories
NAME: vault
LAST DEPLOYED: Thu Dec 10 16:02:50 2020
NAMESPACE: vault
STATUS: deployed
REVISION: 1
TEST SUITE: None
NOTES:
Thank you for installing HashiCorp Vault!

Now that you have deployed Vault, you should look over the docs on using
Vault with Kubernetes available here:

https://www.vaultproject.io/docs/


Your release is named vault. To learn more about the release, try:

  $ helm status vault
  $ helm get manifest vault
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
Version                  n/a
HA Enabled               false
```

Initialize the vault server:

```bash
kubectl exec -n vault vault-0 -- vault operator init -format=json | tee tmp/vault_cluster-keys-${CLUSTER_FQDN}.json
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
Version                  1.5.4
Cluster Name             vault-cluster-678ea3b1
Cluster ID               b61bcecc-1730-14fc-e07c-dc479de0adde
HA Enabled               false
```

Configure vault policy + authentication:

```bash
VAULT_ROOT_TOKEN=$(jq -r ".root_token" tmp/vault_cluster-keys-${CLUSTER_FQDN}.json)
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
```

Create admin policy:

```bash
cat > tmp/my-admin-policy.hcl << EOF
path "*" {
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}
EOF
vault policy write my-admin-policy tmp/my-admin-policy.hcl
```

Configure GitHub + Dex OIDC authentication:

```bash
vault auth enable github
vault write auth/github/config organization="${MY_GITHUB_ORG_NAME}"
vault write auth/github/map/teams/cluster-admin value=my-admin-policy

sleep 100  # Wait for DNS vault.${CLUSTER_FQDN} to be ready...

curl -s https://letsencrypt.org/certs/fakelerootx1.pem -o tmp/fakelerootx1.pem
vault auth enable oidc
vault write auth/oidc/config \
  oidc_discovery_ca_pem=@tmp/fakelerootx1.pem \
  oidc_discovery_url="https://dex.${CLUSTER_FQDN}" \
  oidc_client_id="vault.${CLUSTER_FQDN}" \
  oidc_client_secret="${MY_GITHUB_ORG_OAUTH_CLIENT_SECRET}" \
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
