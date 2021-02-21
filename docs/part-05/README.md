# Authentication

## Dex

```bash
helm repo add stable https://charts.helm.sh/stable
helm install --version 2.15.1 --namespace dex --create-namespace --wait --values - dex stable/dex << EOF
# https://github.com/helm/charts/blob/master/stable/dex/values.yaml
grpc: false
telemetry: true
ingress:
  enabled: true
  annotations:
    nginx.ingress.kubernetes.io/ssl-redirect: "false"
  hosts:
    - dex.${CLUSTER_FQDN}
  tls:
    - secretName: ingress-cert-${LETSENCRYPT_ENVIRONMENT}
      hosts:
        - dex.${CLUSTER_FQDN}
config:
  issuer: https://dex.${CLUSTER_FQDN}
  connectors:
    - type: github
      id: github
      name: GitHub
      config:
        clientID: ${MY_GITHUB_ORG_OAUTH_CLIENT_ID}
        clientSecret: ${MY_GITHUB_ORG_OAUTH_CLIENT_SECRET}
        redirectURI: https://dex.${CLUSTER_FQDN}/callback
        orgs:
          - name: ${MY_GITHUB_ORG_NAME}
  staticClients:
    - id: argocd.${CLUSTER_FQDN}
      redirectURIs:
        - https://argocd.${CLUSTER_FQDN}/auth/callback
      name: ArgoCD
      secret: ${MY_GITHUB_ORG_OAUTH_CLIENT_SECRET}
    - id: gangway.${CLUSTER_FQDN}
      redirectURIs:
        - https://gangway.${CLUSTER_FQDN}/callback
      name: Gangway
      secret: ${MY_GITHUB_ORG_OAUTH_CLIENT_SECRET}
    - id: harbor.${CLUSTER_FQDN}
      redirectURIs:
        - https://harbor.${CLUSTER_FQDN}/c/oidc/callback
      name: Harbor
      secret: ${MY_GITHUB_ORG_OAUTH_CLIENT_SECRET}
    - id: kiali.${CLUSTER_FQDN}
      redirectURIs:
        - https://kiali.${CLUSTER_FQDN}/
      name: Kiali
      secret: ${MY_GITHUB_ORG_OAUTH_CLIENT_SECRET}
    - id: oauth2-proxy.${CLUSTER_FQDN}
      redirectURIs:
        - https://oauth2-proxy.${CLUSTER_FQDN}/oauth2/callback
      name: OAuth2 Proxy
      secret: ${MY_GITHUB_ORG_OAUTH_CLIENT_SECRET}
    - id: vault.${CLUSTER_FQDN}
      redirectURIs:
        - https://vault.${CLUSTER_FQDN}/ui/vault/auth/oidc/oidc/callback
        - http://localhost:8250/oidc/callback
      name: Vault
      secret: ${MY_GITHUB_ORG_OAUTH_CLIENT_SECRET}
  enablePasswordDB: false
EOF
```

Output:

```text
"stable" has been added to your repositories
NAME: dex
LAST DEPLOYED: Thu Dec 10 16:01:52 2020
NAMESPACE: dex
STATUS: deployed
REVISION: 1
TEST SUITE: None
NOTES:
1. Get the application URL by running these commands:
  https://dex.k1.k8s.mylabs.dev/
```

## oauth2-proxy

