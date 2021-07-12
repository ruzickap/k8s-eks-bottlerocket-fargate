# Authentication

## Keycloak

Install `keycloak`
[helm chart](https://artifacthub.io/packages/helm/bitnami/keycloak)
and modify the
[default values](https://github.com/bitnami/charts/blob/master/bitnami/keycloak/values.yaml).

```bash
helm repo add bitnami https://charts.bitnami.com/bitnami
helm upgrade --install --version 4.0.2 --namespace keycloak --create-namespace --values - keycloak bitnami/keycloak << EOF
auth:
  adminUser: admin
  adminPassword: ${MY_PASSWORD}
  managementUser: admin
  managementPassword: ${MY_PASSWORD}
proxyAddressForwarding: true
# https://stackoverflow.com/questions/51616770/keycloak-restricting-user-management-to-certain-groups-while-enabling-manage-us
extraStartupArgs: "-Dkeycloak.profile.feature.admin_fine_grained_authz=enabled"
service:
  type: ClusterIP
ingress:
  enabled: true
  hostname: keycloak.${CLUSTER_FQDN}
  extraTls:
  - hosts:
      - keycloak.${CLUSTER_FQDN}
    secretName: ingress-cert-${LETSENCRYPT_ENVIRONMENT}
networkPolicy:
  enabled: true
metrics:
  enabled: true
  serviceMonitor:
    enabled: true
postgresql:
  persistence:
    enabled: false
keycloakConfigCli:
  enabled: true
  # Workaround for bug: https://github.com/bitnami/charts/issues/6823
  image:
    repository: adorsys/keycloak-config-cli
    tag: v4.0.1-14.0.0
  configuration:
    myrealm.yaml: |
      realm: myrealm
      enabled: true
      displayName: My Realm
      rememberMe: true
      userManagedAccessAllowed: true
      smtpServer:
        from: myrealm-keycloak@${CLUSTER_FQDN}
        fromDisplayName: Keycloak
        host: mailhog.mailhog.svc.cluster.local
        port: 1025
      clients:
      # https://oauth2-proxy.github.io/oauth2-proxy/docs/configuration/oauth_provider/#keycloak-auth-provider
      - clientId: oauth2-proxy-keycloak.${CLUSTER_FQDN}
        name: oauth2-proxy-keycloak.${CLUSTER_FQDN}
        description: "OAuth2 Proxy for Keycloak"
        secret: ${MY_PASSWORD}
        redirectUris:
        - "https://oauth2-proxy-keycloak.${CLUSTER_FQDN}/oauth2/callback"
        protocolMappers:
        - name: groupMapper
          protocol: openid-connect
          protocolMapper: oidc-group-membership-mapper
          config:
            userinfo.token.claim: "true"
            id.token.claim: "true"
            access.token.claim: "true"
            claim.name: groups
            full.path: "true"
      identityProviders:
      # https://ultimatesecurity.pro/post/okta-oidc/
      - alias: keycloak-oidc-okta
        displayName: "Okta"
        providerId: keycloak-oidc
        trustEmail: true
        config:
          clientId: ${OKTA_CLIENT_ID}
          clientSecret: ${OKTA_CLIENT_SECRET}
          tokenUrl: "${OKTA_ISSUER}/oauth2/default/v1/token"
          authorizationUrl: "${OKTA_ISSUER}/oauth2/default/v1/authorize"
          defaultScope: "openid profile email"
          syncMode: IMPORT
      - alias: dex
        displayName: "Dex"
        providerId: keycloak-oidc
        trustEmail: true
        config:
          clientId: keycloak.${CLUSTER_FQDN}
          clientSecret: ${MY_PASSWORD}
          tokenUrl: https://dex.${CLUSTER_FQDN}/token
          authorizationUrl: https://dex.${CLUSTER_FQDN}/auth
          syncMode: IMPORT
      - alias: github
        displayName: "Github"
        providerId: github
        trustEmail: true
        config:
          clientId: ${MY_GITHUB_ORG_OAUTH_KEYCLOAK_CLIENT_ID[${CLUSTER_NAME}]}
          clientSecret: ${MY_GITHUB_ORG_OAUTH_KEYCLOAK_CLIENT_SECRET[${CLUSTER_NAME}]}
      users:
      - username: myuser1
        email: myuser1@${CLUSTER_FQDN}
        enabled: true
        firstName: My Firstname 1
        lastName: My Lastname 1
        groups:
          - group-admins
        credentials:
        - type: password
          value: ${MY_PASSWORD}
      - username: myuser2
        email: myuser2@${CLUSTER_FQDN}
        enabled: true
        firstName: My Firstname 2
        lastName: My Lastname 2
        groups:
          - group-admins
        credentials:
        - type: password
          value: ${MY_PASSWORD}
      - username: myuser3
        email: myuser3@${CLUSTER_FQDN}
        enabled: true
        firstName: My Firstname 3
        lastName: My Lastname 3
        groups:
          - group-users
        credentials:
        - type: password
          value: ${MY_PASSWORD}
      - username: myuser4
        email: myuser4@${CLUSTER_FQDN}
        enabled: true
        firstName: My Firstname 4
        lastName: My Lastname 4
        groups:
          - group-users
          - group-test
        credentials:
        - type: password
          value: ${MY_PASSWORD}
      groups:
      - name: group-users
      - name: group-admins
      - name: group-test
EOF
```

## oauth2-proxy - Keycloak

Install `oauth2-proxy`
[helm chart](https://artifacthub.io/packages/helm/k8s-at-home/oauth2-proxy)
and modify the
[default values](https://github.com/k8s-at-home/charts/blob/master/charts/stable/oauth2-proxy/values.yaml).

```bash
helm repo add k8s-at-home https://k8s-at-home.com/charts/
helm upgrade --install --version 5.0.6 --namespace oauth2-proxy-keycloak --create-namespace --values - oauth2-proxy k8s-at-home/oauth2-proxy << EOF
config:
  clientID: oauth2-proxy-keycloak.${CLUSTER_FQDN}
  clientSecret: "${MY_PASSWORD}"
  cookieSecret: "$(openssl rand -base64 32 | head -c 32 | base64 )"
  configFile: |-
    email_domains = [ "*" ]
    upstreams = [ "file:///dev/null" ]
    whitelist_domains = ".${CLUSTER_FQDN}"
    cookie_domains = ".${CLUSTER_FQDN}"
    provider = "keycloak"
    login_url = "https://keycloak.${CLUSTER_FQDN}/auth/realms/myrealm/protocol/openid-connect/auth"
    redeem_url = "https://keycloak.${CLUSTER_FQDN}/auth/realms/myrealm/protocol/openid-connect/token"
    profile_url = "https://keycloak.${CLUSTER_FQDN}/auth/realms/myrealm/protocol/openid-connect/userinfo"
    validate_url = "https://keycloak.${CLUSTER_FQDN}/auth/realms/myrealm/protocol/openid-connect/userinfo"
    # allowed_groups = "/group-admins,/group-test"
    scope = "openid email profile"
    ssl_insecure_skip_verify = "true"
    insecure_oidc_skip_issuer_verification = "true"
ingress:
  enabled: true
  hosts:
    - oauth2-proxy-keycloak.${CLUSTER_FQDN}
  tls:
    - secretName: ingress-cert-${LETSENCRYPT_ENVIRONMENT}
      hosts:
        - oauth2-proxy-keycloak.${CLUSTER_FQDN}
EOF
```

## Dex

Install `dex`
[helm chart](https://artifacthub.io/packages/helm/dex/dex)
and modify the
[default values](https://github.com/dexidp/helm-charts/blob/master/charts/dex/values.yaml).

```bash
helm repo add dex https://charts.dexidp.io
helm upgrade --install --version 0.5.0 --namespace dex --create-namespace --values - dex dex/dex << EOF
ingress:
  enabled: true
  annotations:
    nginx.ingress.kubernetes.io/ssl-redirect: "false"
  hosts:
    - host: dex.${CLUSTER_FQDN}
      paths:
        - path: /
          pathType: ImplementationSpecific
  tls:
    - secretName: ingress-cert-${LETSENCRYPT_ENVIRONMENT}
      hosts:
        - dex.${CLUSTER_FQDN}
config:
  issuer: https://dex.${CLUSTER_FQDN}
  storage:
    type: kubernetes
    config:
      inCluster: true
  oauth2:
    skipApprovalScreen: true
  connectors:
    - type: github
      id: github
      name: GitHub
      config:
        clientID: ${MY_GITHUB_ORG_OAUTH_DEX_CLIENT_ID[${CLUSTER_NAME}]}
        clientSecret: ${MY_GITHUB_ORG_OAUTH_DEX_CLIENT_SECRET[${CLUSTER_NAME}]}
        redirectURI: https://dex.${CLUSTER_FQDN}/callback
        orgs:
          - name: ${MY_GITHUB_ORG_NAME}
    - type: oidc
      id: okta
      name: Okta
      config:
        issuer: ${OKTA_ISSUER}
        clientID: ${OKTA_CLIENT_ID}
        clientSecret: ${OKTA_CLIENT_SECRET}
        redirectURI: https://dex.${CLUSTER_FQDN}/callback
        scopes:
          - openid
          - profile
          - email
        getUserInfo: true
  staticClients:
    - id: argocd.${CLUSTER_FQDN}
      redirectURIs:
        - https://argocd.${CLUSTER_FQDN}/auth/callback
      name: ArgoCD
      secret: ${MY_PASSWORD}
    - id: gangway.${CLUSTER_FQDN}
      redirectURIs:
        - https://gangway.${CLUSTER_FQDN}/callback
      name: Gangway
      secret: ${MY_PASSWORD}
    - id: harbor.${CLUSTER_FQDN}
      redirectURIs:
        - https://harbor.${CLUSTER_FQDN}/c/oidc/callback
      name: Harbor
      secret: ${MY_PASSWORD}
    - id: kiali.${CLUSTER_FQDN}
      redirectURIs:
        - https://kiali.${CLUSTER_FQDN}
      name: Kiali
      secret: ${MY_PASSWORD}
    - id: keycloak.${CLUSTER_FQDN}
      redirectURIs:
        - https://keycloak.${CLUSTER_FQDN}/auth/realms/myrealm/broker/dex/endpoint
      name: Keycloak
      secret: ${MY_PASSWORD}
    - id: oauth2-proxy.${CLUSTER_FQDN}
      redirectURIs:
        - https://oauth2-proxy.${CLUSTER_FQDN}/oauth2/callback
      name: OAuth2 Proxy
      secret: ${MY_PASSWORD}
    - id: vault.${CLUSTER_FQDN}
      redirectURIs:
        - https://vault.${CLUSTER_FQDN}/ui/vault/auth/oidc/oidc/callback
        - http://localhost:8250/oidc/callback
      name: Vault
      secret: ${MY_PASSWORD}
  enablePasswordDB: false
EOF
```

## oauth2-proxy

Install [oauth2-proxy](https://github.com/oauth2-proxy/oauth2-proxy) to secure
the endpoints like (`prometheus.`, `alertmanager.`).

Install `oauth2-proxy`
[helm chart](https://artifacthub.io/packages/helm/k8s-at-home/oauth2-proxy)
and modify the
[default values](https://github.com/k8s-at-home/charts/blob/master/charts/stable/oauth2-proxy/values.yaml).

```bash
helm upgrade --install --version 5.0.6 --namespace oauth2-proxy --create-namespace --values - oauth2-proxy k8s-at-home/oauth2-proxy << EOF
config:
  clientID: oauth2-proxy.${CLUSTER_FQDN}
  clientSecret: "${MY_PASSWORD}"
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

## Gangway

Install gangway:

```bash
helm repo add stable https://charts.helm.sh/stable
helm upgrade --install --version 0.4.5 --namespace gangway --create-namespace --values - gangway stable/gangway << EOF
# https://github.com/helm/charts/blob/master/stable/gangway/values.yaml
trustedCACert: |
$(curl -s "${LETSENCRYPT_CERTIFICATE}" | sed  "s/^/  /" )
gangway:
  clusterName: ${CLUSTER_FQDN}
  authorizeURL: https://dex.${CLUSTER_FQDN}/auth
  tokenURL: https://dex.${CLUSTER_FQDN}/token
  audience: https://dex.${CLUSTER_FQDN}/userinfo
  redirectURL: https://gangway.${CLUSTER_FQDN}/callback
  clientID: gangway.${CLUSTER_FQDN}
  clientSecret: ${MY_PASSWORD}
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

## openunison

Install `openunison`
[helm chart](https://artifacthub.io/packages/helm/tremolo/openunison-k8s-login-oidc)
and modify the
[default values](https://github.com/OpenUnison/helm-charts/blob/master/openunison-k8s-login-oidc/values.yaml).

```shell
helm repo add tremolo https://nexus.tremolo.io/repository/helm/
helm upgrade --install --version 1.0.5 --namespace openunison --create-namespace --values - openunison-k8s-oidc tremolo/openunison-k8s-oidc << EOF
network:
  openunison_host: "openunison.${CLUSTER_FQDN}"
  dashboard_host: "openunison.${CLUSTER_FQDN}"
...
...
...
EOF
```

## kube-oidc-proxy

The `kube-oidc-proxy` accepting connections only via HTTPS. It's necessary to
configure ingress to communicate with the backend over HTTPS.

Install kube-oidc-proxy:

```bash
test -d "tmp/${CLUSTER_FQDN}/kube-oidc-proxy" || git clone --quiet https://github.com/jetstack/kube-oidc-proxy.git "tmp/${CLUSTER_FQDN}/kube-oidc-proxy"
git -C "tmp/${CLUSTER_FQDN}/kube-oidc-proxy" checkout --quiet v0.3.0

helm upgrade --install --namespace kube-oidc-proxy --create-namespace --values - kube-oidc-proxy "tmp/${CLUSTER_FQDN}/kube-oidc-proxy/deploy/charts/kube-oidc-proxy" << EOF
# https://github.com/jetstack/kube-oidc-proxy/blob/master/deploy/charts/kube-oidc-proxy/values.yaml
oidc:
  clientId: gangway.${CLUSTER_FQDN}
  issuerUrl: https://dex.${CLUSTER_FQDN}
  usernameClaim: email
  caPEM: |
$(curl -s ${LETSENCRYPT_CERTIFICATE} | sed  "s/^/    /" )
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

If you get the credentials form the [https://gangway.kube1.k8s.mylabs.dev](https://gangway.kube1.k8s.mylabs.dev)
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
Labels:       kubed.appscode.com/origin.cluster=kube1.k8s.mylabs.dev
              kubed.appscode.com/origin.name=ingress-cert-staging
              kubed.appscode.com/origin.namespace=cert-manager
Annotations:  cert-manager.io/alt-names: *.kube1.k8s.mylabs.dev,kube1.k8s.mylabs.dev
              cert-manager.io/certificate-name: ingress-cert-staging
              cert-manager.io/common-name: *.kube1.k8s.mylabs.dev
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
