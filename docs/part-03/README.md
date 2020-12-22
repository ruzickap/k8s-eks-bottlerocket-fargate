# Workload

Run some workload on the K8s...

## podinfo

Install `podinfo`
[helm chart](https://github.com/stefanprodan/podinfo/releases)
and modify the
[default values](https://github.com/stefanprodan/podinfo/blob/master/charts/podinfo/values.yaml).

```bash
helm repo add --force-update sp https://stefanprodan.github.io/podinfo ; helm repo update > /dev/null
helm install --version 5.1.1 --values - podinfo sp/podinfo << EOF
serviceMonitor:
  enabled: true
ingress:
  enabled: true
  path: /
  hosts:
    - podinfo.${CLUSTER_FQDN}
  tls:
    - secretName: ingress-cert-${LETSENCRYPT_ENVIRONMENT}
      hosts:
        - podinfo.${CLUSTER_FQDN}
EOF
```

Output:

```text
"sp" has been added to your repositories
NAME: podinfo
LAST DEPLOYED: Thu Dec 10 16:02:34 2020
NAMESPACE: default
STATUS: deployed
REVISION: 1
NOTES:
1. Get the application URL by running these commands:
  https://podinfo.k1.k8s.mylabs.dev/
```

Install `podinfo` secured by `oauth2`:

```bash
helm install --version 5.0.2 --values - podinfo-oauth sp/podinfo << EOF
# https://github.com/stefanprodan/podinfo/blob/master/charts/podinfo/values.yaml
serviceMonitor:
  enabled: true
ingress:
  enabled: true
  annotations:
    nginx.ingress.kubernetes.io/auth-url: https://oauth2-proxy.${CLUSTER_FQDN}/oauth2/auth
    nginx.ingress.kubernetes.io/auth-signin: https://oauth2-proxy.${CLUSTER_FQDN}/oauth2/start?rd=\$scheme://\$host\$request_uri
  path: /
  hosts:
    - podinfo-oauth.${CLUSTER_FQDN}
  tls:
    - secretName: ingress-cert-${LETSENCRYPT_ENVIRONMENT}
      hosts:
        - podinfo-oauth.${CLUSTER_FQDN}
EOF
```

## Polaris

Install `polaris`
[helm chart](https://artifacthub.io/packages/helm/fairwinds-stable/polaris)
and modify the
[default values](https://github.com/FairwindsOps/charts/blob/master/stable/polaris/values.yaml).

```bash
helm repo add fairwinds-stable https://charts.fairwinds.com/stable
helm install --version 1.3.1 --namespace polaris --create-namespace --values - polaris fairwinds-stable/polaris << EOF
dashboard:
  ingress:
    enabled: true
    annotations:
      nginx.ingress.kubernetes.io/auth-url: https://oauth2-proxy.${CLUSTER_FQDN}/oauth2/auth
      nginx.ingress.kubernetes.io/auth-signin: https://oauth2-proxy.${CLUSTER_FQDN}/oauth2/start?rd=\$scheme://\$host\$request_uri
    hosts:
      - polaris.${CLUSTER_FQDN}
    tls:
      - secretName: ingress-cert-${LETSENCRYPT_ENVIRONMENT}
        hosts:
          - polaris.${CLUSTER_FQDN}
EOF
```

Output:

```text
"fairwinds-stable" has been added to your repositories
NAME: polaris
LAST DEPLOYED: Thu Dec 10 16:02:41 2020
NAMESPACE: polaris
STATUS: deployed
REVISION: 1
TEST SUITE: None
NOTES:
** Please be patient while the chart is being deployed **

Enjoy Polaris and smooth sailing!
To view the dashboard execute this command:

kubectl port-forward --namespace polaris svc/polaris-dashboard 8080:80

Then open http://localhost:8080 in your browser.
```

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

Install `podinfo`
[helm chart](https://artifacthub.io/packages/helm/argo/argo-cd)
and modify the
[default values](https://github.com/argoproj/argo-helm/blob/master/charts/argo-cd/values.yaml).

```bash
helm repo add argo https://argoproj.github.io/argo-helm
helm install --version 2.11.0 --namespace argocd --create-namespace --values - argocd argo/argo-cd << EOF
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

## kubernetes-dashboard

Install `kubernetes-dashboard`
[helm chart](https://artifacthub.io/packages/helm/k8s-dashboard/kubernetes-dashboard)
and modify the
[default values](https://github.com/kubernetes/dashboard/blob/master/aio/deploy/helm-chart/kubernetes-dashboard/values.yaml).

```bash
helm repo add kubernetes-dashboard https://kubernetes.github.io/dashboard/
helm install --version 3.0.1 --namespace kubernetes-dashboard --create-namespace --values - kubernetes-dashboard kubernetes-dashboard/kubernetes-dashboard << EOF
extraArgs:
  - --enable-skip-login
  - --enable-insecure-login
  - --disable-settings-authorizer
protocolHttp: true
ingress:
 enabled: true
 annotations:
   nginx.ingress.kubernetes.io/auth-url: https://oauth2-proxy.${CLUSTER_FQDN}/oauth2/auth
   nginx.ingress.kubernetes.io/auth-signin: https://oauth2-proxy.${CLUSTER_FQDN}/oauth2/start?rd=\$scheme://\$host\$request_uri
 hosts:
   - kubernetes-dashboard.${CLUSTER_FQDN}
 tls:
   - secretName: ingress-cert-${LETSENCRYPT_ENVIRONMENT}
     hosts:
       - kubernetes-dashboard.${CLUSTER_FQDN}
settings:
  clusterName: ${CLUSTER_FQDN}
  itemsPerPage: 50
metricsScraper:
  enabled: true
serviceAccount:
  name: kubernetes-dashboard-admin
EOF
```

Output:

```text
"kubernetes-dashboard" has been added to your repositories
NAME: kubernetes-dashboard
LAST DEPLOYED: Thu Dec 10 16:03:04 2020
NAMESPACE: kubernetes-dashboard
STATUS: deployed
REVISION: 1
TEST SUITE: None
NOTES:
*********************************************************************************
*** PLEASE BE PATIENT: kubernetes-dashboard may take a few minutes to install ***
*********************************************************************************
From outside the cluster, the server URL(s) are:
     http://kubernetes-dashboard.k1.k8s.mylabs.dev
```

Create `clusterrolebinding` to allow the kubernetes-dashboard to access
the K8s API:

```bash
kubectl create clusterrolebinding kubernetes-dashboard-admin --clusterrole=cluster-admin --serviceaccount=kubernetes-dashboard:kubernetes-dashboard-admin
```

## Octant

```bash
helm repo add octant-dashboard https://aleveille.github.io/octant-dashboard-turnkey/repo
helm install --version 0.16.2 --namespace octant --create-namespace --values - octant octant-dashboard/octant << EOF
plugins:
  install:
    - https://github.com/bloodorangeio/octant-helm/releases/download/v0.1.0/octant-helm_0.1.0_linux_amd64.tar.gz
    -
ingress:
  enabled: true
  annotations:
    nginx.ingress.kubernetes.io/auth-url: https://oauth2-proxy.${CLUSTER_FQDN}/oauth2/auth
    nginx.ingress.kubernetes.io/auth-signin: https://oauth2-proxy.${CLUSTER_FQDN}/oauth2/start?rd=\$scheme://\$host\$request_uri
  hosts:
    - host: octant.${CLUSTER_FQDN}
      paths: ["/"]
  tls:
    - secretName: ingress-cert-${LETSENCRYPT_ENVIRONMENT}
      hosts:
        - octant.${CLUSTER_FQDN}
EOF
```

Output:

```text
"octant-dashboard" has been added to your repositories
NAME: octant
LAST DEPLOYED: Thu Dec 10 16:03:09 2020
NAMESPACE: octant
STATUS: deployed
REVISION: 1
NOTES:
1. Get the application URL by running these commands:
  https://octant.k1.k8s.mylabs.dev/
```

## kubeview

Install `kubeview`
[helm chart](https://artifacthub.io/packages/helm/kubeview/kubeview)
and modify the
[default values](https://github.com/benc-uk/kubeview/blob/master/charts/kubeview/values.yaml).

```bash
helm repo add kubeview https://benc-uk.github.io/kubeview/charts
helm install --version 0.1.17 --namespace kubeview --create-namespace --values - kubeview kubeview/kubeview << EOF
ingress:
  enabled: true
  annotations:
    nginx.ingress.kubernetes.io/auth-url: https://oauth2-proxy.${CLUSTER_FQDN}/oauth2/auth
    nginx.ingress.kubernetes.io/auth-signin: https://oauth2-proxy.${CLUSTER_FQDN}/oauth2/start?rd=\$scheme://\$host\$request_uri
  hosts:
    - host: kubeview.${CLUSTER_FQDN}
      paths: [ "/" ]
  tls:
    - secretName: ingress-cert-${LETSENCRYPT_ENVIRONMENT}
      hosts:
        - kubeview.${CLUSTER_FQDN}
EOF
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
helm repo add --force-update hashicorp https://helm.releases.hashicorp.com ; helm repo update > /dev/null
helm install --version 0.8.0 --namespace vault --values - vault hashicorp/vault << EOF
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
        kms_key_id = "${KMS_KEY_ID}"
      }
      storage "file" {
        path = "/vault/data"
      }
EOF
sleep 60
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
kubectl exec -n vault vault-0 -- vault operator init -format=json | tee tmp/vault_cluster-keys.json
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
VAULT_ROOT_TOKEN=$(jq -r ".root_token" tmp/vault_cluster-keys.json)
export VAULT_ROOT_TOKEN
export VAULT_ADDR="https://vault.${CLUSTER_FQDN}"
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

wget -q https://letsencrypt.org/certs/fakelerootx1.pem -O tmp/fakelerootx1.pem
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

## Velero

::: danger
This is not working due to dependency on [kube2iam](https://github.com/jtblin/kube2iam)
See: [https://github.com/vmware-tanzu/velero/issues/2198](https://github.com/vmware-tanzu/velero/issues/2198)
:::

Install `velero`
[helm chart](https://artifacthub.io/packages/helm/vmware-tanzu/velero)
and modify the
[default values](https://github.com/vmware-tanzu/helm-charts/blob/main/charts/velero/values.yaml).

```shell
helm repo add vmware-tanzu https://vmware-tanzu.github.io/helm-charts
helm install --version 2.14.1 --namespace velero --create-namespace --values - velero vmware-tanzu/velero << EOF
# https://github.com/vmware-tanzu/helm-charts/blob/main/charts/velero/values.yaml
initContainers:
  - name: velero-plugin-for-aws
    image: velero/velero-plugin-for-aws:v1.0.0
    imagePullPolicy: IfNotPresent
    volumeMounts:
      - mountPath: /target
        name: plugins
configuration:
  provider: aws
  backupStorageLocation:
    bucket: ${CLUSTER_FQDN}
    prefix: velero
    config:
      region: ${AWS_DEFAULT_REGION}
  volumeSnapshotLocation:
    name: aws
    config:
      region: ${AWS_DEFAULT_REGION}
# IRSA not working due to bug: https://github.com/vmware-tanzu/velero/issues/2198
# serviceAccount:
#   server:
#     annotations:
#       eks.amazonaws.com/role-arn: ${S3_POLICY_ARN}
# This should be removed in favor of IRSA (see above)
credentials:
  secretContents:
    cloud: |
      [default]
      aws_access_key=${AWS_ACCESS_KEY_ID}
      aws_secret_access_key=${AWS_SECRET_ACCESS_KEY}
deployRestic: true
EOF
```

Output:

```text
```