Install [oauth2-proxy](https://github.com/oauth2-proxy/oauth2-proxy) to secure
the endpoints like (`prometheus.`, `alertmanager.`).

Install `oauth2-proxy`
[helm chart](https://artifacthub.io/packages/helm/k8s-at-home/oauth2-proxy)
and modify the
[default values](https://github.com/k8s-at-home/charts/blob/master/charts/oauth2-proxy/values.yaml).

```bash
helm repo add k8s-at-home https://k8s-at-home.com/charts/
helm install --version 4.3.0 --namespace oauth2-proxy --create-namespace --values - oauth2-proxy k8s-at-home/oauth2-proxy << EOF
# https://github.com/helm/charts/blob/master/stable/oauth2-proxy/values.yaml
config:
  clientID: oauth2-proxy.${CLUSTER_FQDN}
  clientSecret: "${MY_GITHUB_ORG_OAUTH_CLIENT_SECRET}"
  cookieSecret: "$(openssl rand -base64 32 | head -c 32 | base64 )"
  configFile: |-
    email_domains = [ "*" ]
    upstreams = [ "file:///dev/null" ]
    whitelist_domains = ".${CLUSTER_FQDN}"
    cookie_domains = ".${CLUSTER_FQDN}"
    provider = "oidc"
    oidc_issuer_url = "https://dex.${CLUSTER_FQDN}"
    ssl_insecure_skip_verify = "true"
    insecure_oidc_skip_issuer_verification = "true"
ingress:
  enabled: true
  hosts:
    - oauth2-proxy.${CLUSTER_FQDN}
  tls:
    - secretName: ingress-cert-${LETSENCRYPT_ENVIRONMENT}
      hosts:
        - oauth2-proxy.${CLUSTER_FQDN}
EOF
```

Output:

```text
namespace/oauth2-proxy created
WARNING: This chart is deprecated
NAME: oauth2-proxy
LAST DEPLOYED: Thu Dec 10 16:02:08 2020
NAMESPACE: oauth2-proxy
STATUS: deployed
REVISION: 1
TEST SUITE: None
NOTES:
To verify that oauth2-proxy has started, run:

  kubectl --namespace=oauth2-proxy get pods -l "app=oauth2-proxy"
```

## Gangway

Install gangway:

```bash
helm install --version 0.4.3 --namespace gangway --create-namespace --values - gangway stable/gangway << EOF
# https://github.com/helm/charts/blob/master/stable/gangway/values.yaml
trustedCACert: |
$(curl -s https://letsencrypt.org/certs/staging/letsencrypt-stg-root-x1.pem | sed  "s/^/  /" )
gangway:
  clusterName: ${CLUSTER_FQDN}
  authorizeURL: https://dex.${CLUSTER_FQDN}/auth
  tokenURL: https://dex.${CLUSTER_FQDN}/token
  audience: https://dex.${CLUSTER_FQDN}/userinfo
  redirectURL: https://gangway.${CLUSTER_FQDN}/callback
  clientID: gangway.${CLUSTER_FQDN}
  clientSecret: ${MY_GITHUB_ORG_OAUTH_CLIENT_SECRET}
  apiServerURL: https://kube-oidc-proxy.${CLUSTER_FQDN}
ingress:
  enabled: true
  annotations:
    nginx.ingress.kubernetes.io/auth-url: https://oauth2-proxy.${CLUSTER_FQDN}/oauth2/auth
    nginx.ingress.kubernetes.io/auth-signin: https://oauth2-proxy.${CLUSTER_FQDN}/oauth2/start?rd=\$scheme://\$host\$request_uri
  hosts:
    - gangway.${CLUSTER_FQDN}
  tls:
    - secretName: ingress-cert-${LETSENCRYPT_ENVIRONMENT}
      hosts:
        - gangway.${CLUSTER_FQDN}
EOF
```

Output:

```text
NAME: gangway
LAST DEPLOYED: Fri Nov 13 16:51:53 2020
NAMESPACE: gangway
STATUS: deployed
REVISION: 1
TEST SUITE: None
NOTES:
1. Get the application URL by running these commands:
  https://gangway.k1.k8s.mylabs.dev/
```

## kube-oidc-proxy

The `kube-oidc-proxy` accepting connections only via HTTPS. It's necessary to
configure ingress to communicate with the backend over HTTPS.

Install kube-oidc-proxy:

```bash
git clone --quiet https://github.com/jetstack/kube-oidc-proxy.git tmp/kube-oidc-proxy
git -C tmp/kube-oidc-proxy checkout --quiet v0.3.0

helm install --namespace kube-oidc-proxy --create-namespace --values - kube-oidc-proxy tmp/kube-oidc-proxy/deploy/charts/kube-oidc-proxy << EOF
# https://github.com/jetstack/kube-oidc-proxy/blob/master/deploy/charts/kube-oidc-proxy/values.yaml
oidc:
  clientId: gangway.${CLUSTER_FQDN}
  issuerUrl: https://dex.${CLUSTER_FQDN}
  usernameClaim: email
  caPEM: |
$(curl -s https://letsencrypt.org/certs/staging/letsencrypt-stg-root-x1.pem | sed  "s/^/    /" )
ingress:
  annotations:
    nginx.ingress.kubernetes.io/backend-protocol: HTTPS
  enabled: true
  hosts:
    - host: kube-oidc-proxy.${CLUSTER_FQDN}
      paths:
        - /
  tls:
   - secretName: ingress-cert-${LETSENCRYPT_ENVIRONMENT}
     hosts:
       - kube-oidc-proxy.${CLUSTER_FQDN}
EOF
```

If you get the credentials form the [https://gangway.k1.k8s.mylabs.dev](https://gangway.k1.k8s.mylabs.dev)
you will have the access to the cluster, but no rights there.

Add access rights to the user:

```bash
kubectl apply -f - << EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  namespace: kube-prometheus-stack
  name: secret-reader
rules:
- apiGroups: [""]
  resources: ["secrets"]
  verbs: ["get", "watch", "list"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: read-secrets
  namespace: kube-prometheus-stack
subjects:
- kind: User
  name: ${MY_EMAIL}
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: Role
  name: secret-reader
  apiGroup: rbac.authorization.k8s.io
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: pods-reader
rules:
- apiGroups: [""]
  resources: ["pods"]
  verbs: ["get", "watch", "list"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: read-pods
subjects:
- kind: User
  name: ${MY_EMAIL}
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: pods-reader
  apiGroup: rbac.authorization.k8s.io
EOF
```

The user should be able to read the secrets in `kube-prometheus-stack`
namespace:

```shell
kubectl describe secrets --insecure-skip-tls-verify -n kube-prometheus-stack "ingress-cert-${LETSENCRYPT_ENVIRONMENT}"
```

Output:

```text
Name:         ingress-cert-staging
Namespace:    kube-prometheus-stack
Labels:       kubed.appscode.com/origin.cluster=k1.k8s.mylabs.dev
              kubed.appscode.com/origin.name=ingress-cert-staging
              kubed.appscode.com/origin.namespace=cert-manager
Annotations:  cert-manager.io/alt-names: *.k1.k8s.mylabs.dev,k1.k8s.mylabs.dev
              cert-manager.io/certificate-name: ingress-cert-staging
              cert-manager.io/common-name: *.k1.k8s.mylabs.dev
              cert-manager.io/ip-sans:
              cert-manager.io/issuer-group:
              cert-manager.io/issuer-kind: ClusterIssuer
              cert-manager.io/issuer-name: letsencrypt-staging-dns
              cert-manager.io/uri-sans:
              kubed.appscode.com/origin:
                {"namespace":"cert-manager","name":"ingress-cert-staging","uid":"f1ed062c-23d9-4cf7-ad51-cfafd8a3b788","resourceVersion":"5296"}

Type:  kubernetes.io/tls

Data
====
tls.crt:  3586 bytes
tls.key:  1679 bytes
```

But it's not allowed to delete the secrets for the user:

```shell
kubectl delete secrets --insecure-skip-tls-verify -n kube-prometheus-stack "ingress-cert-${LETSENCRYPT_ENVIRONMENT}"
```

Output:

```text
Error from server (Forbidden): secrets "ingress-cert-staging" is forbidden: User "petr.ruzicka@gmail.com" cannot delete resource "secrets" in API group "" in the namespace "kube-prometheus-stack"
```

The user can not read secrets outside the `kube-prometheus-stack`:

```shell
kubectl get secrets --insecure-skip-tls-verify -n kube-system
```

Output:

```text
Error from server (Forbidden): secrets is forbidden: User "petr.ruzicka@gmail.com" cannot list resource "secrets" in API group "" in the namespace "kube-system"
```

You can see the pods "everywhere":

```shell
kubectl get pods --insecure-skip-tls-verify -n kube-system
```

Output:

```text
NAME                                                         READY   STATUS    RESTARTS   AGE
aws-for-fluent-bit-5hxlt                                     1/1     Running   0          32m
aws-for-fluent-bit-dmvzq                                     1/1     Running   0          32m
aws-node-ggfft                                               1/1     Running   0          32m
aws-node-lhlvf                                               1/1     Running   0          32m
cluster-autoscaler-aws-cluster-autoscaler-7f878bccc8-s279k   1/1     Running   0          25m
coredns-59b69b4849-6v487                                     1/1     Running   0          46m
coredns-59b69b4849-tw2dg                                     1/1     Running   0          46m
ebs-csi-controller-86785d75db-7brbr                          5/5     Running   0          31m
ebs-csi-controller-86785d75db-gn4ll                          5/5     Running   0          31m
ebs-csi-node-6h9zv                                           3/3     Running   0          31m
ebs-csi-node-r5rj7                                           3/3     Running   0          31m
kube-proxy-m6dm8                                             1/1     Running   0          32m
kube-proxy-pdmv9                                             1/1     Running   0          32m
```

But you can not delete them:

```shell
kubectl delete pods --insecure-skip-tls-verify -n kube-oidc-proxy --all
```

Output:

```text
Error from server (Forbidden): pods "kube-oidc-proxy-74bf5679fd-jhdmr" is forbidden: User "petr.ruzicka@gmail.com" cannot delete resource "pods" in API group "" in the namespace "kube-oidc-proxy"
```
