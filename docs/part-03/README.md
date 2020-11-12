# Workload

Run some workload on the K8s...

## podinfo

Install `podinfo`:

```bash
helm repo add --force-update sp https://stefanprodan.github.io/podinfo ; helm repo update > /dev/null
helm install --version 5.0.2 --values - podinfo sp/podinfo << EOF
# https://github.com/stefanprodan/podinfo/blob/master/charts/podinfo/values.yaml
serviceMonitor:
  enabled: true
ingress:
  enabled: true
  path: /
  hosts:
    - podinfo.${MY_DOMAIN}
  tls:
    - secretName: ingress-cert-${LETSENCRYPT_ENVIRONMENT}
      hosts:
        - podinfo.${MY_DOMAIN}
EOF
```

Output:

```text
"sp" has been added to your repositories
NAME: podinfo
LAST DEPLOYED: Thu Nov 12 14:20:14 2020
NAMESPACE: default
STATUS: deployed
REVISION: 1
NOTES:
1. Get the application URL by running these commands:
  https://podinfo.kube1.mylabs.dev/
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
    nginx.ingress.kubernetes.io/auth-url: https://auth.${MY_DOMAIN}/oauth2/auth
    nginx.ingress.kubernetes.io/auth-signin: https://auth.${MY_DOMAIN}/oauth2/start?rd=\$scheme://\$host\$request_uri
  path: /
  hosts:
    - podinfo-oauth.${MY_DOMAIN}
  tls:
    - secretName: ingress-cert-${LETSENCRYPT_ENVIRONMENT}
      hosts:
        - podinfo-oauth.${MY_DOMAIN}
EOF
```

Output:

```text
NAME: podinfo-oauth
LAST DEPLOYED: Thu Nov 12 14:20:17 2020
NAMESPACE: default
STATUS: deployed
REVISION: 1
NOTES:
1. Get the application URL by running these commands:
  https://podinfo-oauth.kube1.mylabs.dev/
```
