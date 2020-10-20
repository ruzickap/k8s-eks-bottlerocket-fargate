# Workload

Run some workload on the K8s...

## podinfo

Install `podinfo`:

```bash
helm repo add sp https://stefanprodan.github.io/podinfo
cat << EOF | helm install --version 5.0.2 --values - podinfo sp/podinfo
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
LAST DEPLOYED: Tue Oct 20 10:10:48 2020
NAMESPACE: default
STATUS: deployed
REVISION: 1
NOTES:
1. Get the application URL by running these commands:
  https://podinfo.kube1.mylabs.dev/
```

Install `podinfo` secured by `oauth2`:

```bash
cat << EOF | helm install --version 5.0.2 --values - podinfo-oauth sp/podinfo
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
